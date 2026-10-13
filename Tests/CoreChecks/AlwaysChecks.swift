import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

struct AlwaysChecks {
    func event(_ tool: String = "Bash", _ full: String? = "pnpm test --watch") -> HookEvent {
        HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: "always",
                  cwd: "/synthetic/wedding-app", tool: tool, full: full)
    }

    func prefixes() throws {
        for (command, expected) in [("pnpm test --watch", "pnpm test"), ("git status --short", "git status"),
                                    ("npm run test", "npm run"), ("yarn lint", "yarn lint"),
                                    ("cargo test", "cargo test"), ("go test ./...", "go test"),
                                    ("swift build", "swift build"), ("docker compose ps", "docker compose"),
                                    ("kubectl get pods", "kubectl get"), ("ls -la", "ls"),
                                    ("  pnpm\tbot:status  ", "pnpm bot:status")] {
            let s = try XCTUnwrap(AlwaysRule.suggest(for: event("Bash", command)))
            XCTAssertEqual(s.toolName, "Bash")
            XCTAssertEqual(s.ruleContent, expected + ":*")
            XCTAssertEqual(s.prefix, expected.split(separator: " ").map(String.init))
        }
        XCTAssertEqual(AlwaysRule.suggest(for: event())?.label, "Всегда `pnpm test *` в wedding-app")
    }

    func refused() {
        for command in ["rm -rf build", "git push --force", "git reset --hard", "sudo pnpm test",
                        "/usr/bin/sudo pnpm test", "pnpm test && echo ok", "pnpm test; echo ok",
                        "pnpm test | cat", "pnpm test || echo bad", "pnpm test &", "pnpm test $(echo x)",
                        "pnpm test `echo x`", "pnpm test\necho ok", "pnpm test >out", "pnpm test <in",
                        "git -C /tmp status", "pnpm", "", "   ", "'pnpm' test", "env pnpm test",
                        "bash -c 'pnpm test'", String(repeating: "x", count: 4000)] {
            XCTAssertNil(AlwaysRule.suggest(for: event("Bash", command)), command)
        }
        var hidden = event("Bash", "pnpm test && rm -rf build")
        hidden.detail = "pnpm test"
        XCTAssertNil(AlwaysRule.suggest(for: hidden))
        XCTAssertNil(AlwaysRule.suggest(for: event("Bash", nil)))
        for tool in ["Edit", "Write", "Read", "AskUserQuestion"] {
            XCTAssertNil(AlwaysRule.suggest(for: event(tool)))
        }
        var other = event(); other.name = "PreToolUse"
        XCTAssertNil(AlwaysRule.suggest(for: other))
        other = event(); other.vendor = .codex
        XCTAssertNil(AlwaysRule.suggest(for: other))
    }

    func webAndMCP() throws {
        let web = try XCTUnwrap(AlwaysRule.suggest(for: event("WebFetch", "https://Docs.Example.com:443/path?q=1")))
        XCTAssertEqual(web.toolName, "WebFetch")
        XCTAssertEqual(web.ruleContent, "domain:docs.example.com")
        XCTAssertNil(web.prefix)
        for url in ["not a URL", "file:///tmp/file", "https:///missing", "https://*.example.com", "https://example.com\n"] {
            XCTAssertNil(AlwaysRule.suggest(for: event("WebFetch", url)), url)
        }
        let mcp = try XCTUnwrap(AlwaysRule.suggest(for: event("mcp__docs__search", nil)))
        XCTAssertEqual(mcp.toolName, "mcp__docs__search")
        XCTAssertNil(mcp.ruleContent)
        XCTAssertNil(mcp.prefix)
        XCTAssertNil(AlwaysRule.suggest(for: event("mcp__docs__*", nil)))
    }

    func reply() throws {
        let e = event(), rule = try XCTUnwrap(AlwaysRule.suggest(for: e))
        let out = try XCTUnwrap(HookReply.stdout(event: e, decision: .allow, rule: rule))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        let hook = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(hook["hookEventName"] as? String, "PermissionRequest")
        let decision = try XCTUnwrap(hook["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        let updates = try XCTUnwrap(decision["updatedPermissions"] as? [[String: Any]])
        XCTAssertEqual(updates.count, 1)
        let update = try XCTUnwrap(updates.first)
        XCTAssertEqual(update["type"] as? String, "addRules")
        XCTAssertEqual(update["behavior"] as? String, "allow")
        XCTAssertEqual(update["destination"] as? String, "localSettings")
        let rules = try XCTUnwrap(update["rules"] as? [[String: Any]])
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?["toolName"] as? String, "Bash")
        XCTAssertEqual(rules.first?["ruleContent"] as? String, "pnpm test:*")
        XCTAssertEqual(HookReply.stdout(event: e, decision: .deny, rule: rule),
                       HookReply.stdout(event: e.name, decision: .deny))
        XCTAssertNil(HookReply.stdout(event: e, decision: .pass, rule: rule))
        XCTAssertEqual(HookReply.stdout(event: e, decision: .allow, rule: nil),
                       HookReply.stdout(event: e.name, decision: .allow))
        XCTAssertNil(HookReply.stdout(event: event("Bash", "sudo pnpm test"), decision: .allow, rule: rule))
        XCTAssertNil(HookReply.stdout(event: event("Bash", "git status"), decision: .allow, rule: rule))
        var codex = e; codex.vendor = .codex
        XCTAssertNil(HookReply.stdout(event: codex, decision: .allow, rule: rule))
        let mcp = event("mcp__docs__search", nil)
        let mcpOut = try XCTUnwrap(HookReply.stdout(event: mcp, decision: .allow, rule: AlwaysRule.suggest(for: mcp)))
        XCTAssertFalse(mcpOut.contains("ruleContent"))
    }

    func tempHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("always-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    func codexRules() throws {
        let home = try tempHome(), fm = FileManager.default
        defer { try? fm.removeItem(at: home) }
        let dir = home.appendingPathComponent(".codex/rules"), own = dir.appendingPathComponent("agents-notch.rules")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let other = dir.appendingPathComponent("default.rules")
        try Data("# unrelated\n".utf8).write(to: other)
        try CodexRules.add(prefix: ["pnpm", "test"], home: home)
        let first = try String(contentsOf: own, encoding: .utf8)
        XCTAssertTrue(first.hasPrefix("# Managed by Agents Notch\n"))
        XCTAssertTrue(first.contains(#"prefix_rule(pattern=["pnpm", "test"], decision="allow")"#))
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: own.path)
        try CodexRules.add(prefix: ["pnpm", "test"], home: home)
        XCTAssertEqual(try String(contentsOf: own, encoding: .utf8), first)
        XCTAssertEqual(try fm.attributesOfItem(atPath: own.path)[.posixPermissions] as? Int, 0o600)
        try CodexRules.add(prefix: ["git", "status"], home: home)
        XCTAssertTrue(try String(contentsOf: own, encoding: .utf8).hasPrefix(first))
        XCTAssertEqual(try String(contentsOf: other, encoding: .utf8), "# unrelated\n")
        for prefix in [[], [""], ["pnpm", "\0"]] {
            do { try CodexRules.add(prefix: prefix, home: home); XCTFail("accepted invalid prefix") }
            catch { }
        }
    }

    func codexExistingFile() throws {
        let home = try tempHome(), fm = FileManager.default
        defer { try? fm.removeItem(at: home) }
        let dir = home.appendingPathComponent(".codex/rules"), own = dir.appendingPathComponent("agents-notch.rules")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let existing = #"prefix_rule(pattern=["ls"], decision="allow")"#
        try Data(existing.utf8).write(to: own)
        try CodexRules.add(prefix: ["ls"], home: home)
        let next = try String(contentsOf: own, encoding: .utf8)
        XCTAssertEqual(next, existing + "\n# Managed by Agents Notch\n")
        try CodexRules.add(prefix: ["ls"], home: home)
        XCTAssertEqual(try String(contentsOf: own, encoding: .utf8), next)
        try CodexRules.add(prefix: ["git", "status"], home: home)
        XCTAssertTrue(try String(contentsOf: own, encoding: .utf8).hasPrefix(next))
    }

    func codexEscapingAndLinks() throws {
        let home = try tempHome(), fm = FileManager.default
        defer { try? fm.removeItem(at: home) }
        try CodexRules.add(prefix: ["echo", "quote\"\\name", "строка\n\t\u{1}"], home: home)
        let own = home.appendingPathComponent(".codex/rules/agents-notch.rules")
        let text = try String(contentsOf: own, encoding: .utf8)
        XCTAssertTrue(text.contains(#""quote\"\\name""#))
        XCTAssertTrue(text.contains(#""строка\n\t\x01""#))
        let target = home.appendingPathComponent("untouched")
        try Data("original".utf8).write(to: target)
        try fm.removeItem(at: own)
        try fm.createSymbolicLink(at: own, withDestinationURL: target)
        do { try CodexRules.add(prefix: ["ls"], home: home); XCTFail("followed symlink") } catch { }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "original")
    }
}

// Standing approval over the socket.
extension AlwaysChecks {
    func socketCarriesTheRule() throws {
        let e = event(), rule = try XCTUnwrap(AlwaysRule.suggest(for: e))
        let decision = HookDecision.allowAlways(rule)
        XCTAssertEqual(decision.name, "always")
        let wire = try XCTUnwrap(try JSONSerialization.jsonObject(with: decision.wire) as? [String: Any])
        XCTAssertEqual(wire["decision"] as? String, "allow", "older readers still see an allow")
        XCTAssertEqual(HookDecision(wire: wire), decision)
        // notch-hook prints the updatedPermissions reply, checked against its own copy of the event.
        let out = try XCTUnwrap(HookReply.stdout(event: e, decision: decision))
        XCTAssertEqual(out, HookReply.stdout(event: e, decision: .allow, rule: rule))
        XCTAssertTrue(out.contains("updatedPermissions"))
        // A rule that does not fit the request is never printed.
        XCTAssertNil(HookReply.stdout(event: event("Bash", "git status"), decision: decision))
        // Without rule context an always is only an allow.
        XCTAssertEqual(HookReply.stdout(event: "PermissionRequest", decision: decision), HookReply.stdout(event: "PermissionRequest", decision: .allow))
        // A plain allow stays plain.
        XCTAssertEqual(HookDecision(wire: ["decision": "allow"]), .allow)
    }

    func socketRoundTrip() throws {
        let path = "/tmp/notch-al-\(UUID().uuidString.prefix(8)).sock"
        let server = HookServer(path: path)
        let ticket = Box<Int?>(nil)
        let got = DispatchSemaphore(value: 0)
        server.onEvent = { _, t in ticket.value = t; got.signal() }
        try server.start()
        defer { server.stop() }
        let rule = try XCTUnwrap(AlwaysRule.suggest(for: event()))
        let body = Data(#"{"session_id":"always","hook_event_name":"PermissionRequest","cwd":"/synthetic/wedding-app","tool_name":"Bash","tool_input":{"command":"pnpm test --watch"}}"#.utf8)
        let answer = Box<HookDecision?>(nil)
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread { answer.value = HookClient.send(vendor: .claude, payload: body, wait: 3, path: path, pathCheck: { _ in true }); done.signal() }
        XCTAssertTrue(got.wait(timeout: .now() + 2) == .success)
        server.answer(try XCTUnwrap(ticket.value), .allowAlways(rule))
        XCTAssertTrue(done.wait(timeout: .now() + 2) == .success)
        XCTAssertEqual(answer.value, .allowAlways(rule))
    }
}
