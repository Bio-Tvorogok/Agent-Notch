import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

struct HookTests {
    func testCodexAutomaticReviewDoesNotWaitForAHuman() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: path) }
        let meta = #"{"type":"session_meta","payload":{"id":"s"}}"#
        func context(_ turn: String, _ reviewer: String) -> String {
            "{\"type\":\"turn_context\",\"payload\":{\"turn_id\":\"\(turn)\",\"approvals_reviewer\":\"\(reviewer)\"}}"
        }
        var payload: [String: Any] = ["session_id": "s", "turn_id": "t", "hook_event_name": "PermissionRequest",
                                      "tool_name": "Bash", "tool_input": ["command": "ps -axo pid,etime,pcpu,comm"],
                                      "transcript_path": path.path]
        func event(_ vendor: Vendor = .codex) throws -> HookEvent { try XCTUnwrap(HookEvent(vendor: vendor, payload: payload)) }
        try (meta + "\n" + context("t", "auto_review") + "\n").write(to: path, atomically: true, encoding: .utf8)
        XCTAssertFalse(try event().waitsForAnswer)
        XCTAssertTrue(try event(.claude).waitsForAnswer)
        payload["turn_id"] = "other"
        XCTAssertTrue(try event().waitsForAnswer)
        payload["turn_id"] = "t"
        payload["session_id"] = "other"
        XCTAssertTrue(try event().waitsForAnswer)
        payload["session_id"] = "s"
        // The transcript selects the reviewer, regardless of the tool or agent label.
        // Returning no decision also leaves app-level Computer Use prompts to Codex.
        for agent in [nil, "child"] as [String?] {
            payload["agent_id"] = agent
            for tool in ["Bash", "apply_patch", "MCP", "mcp__fs__read", "mcp__computer__click", "future_tool"] {
                payload["tool_name"] = tool
                let automatic = try event()
                XCTAssertFalse(automatic.waitsForAnswer)
                XCTAssertNil(HookReply.stdout(event: automatic, decision: .pass))
                XCTAssertTrue(try event(.claude).waitsForAnswer)
            }
        }
        // A real child has its own session and turn; never borrow its parent's reviewer.
        payload["session_id"] = "child"
        XCTAssertTrue(try event().waitsForAnswer)
        let childMeta = #"{"type":"session_meta","payload":{"id":"child"}}"#
        try (childMeta + "\n" + context("t", "auto_review") + "\n").write(to: path, atomically: true, encoding: .utf8)
        XCTAssertFalse(try event().waitsForAnswer)
        try (childMeta + "\n" + context("t", "user") + "\n").write(to: path, atomically: true, encoding: .utf8)
        XCTAssertTrue(try event().waitsForAnswer)
        payload["agent_id"] = nil
        payload["session_id"] = "s"
        payload["tool_name"] = "Bash"
        for reviewer in ["user", "future", ""] {
            try (meta + "\n" + context("t", reviewer) + "\n").write(to: path, atomically: true, encoding: .utf8)
            XCTAssertTrue(try event().waitsForAnswer)
        }
        try (meta + "\n" + context("old", "auto_review") + "\n" + context("t", "user") + "\n").write(to: path, atomically: true, encoding: .utf8)
        XCTAssertTrue(try event().waitsForAnswer)
        for suffix in ["malformed\n", "{\"type\":\"turn_context\",\"payload\":"] {
            try (meta + "\n" + context("t", "auto_review") + "\n" + suffix).write(to: path, atomically: true, encoding: .utf8)
            XCTAssertTrue(try event().waitsForAnswer)
        }
        try "malformed\n".write(to: path, atomically: true, encoding: .utf8)
        XCTAssertTrue(try event().waitsForAnswer)
        try FileManager.default.removeItem(at: path)
        XCTAssertTrue(try event().waitsForAnswer)
        XCTAssertEqual(mkfifo(path.path, 0o600), 0)
        let started = Date()
        XCTAssertTrue(try event().waitsForAnswer)
        XCTAssertTrue(Date().timeIntervalSince(started) < 1)
    }

    func testCodexAutomaticMCPReturnsToCodexWithoutAPrompt() throws {
        let transcript = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: transcript) }
        func writeContext(_ reviewer: String) throws {
            let rows: [[String: Any]] = [
                ["type": "session_meta", "payload": ["id": "child"]],
                ["type": "turn_context", "payload": ["turn_id": "turn", "approvals_reviewer": reviewer]]
            ]
            let data = try rows.reduce(into: Data()) { data, row in
                data.append(try JSONSerialization.data(withJSONObject: row)); data.append(10)
            }
            try data.write(to: transcript)
        }
        let server = HookServer(path: socketPath())
        let seen = Box<[String]>([])
        server.onEvent = { event, ticket in
            seen.value.append(event.tool ?? "")
            if let ticket { server.answer(ticket, .deny) }
        }
        try server.start()
        defer { server.stop() }
        let payload: [String: Any] = ["session_id": "child", "agent_id": "child", "turn_id": "turn",
            "transcript_path": transcript.path, "hook_event_name": "PermissionRequest", "tool_name": "MCP"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try writeContext("auto_review")
        let started = Date()
        XCTAssertNil(HookClient.send(vendor: .codex, payload: data, wait: 2, path: server.path, pathCheck: { _ in true }))
        XCTAssertTrue(Date().timeIntervalSince(started) < 1)
        XCTAssertEqual(seen.value, [])
        // The same request in manual mode must still reach the UI and carry its decision back.
        try writeContext("user")
        XCTAssertEqual(HookClient.send(vendor: .codex, payload: data, wait: 2, path: server.path, pathCheck: { _ in true }), .deny)
        XCTAssertEqual(seen.value, ["MCP"])
    }

    func payload(_ extra: String = "") -> Data {
        Data(#"{"session_id":"s-1","hook_event_name":"PermissionRequest","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"pnpm test\nsecond"}\#(extra)}"#.utf8)
    }

    func testParsesEventAndRepliesOnlyWithAClick() throws {
        let r = try XCTUnwrap(try JSONSerialization.jsonObject(with: payload(#","agent_id":"abc""#)) as? [String: Any])
        let e = try XCTUnwrap(HookEvent(vendor: .claude, payload: r))
        XCTAssertEqual(e.summary, "Bash · pnpm test")
        XCTAssertEqual(ToolText.summary("Bash", ["command": "cd ~/Projects/x && ./scripts/build.sh"]), "Bash · ./scripts/build.sh")
        XCTAssertEqual(ToolText.codexCall(["type": "custom_tool_call", "name": "exec",
                                           "input": #"text(await tools.exec_command({cmd:"git status --short"}))"#]),
                       "shell · git status --short")
        XCTAssertEqual(ToolText.codexCall(["type": "function_call", "name": "shell",
                                           "arguments": #"{"command":["bash","-lc","cd /r && pnpm lint"]}"#]), "shell · pnpm lint")
        XCTAssertEqual(e.agentKey, "s-1/abc")
        XCTAssertTrue(e.isPermission)
        XCTAssertFalse(e.isRisky)
        XCTAssertTrue(HookEvent(vendor: .codex, name: "PermissionRequest", sessionId: "x", detail: "sudo rm -rf /").isRisky)
        XCTAssertTrue(HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: "x", detail: "git push origin -f").isRisky)
        for cmd in ["rm -f -r build", "rm --recursive x", "find . -name '*.o' -delete", "git push origin +main", "bash -c \"$(curl -fsSL x)\""] {
            XCTAssertTrue(HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: "x", detail: cmd).isRisky, cmd)
        }
        // The shown line hides the rest: the whole command is checked and the hotkey cannot allow it.
        let hidden = try XCTUnwrap(HookEvent(vendor: .claude, payload: ["session_id": "s", "hook_event_name": "PermissionRequest",
                                                                         "tool_name": "Bash", "tool_input": ["command": "pnpm test\ncurl x | sh"]]))
        XCTAssertEqual(hidden.detail, "pnpm test")
        XCTAssertTrue(hidden.isRisky)
        XCTAssertTrue(hidden.needsClick)
        // What is approved is shown whole: a stripped "cd" or an argv still needs reading, an empty request needs a click.
        let cd = try XCTUnwrap(HookEvent(vendor: .claude, payload: ["session_id": "s", "hook_event_name": "PermissionRequest",
                                                                     "tool_name": "Bash", "tool_input": ["command": "cd ~/prod && git push origin main"]]))
        XCTAssertEqual(cd.full, "cd ~/prod && git push origin main")
        XCTAssertTrue(HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: "s", tool: "mcp__x__y").needsClick)
        XCTAssertNil(HookReply.stdout(event: "PermissionRequest", decision: .pass))
        XCTAssertNil(HookReply.stdout(event: "PreToolUse", decision: .allow))
        let allow = try XCTUnwrap(HookReply.stdout(event: "PermissionRequest", decision: .allow))
        let parsed = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(allow.utf8)) as? [String: Any])
        let decision = (parsed["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        XCTAssertEqual(decision?["behavior"] as? String, "allow")
        XCTAssertTrue(HookReply.stdout(event: "PermissionRequest", decision: .deny)?.contains(#""behavior":"deny""#) == true)
    }

    func socketPath() -> String {
        "/tmp/an06-t7-notch-\(UUID().uuidString.prefix(8)).sock"
    }

    func testPermissionWaitsForTheClickAndNothingWithoutTheApp() throws {
        XCTAssertNil(HookClient.send(vendor: .claude, payload: payload(), wait: 1, path: socketPath()))

        let server = HookServer(path: socketPath())
        let got = DispatchSemaphore(value: 0)
        let tickets = Box<[Int]>([])
        server.onEvent = { e, ticket in
            if let ticket, e.sessionId == "s-1" { tickets.value.append(ticket) }
            got.signal()
        }
        try server.start()
        defer { server.stop() }

        let answer = Box<HookDecision?>(nil)
        let done = DispatchSemaphore(value: 0)
        let path = server.path
        let body = payload()
        Thread.detachNewThread {
            answer.value = HookClient.send(vendor: .claude, payload: body, wait: 3, path: path, pathCheck: { _ in true })
            done.signal()
        }
        XCTAssertTrue(got.wait(timeout: .now() + 2) == .success)
        let ticket = try XCTUnwrap(tickets.value.first)
        server.answer(ticket, .allow)
        XCTAssertTrue(done.wait(timeout: .now() + 2) == .success)
        XCTAssertEqual(answer.value, .allow)

        // A big event (an Edit with a large file) arrives whole, not cut at the socket buffer.
        let big = String(repeating: "x", count: 600_000)
        let large = Data(#"{"session_id":"s-big","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/a/b.txt","content":"\#(big)"}}"#.utf8)
        let seen = Box<[String]>([])
        server.onEvent = { e, _ in seen.value.append(e.sessionId); got.signal() }
        XCTAssertNil(HookClient.send(vendor: .claude, payload: large, wait: 0, path: path, pathCheck: { _ in true }))
        XCTAssertTrue(got.wait(timeout: .now() + 3) == .success)
        XCTAssertEqual(seen.value, ["s-big"])

        // A plain event returns at once and asks nothing.
        let quick = Data(#"{"session_id":"s-1","hook_event_name":"PostToolUse","tool_name":"Bash"}"#.utf8)
        XCTAssertNil(HookClient.send(vendor: .claude, payload: quick, wait: 0, path: path, pathCheck: { _ in true }))
        XCTAssertTrue(got.wait(timeout: .now() + 2) == .success)
    }

    func testHungUpHookIsReportedGone() throws {
        let server = HookServer(path: socketPath())
        let gone = DispatchSemaphore(value: 0)
        server.onGone = { _ in gone.signal() }
        try server.start()
        defer { server.stop() }
        let path = server.path
        let body = payload()
        // The hook gives up after 0.4 s, as when the agent's own timeout kills it.
        Thread.detachNewThread { _ = HookClient.send(vendor: .codex, payload: body, wait: 0.4, path: path, pathCheck: { _ in true }) }
        XCTAssertTrue(gone.wait(timeout: .now() + 3) == .success)
    }

    func testInstallerKeepsOtherHooksAndRemovesOnlyOurs() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("notch-home-\(UUID().uuidString)")
        let inst = HookInstaller(home: home)
        let settings = inst.file(.claude)
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = """
        {
          "model": "opus",
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "node other.js stop"
                  }
                ]
              }
            ]
          },
          "zeta": true
        }

        """
        try original.write(to: settings, atomically: true, encoding: .utf8)
        try inst.install(.claude)
        XCTAssertTrue(inst.isInstalled(.claude))
        let text = try String(contentsOf: settings, encoding: .utf8)
        XCTAssertTrue(text.contains("node other.js stop"))
        XCTAssertTrue(text.contains(#""timeout": 110"#))
        XCTAssertTrue(text.range(of: "\"model\"")!.lowerBound < text.range(of: "\"zeta\"")!.lowerBound)
        try inst.install(.claude)
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8).components(separatedBy: "PermissionRequest").count, 2)
        try inst.uninstall(.claude)
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), original)
        XCTAssertFalse(inst.isInstalled(.claude))

        // A file that cannot be read is left alone, never replaced.
        let junk = Data([0xFF, 0xFE, 0x00, 0x7B])
        try junk.write(to: settings)
        var threw = false
        do { try inst.install(.claude) } catch { threw = true }
        XCTAssertTrue(threw)
        XCTAssertEqual(try Data(contentsOf: settings), junk)

        // A symlinked hooks file stays a symlink; the edit lands in its target, mode kept.
        let real = home.appendingPathComponent("dotfiles/hooks.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}\n".write(to: real, atomically: true, encoding: .utf8)
        chmod(real.path, 0o600)
        try FileManager.default.createDirectory(at: inst.file(.codex).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: inst.file(.codex), withDestinationURL: real)
        try inst.install(.codex)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: inst.file(.codex).path)[.type] as? FileAttributeType), .typeSymbolicLink)
        XCTAssertTrue(try String(contentsOf: real, encoding: .utf8).contains("notch-hook"))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: real.path)[.posixPermissions] as? Int, 0o600)

        let codex = try String(contentsOf: inst.file(.codex), encoding: .utf8)
        XCTAssertTrue(codex.contains("\" codex"))
        XCTAssertFalse(codex.contains("async"))
    }
}

extension HookTests {
    func testOverlayWaitsUntilTheAgentMovesOn() {
        var st = HookState()
        let ask = HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: "s", tool: "Bash", detail: "make")
        XCTAssertEqual(st.receive(ask, ticket: 7, now: 0), [])
        let logs = [Agent(id: "s", vendor: .claude, title: "fix", state: .working, project: "p")]
        let a = st.apply(to: logs, now: 1) { _ in "p" }
        XCTAssertEqual(a.map(\.state), [.waiting])
        XCTAssertEqual(a[0].ask, "разрешить: Bash · make")
        // Unknown session: its own row, once.
        _ = st.receive(HookEvent(vendor: .codex, name: "PermissionRequest", sessionId: "c", cwd: "/x"), ticket: 8, now: 0)
        _ = st.receive(HookEvent(vendor: .codex, name: "PermissionRequest", sessionId: "c", cwd: "/x"), ticket: 9, now: 0)
        XCTAssertEqual(st.apply(to: logs, now: 1) { _ in "p" }.count, 2)
        // Another tool finishing changes nothing; the same tool finishing means it was answered elsewhere.
        XCTAssertEqual(st.receive(HookEvent(vendor: .claude, name: "PostToolUse", sessionId: "s", tool: "Read"), ticket: nil, now: 2), [])
        XCTAssertEqual(st.receive(HookEvent(vendor: .claude, name: "PostToolUse", sessionId: "s", tool: "Bash", detail: "make"), ticket: nil, now: 2), [7])
        XCTAssertEqual(st.apply(to: logs, now: 3) { _ in "p" }.first?.state, .working)
        // Claude's own prompt on screen waits until the next sign of life.
        _ = st.receive(HookEvent(vendor: .claude, name: "Notification", sessionId: "s", notificationType: "permission_prompt", message: "Claude needs your permission to use Bash"), ticket: nil, now: 4)
        XCTAssertEqual(st.apply(to: logs, now: 5) { _ in "p" }.first?.state, .waiting)
        _ = st.receive(HookEvent(vendor: .claude, name: "PreToolUse", sessionId: "s", tool: "Bash"), ticket: nil, now: 6)
        XCTAssertEqual(st.apply(to: logs, now: 7) { _ in "p" }.first?.state, .working)
        st.resolve(8); st.resolve(9)
        XCTAssertTrue(st.pending.isEmpty)
    }
}

final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ v: T) { value = v }
}

