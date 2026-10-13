import Foundation

struct DetailChecks {
    func fixture(_ rows: [Rec], _ body: (String) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("session.jsonl")
        var data = Data()
        for row in rows { data += try JSONSerialization.data(withJSONObject: row); data.append(10) }
        try data.write(to: path)
        try body(path.path)
    }
    func claude() throws {
        func call(_ id: String, _ name: String, _ input: Rec) -> Rec {
            ["type": "assistant", "timestamp": "2026-10-13T10:00:00Z", "cwd": "/repo",
             "gitBranch": "feat/detail", "message": ["model": "claude-sonnet", "content":
                [["type": "tool_use", "id": id, "name": name, "input": input]]]]
        }
        func result(_ id: String, _ error: Bool) -> Rec {
            ["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": id,
                "is_error": error, "content": "  Failed   build\nmore"]]]]
        }
        try fixture([
            call("p", "TodoWrite", ["todos": [["content": "old", "status": "pending"]]]),
            call("p2", "TodoWrite", ["todos": [["content": "ship", "status": "in_progress"]]]),
            call("e", "Edit", ["file_path": "/repo/a.swift", "old_string": "a\nb\n", "new_string": "c\n"]),
            call("w", "Write", ["file_path": "/repo/b.swift", "content": "a\nb"]),
            call("b", "Bash", ["command": "./scripts/test.sh"]), result("b", false),
            call("c", "Bash", ["command": "make"]), result("c", true),
            call("d", "Bash", ["command": "make"]), result("d", true),
            ["type": "assistant", "message": ["content": [["type": "text", "text": String(repeating: "я", count: 650)]]]]
        ]) { path in
            let d = try XCTUnwrap(DetailReader.read(path: path, vendor: .claude, agentId: nil))
            XCTAssertEqual(d.plan, [PlanItem(text: "ship", status: .active)])
            XCTAssertEqual(d.files.map(\.path), ["b.swift", "a.swift"])
            XCTAssertEqual(d.files[1].added, 1); XCTAssertEqual(d.files[1].removed, 2)
            XCTAssertEqual(d.files[0].added, 2)
            // Files carry the time of their last change, like commands.
            XCTAssertEqual(d.files[0].at, LogText.time("2026-10-13T10:00:00Z"))
            XCTAssertEqual(d.commands.map(\.ok), [true, false, false])
            XCTAssertTrue(d.commands[0].isTest)
            XCTAssertEqual(d.lastMessage?.count, 600)
            XCTAssertEqual(d.errors.first?.count, 2)
            XCTAssertEqual(d.errors.first?.text, "Failed build")
            XCTAssertEqual(d.meta.branch, "feat/detail")
            XCTAssertEqual(d.meta.model, "claude-sonnet")
        }
    }
    func codex() throws {
        func item(_ p: Rec) -> Rec { ["type": "response_item", "timestamp": "2026-10-13T10:01:00Z", "payload": p] }
        func call(_ id: String, _ name: String, _ args: Rec) throws -> Rec {
            item(["type": "function_call", "call_id": id, "name": name,
                  "arguments": String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self)])
        }
        try fixture([
            ["type": "session_meta", "timestamp": "2026-10-13T10:00:00Z",
             "payload": ["cwd": "/repo", "git": ["branch": "dev"]]],
            ["type": "turn_context", "payload": ["model": "gpt-6.1-sol", "effort": "high"]],
            try call("p", "update_plan", ["plan": [["step": "build", "status": "completed"]]]),
            item(["type": "custom_tool_call", "call_id": "a", "name": "apply_patch",
                  "input": "*** Begin Patch\n*** Update File: a.swift\n@@\n-old\n+new\n+extra\n*** Add File: b.swift\n+one\n*** Delete File: c.swift\n*** End Patch"]),
            try call("c", "exec_command", ["cmd": "pytest -q"]),
            item(["type": "function_call_output", "call_id": "c", "output": "Process exited with code 0\nOutput:\nok"]),
            ["type": "event_msg", "payload": ["type": "agent_message", "message": "готово"]]
        ]) { path in
            let d = try XCTUnwrap(DetailReader.read(path: path, vendor: .codex, agentId: nil))
            XCTAssertEqual(d.plan, [PlanItem(text: "build", status: .done)])
            XCTAssertEqual(d.files.first(where: { $0.path == "a.swift" })?.added, 2)
            XCTAssertEqual(d.files.first(where: { $0.path == "a.swift" })?.removed, 1)
            XCTAssertEqual(d.files.first(where: { $0.path == "b.swift" })?.added, 1)
            XCTAssertTrue(d.files.contains { $0.path == "c.swift" })
            XCTAssertEqual(d.files.first(where: { $0.path == "b.swift" })?.at, LogText.time("2026-10-13T10:01:00Z"))
            XCTAssertEqual(d.commands.first?.ok, true); XCTAssertEqual(d.commands.first?.isTest, true)
            XCTAssertEqual(d.lastMessage, "готово")
            XCTAssertEqual(d.meta.effort, .high); XCTAssertEqual(d.meta.branch, "dev")
        }
    }
    func worktrees() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let main = root.appendingPathComponent("main")
        let linked = root.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: main.appendingPathComponent(".git/worktrees/linked"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linked.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "gitdir: ../main/.git/worktrees/linked\n".write(to: linked.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        for (cwd, expected) in [(main.path, nil as String?), (linked.appendingPathComponent("src").path, "linked")] {
            var s = SessionLog(id: "s", vendor: .claude)
            ClaudeLine.apply(["type": "user", "cwd": cwd, "gitBranch": "topic",
                              "timestamp": "2026-10-13T10:00:00Z"], to: &s, isSubagent: false)
            let a = try XCTUnwrap(s.agent(now: s.lastAt, project: { _ in "p" }))
            XCTAssertEqual(a.worktree, expected); XCTAssertEqual(a.branch, "topic")
            try fixture([["type": "user", "cwd": cwd, "gitBranch": "topic"]]) { path in
                XCTAssertEqual(DetailReader.read(path: path, vendor: .claude, agentId: nil)?.meta.worktree, expected)
            }
        }
    }
    func tasksAndBounds() throws {
        let created: Rec = ["type": "assistant", "isSidechain": true, "message": ["content": [
            ["type": "tool_use", "id": "create", "name": "TaskCreate", "input": ["subject": "first"]]]]]
        let result: Rec = ["type": "user", "isSidechain": true, "message": ["content": [
            ["type": "tool_result", "tool_use_id": "create", "content": "Task #1 created successfully: first"]]]]
        let update: Rec = ["type": "assistant", "isSidechain": true, "message": ["content": [
            ["type": "tool_use", "name": "TaskUpdate", "input": ["taskId": "1", "status": "completed"]]]]]
        try fixture([created, result, update]) { path in
            let d = try XCTUnwrap(DetailReader.read(path: path, vendor: .claude, agentId: "child"))
            XCTAssertEqual(d.plan, [PlanItem(text: "first", status: .done)])
            XCTAssertNil(DetailReader.read(path: path, vendor: .claude, agentId: nil))
        }
        var rows: [Rec] = [
            ["type": "session_meta", "timestamp": "2026-10-13T10:00:00Z",
             "payload": ["cwd": "/repo", "git": ["branch": "topic"]]],
            ["type": "response_item", "payload": ["type": "message", "role": "assistant",
             "content": [["type": "output_text", "text": "old"]]]],
            ["type": "padding", "value": String(repeating: "x", count: 9 << 20)]
        ]
        for i in 0..<35 {
            let args = String(decoding: try JSONSerialization.data(withJSONObject: ["command": ["sh", "-c", "echo \(i)"]]), as: UTF8.self)
            rows.append(["type": "response_item", "payload": ["type": "function_call",
                "call_id": "c\(i)", "name": "shell", "arguments": args]])
        }
        rows.append(["type": "response_item", "payload": ["type": "message", "role": "assistant",
            "content": [["type": "output_text", "text": "latest"]]]])
        try fixture(rows) { path in
            let d = try XCTUnwrap(DetailReader.read(path: path, vendor: .codex, agentId: nil))
            XCTAssertEqual(d.commands.count, 30); XCTAssertEqual(d.commands.first?.command, "sh -c echo 5")
            XCTAssertNil(d.commands.first?.ok)
            XCTAssertEqual(d.lastMessage, "latest"); XCTAssertEqual(d.meta.branch, "topic")
            XCTAssertEqual(d.meta.cwd, "/repo"); XCTAssertTrue(d.meta.startedAt != nil)
        }
    }
    func codexOutputs() throws {
        let args = String(decoding: try JSONSerialization.data(withJSONObject: ["cmd": "make"]), as: UTF8.self)
        var rows: [Rec] = []
        for i in 0..<2 {
            rows.append(["type": "response_item", "payload": ["type": "function_call",
                "call_id": "c\(i)", "name": "functions.exec_command", "arguments": args]])
            rows.append(["type": "response_item", "payload": ["type": "function_call_output",
                "call_id": "c\(i)", "output": String(decoding: try JSONSerialization.data(withJSONObject: ["exit_code": 1, "output": "compile failed\nmore"]), as: UTF8.self)]])
        }
        try fixture(rows) { path in
            let d = try XCTUnwrap(DetailReader.read(path: path, vendor: .codex, agentId: nil))
            XCTAssertEqual(d.commands.count, 2); XCTAssertEqual(d.commands.first?.ok, false)
            XCTAssertEqual(d.errors, [DetailError(text: "compile failed", count: 2)])
        }
    }
    func failedAndStreamed() throws {
        func item(_ p: Rec) -> Rec { ["type": "response_item", "payload": p] }
        func output(_ id: String, _ data: Rec) throws -> Rec {
            item(["type": "function_call_output", "call_id": id,
                  "output": String(decoding: try JSONSerialization.data(withJSONObject: data), as: UTF8.self)])
        }
        try fixture([
            item(["type": "custom_tool_call", "name": "apply_patch", "call_id": "patch",
                  "input": "*** Begin Patch\n*** Add File: failed.swift\n+oops\n*** End Patch"]),
            try output("patch", ["exit_code": 1, "output": "patch failed"]),
            item(["type": "function_call", "name": "exec_command", "call_id": "cmd", "arguments": "{\"cmd\":\"pytest\"}"]),
            try output("cmd", ["session_id": 42, "output": "running"]),
            item(["type": "function_call", "name": "write_stdin", "call_id": "poll", "arguments": "{\"session_id\":42}"]),
            try output("poll", ["exit_code": 1, "output": "tests failed"])
        ]) { path in
            let d = try XCTUnwrap(DetailReader.read(path: path, vendor: .codex, agentId: nil))
            XCTAssertTrue(d.files.isEmpty); XCTAssertEqual(d.commands.first?.ok, false)
            XCTAssertTrue(d.errors.isEmpty)
        }
        try fixture([
            item(["type": "custom_tool_call", "name": "exec", "call_id": "nested",
                  "input": "text(await tools.exec_command({cmd: \"pytest -q\"}));"]),
            item(["type": "custom_tool_call_output", "call_id": "nested",
                  "output": [["type": "text", "text": "{\"exit_code\":0,\"output\":\"ok\"}"]]])
        ]) { path in
            let d = try XCTUnwrap(DetailReader.read(path: path, vendor: .codex, agentId: nil))
            XCTAssertEqual(d.commands.first?.command, "pytest -q"); XCTAssertEqual(d.commands.first?.ok, true)
        }
    }
    func outcomeDeduplication() throws {
        try fixture([["type": "response_item", "payload": ["type": "custom_tool_call", "name": "exec", "call_id": "x",
            "input": "tools.update_plan({plan:[{step:\"build\",status:\"completed\"}]}); tools.apply_patch(\"*** Begin Patch\\n*** Add File: a\\n+ok\\n*** End Patch\");"]],
            ["type": "response_item", "payload": ["type": "custom_tool_call_output", "call_id": "x",
                "output": [["type": "text", "text": "{\"exit_code\":1,\"output\":\"failed\"}"]]]]]) { path in
            let d = try XCTUnwrap(DetailReader.read(path: path, vendor: .codex))
            XCTAssertEqual(d.plan, [PlanItem(text: "build", status: .done)]); XCTAssertEqual(d.files.first?.added, 1)
        }
        try fixture([
            ["type": "response_item", "payload": ["type": "function_call", "call_id": "c",
                "name": "exec_command", "arguments": "{\"cmd\":\"make\"}"]],
            ["type": "event_msg", "payload": ["type": "exec_command_end", "call_id": "c", "exit_code": 1, "output": "failed"]],
            ["type": "response_item", "payload": ["type": "function_call_output", "call_id": "c", "output": "{\"exit_code\":1,\"output\":\"failed\"}"]]
        ]) { path in
            XCTAssertTrue(try XCTUnwrap(DetailReader.read(path: path, vendor: .codex)).errors.isEmpty)
        }
        try fixture([
            ["type": "assistant", "message": ["content": [["type": "tool_use", "name": "Edit", "id": "e", "input":
                ["file_path": "/repo/a", "old_string": "old", "new_string": "new"]]]]],
            ["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": "e", "is_error": true, "content": "not found"]]]]
        ]) { path in
            XCTAssertTrue(try XCTUnwrap(DetailReader.read(path: path, vendor: .claude)).files.isEmpty)
        }
    }

}