// Question and plan route: PreToolUse.
extension HookTests {
    func preEvent(_ tool: String, name: String = "PreToolUse", vendor: Vendor = .claude) throws -> HookEvent {
        let input: [String: Any] = tool == "ExitPlanMode" ? ["plan": "1. сделать"]
            : ["questions": [["question": "Какой цвет?", "header": "Цвет", "options": [["label": "красный", "description": ""]]]]]
        return try XCTUnwrap(HookEvent(vendor: vendor, payload: ["session_id": "s-9", "hook_event_name": name,
                                                                  "tool_name": tool, "tool_input": input]))
    }

    func testInstallerAddsSynchronousPreToolUseForAnswers() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("notch-pre-\(UUID().uuidString)")
        let inst = HookInstaller(home: home)
        try inst.install(.claude)
        let data = try Data(contentsOf: inst.file(.claude))
        let hooks = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["hooks"] as? [String: Any])
        let groups = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 2, "async activity entry stays, answer entry is added")
        let async = try XCTUnwrap(groups.first { $0["matcher"] == nil }?["hooks"] as? [[String: Any]])
        XCTAssertEqual(async.first?["async"] as? Bool, true)
        let sync = try XCTUnwrap(groups.first { $0["matcher"] != nil })
        XCTAssertEqual(sync["matcher"] as? String, "AskUserQuestion|ExitPlanMode")
        let hook = try XCTUnwrap((sync["hooks"] as? [[String: Any]])?.first)
        XCTAssertNil(hook["async"] as? Bool)
        XCTAssertEqual(hook["timeout"] as? Int, HookInstaller.wait + 10)
        XCTAssertTrue((hook["command"] as? String)?.hasSuffix("claude --wait") == true)
        // Codex has no such hook.
        try inst.install(.codex)
        XCTAssertFalse(try String(contentsOf: inst.file(.codex), encoding: .utf8).contains("matcher"))
        // Reinstalling does not stack entries; removing takes both.
        try inst.install(.claude)
        let again = try XCTUnwrap((try JSONSerialization.jsonObject(with: Data(contentsOf: inst.file(.claude))) as? [String: Any])?["hooks"] as? [String: Any])
        XCTAssertEqual((again["PreToolUse"] as? [Any])?.count, 2)
        try inst.uninstall(.claude)
        XCTAssertFalse(inst.isInstalled(.claude))
    }

    func testPreToolUseReplyShapes() throws {
        let q = try preEvent("AskUserQuestion")
        let answered = try XCTUnwrap(HookDecision.answer(q, ["Какой цвет?": "красный"]))
        let out = try XCTUnwrap(HookReply.stdout(event: q, decision: answered))
        let hook = try XCTUnwrap((try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])?["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(hook["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(hook["permissionDecision"] as? String, "allow")
        let updated = try XCTUnwrap(hook["updatedInput"] as? [String: Any])
        XCTAssertEqual((updated["answers"] as? [String: String])?["Какой цвет?"], "красный")
        XCTAssertTrue(updated["questions"] != nil)
        let plan = try preEvent("ExitPlanMode")
        let back = try XCTUnwrap(HookReply.stdout(event: plan, decision: HookDecision.returnPlan(feedback: "короче")))
        let denied = try XCTUnwrap((try JSONSerialization.jsonObject(with: Data(back.utf8)) as? [String: Any])?["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(denied["permissionDecision"] as? String, "deny")
        XCTAssertTrue((denied["permissionDecisionReason"] as? String)?.contains("короче") == true)
        XCTAssertNil(denied["updatedInput"])
        // Pass prints nothing; other tools' PreToolUse never get a reply; PermissionRequest keeps its own shape.
        XCTAssertNil(HookReply.stdout(event: q, decision: .pass))
        XCTAssertNil(HookReply.stdout(event: "PreToolUse", tool: "Bash", decision: .allow))
        XCTAssertNil(HookReply.stdout(event: "PreToolUse", tool: nil, decision: .allow))
        let permission = try XCTUnwrap(HookReply.stdout(event: "PermissionRequest", tool: "AskUserQuestion", decision: answered))
        XCTAssertTrue(permission.contains(#""hookEventName":"PermissionRequest""#))
        XCTAssertTrue(permission.contains(#""updatedInput""#))
    }

    func testServerWaitsOnlyForPermissionAndAnswerTools() throws {
        XCTAssertTrue(try preEvent("AskUserQuestion").waitsForAnswer)
        XCTAssertTrue(try preEvent("ExitPlanMode").waitsForAnswer)
        XCTAssertTrue(try preEvent("AskUserQuestion", name: "PermissionRequest").waitsForAnswer)
        XCTAssertFalse(try preEvent("AskUserQuestion", name: "PostToolUse").waitsForAnswer)
        XCTAssertFalse(try preEvent("AskUserQuestion", vendor: .codex).waitsForAnswer)
        XCTAssertFalse(HookEvent(vendor: .claude, name: "PreToolUse", sessionId: "s", tool: "Bash", detail: "ls").waitsForAnswer)

        let server = HookServer(path: socketPath())
        let seen = Box<[(String, Int?)]>([])
        let got = DispatchSemaphore(value: 0)
        server.onEvent = { e, t in seen.value.append((e.tool ?? "", t)); got.signal() }
        try server.start()
        defer { server.stop() }
        let path = server.path
        func body(_ tool: String, _ input: String) -> Data {
            Data(#"{"session_id":"s-1","hook_event_name":"PreToolUse","tool_name":"\#(tool)","tool_input":\#(input)}"#.utf8)
        }
        // Bash PreToolUse returns at once even when the hook asks to wait.
        XCTAssertNil(HookClient.send(vendor: .claude, payload: body("Bash", #"{"command":"ls"}"#), wait: 2, path: path, pathCheck: { _ in true }))
        XCTAssertTrue(got.wait(timeout: .now() + 2) == .success)
        XCTAssertNil(seen.value.first?.1)
        // A question holds the call until the answer arrives.
        let answer = Box<HookDecision?>(nil)
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            answer.value = HookClient.send(vendor: .claude, payload: body("ExitPlanMode", #"{"plan":"x"}"#), wait: 3, path: path, pathCheck: { _ in true })
            done.signal()
        }
        XCTAssertTrue(got.wait(timeout: .now() + 2) == .success)
        let ticket = try XCTUnwrap(seen.value.last?.1)
        server.answer(ticket, .denyWith(message: "нет"))
        XCTAssertTrue(done.wait(timeout: .now() + 2) == .success)
        XCTAssertEqual(answer.value, .denyWith(message: "нет"))
    }

    func testPermissionRequestAfterAHeldPreToolUseIsHandedBack() throws {
        var route = AnswerRoute()
        let pre = try preEvent("AskUserQuestion")
        let perm = try preEvent("AskUserQuestion", name: "PermissionRequest")
        XCTAssertFalse(route.isHandedBack(perm, now: 0))
        route.noteRouted(pre, now: 10)
        XCTAssertTrue(route.isHandedBack(perm, now: 12))
        XCTAssertFalse(route.isHandedBack(perm, now: 13))
        route.noteRouted(pre, now: 10)
        XCTAssertFalse(route.isHandedBack(perm, now: 500))
        route.noteRouted(try preEvent("ExitPlanMode"), now: 10)
        XCTAssertFalse(route.isHandedBack(perm, now: 11))
    }
}
