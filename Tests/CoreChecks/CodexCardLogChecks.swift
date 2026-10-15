import Foundation

struct CodexCardLogChecks {
    // Shapes from codex exec --json, 2026-10-13. All content and ids are synthetic.
    static let execFixture: [Rec] = [
        ["type": "thread.started", "thread_id": "test-thread"],
        ["type": "turn.started"],
        ["type": "item.started", "item": ["id": "read", "type": "command_execution",
            "command": "/bin/zsh -lc 'cat /tmp/example/README.md'", "aggregated_output": "",
            "exit_code": NSNull(), "status": "in_progress"]],
        ["type": "item.completed", "item": ["id": "read", "type": "command_execution",
            "command": "/bin/zsh -lc 'cat /tmp/example/README.md'", "aggregated_output": "Example documentation",
            "exit_code": 0, "status": "completed"]],
        ["type": "item.started", "item": ["id": "search", "type": "web_search", "query": "",
            "action": ["type": "other"]]],
        ["type": "item.completed", "item": ["id": "search", "type": "web_search", "query": "example documentation",
            "action": ["type": "search", "queries": ["example documentation"]], "results": []]],
        ["type": "item.started", "item": ["id": "failed", "type": "command_execution",
            "command": "cat /tmp/example/missing.txt", "aggregated_output": "", "exit_code": NSNull(), "status": "in_progress"]],
        ["type": "item.completed", "item": ["id": "failed", "type": "command_execution",
            "command": "cat /tmp/example/missing.txt", "aggregated_output": "File not found\nDetails",
            "exit_code": 1, "status": "completed"]],
        ["type": "item.completed", "item": ["id": "message", "type": "agent_message", "text": "Reading documentation"]],
        ["type": "item.started", "item": ["id": "running", "type": "command_execution",
            "command": "rg example /tmp/example", "aggregated_output": "", "exit_code": NSNull(), "status": "in_progress"]]
    ]

    func execCardLog() throws {
        try DetailChecks().fixture(Self.execFixture) { path in
            let run = ExecRun(pid: 7, log: path, cwd: "/tmp/example", model: "gpt-6.1-sol", effort: .high)
            let scanner = LogScanner(home: URL(fileURLWithPath: "/tmp/example-home"), execRuns: { [run] })
            let agent = try XCTUnwrap(scanner.poll()!.first { $0.logPath == path })
            XCTAssertEqual(agent.state, .working)
            let d = try XCTUnwrap(DetailReader.read(path: try XCTUnwrap(agent.logPath), vendor: agent.vendor, agentId: agent.id))
            XCTAssertEqual(d.commands.map(\.command), ["cat /tmp/example/README.md", "search · example documentation",
                                                     "cat /tmp/example/missing.txt", "rg example /tmp/example"])
            XCTAssertEqual(d.commands.map(\.ok), [true, true, false, nil])
            XCTAssertEqual(CardContent.commands(d).first?.command, "rg example /tmp/example")
            XCTAssertEqual(d.errors, [DetailError(text: "File not found", count: 1)])
            XCTAssertEqual(d.lastMessage, "Reading documentation")
        }
    }

    func execCompletionWithoutStart() throws {
        // A bounded tail can miss item.started; a completed item still contains the command.
        try DetailChecks().fixture([Self.execFixture[3], Self.execFixture[5]]) { path in
            let d = try XCTUnwrap(DetailReader.read(path: path, vendor: .codex))
            XCTAssertEqual(d.commands.map(\.command), ["cat /tmp/example/README.md", "search · example documentation"])
            XCTAssertEqual(d.commands.map(\.ok), [true, true])
        }
    }

    func rolloutWebSearch() throws {
        try DetailChecks().fixture([
            ["type": "response_item", "timestamp": "2026-10-13T10:00:00Z", "payload": [
                "type": "web_search_call", "id": "web", "status": "completed", "action": [
                    "type": "search", "queries": ["example documentation", "example API"]]]],
            ["type": "response_item", "payload": ["type": "function_call", "call_id": "read",
                "name": "exec_command", "arguments": "{\"cmd\":\"cat README.md\"}"]],
            ["type": "event_msg", "payload": ["type": "exec_command_end", "call_id": "read",
                "exit_code": 0, "aggregated_output": "Example documentation"]]
        ]) { path in
            let d = try XCTUnwrap(DetailReader.read(path: path, vendor: .codex))
            XCTAssertEqual(d.commands.map(\.command), ["search · example documentation, example API", "cat README.md"])
            XCTAssertEqual(d.commands.map(\.ok), [true, true])
        }
    }

    func execWebActionsAndDeclinedCommand() throws {
        try DetailChecks().fixture([
            ["type": "item.completed", "item": ["id": "open", "type": "web_search", "query": "https://example.com/docs",
                "action": ["type": "open_page", "url": "https://example.com/docs"], "results": []]],
            ["type": "item.completed", "item": ["id": "find", "type": "web_search", "query": "example pattern",
                "action": ["type": "find_in_page", "pattern": "example pattern"], "results": []]],
            ["type": "item.completed", "item": ["id": "declined", "type": "command_execution",
                "command": "cat /tmp/example/README.md", "aggregated_output": "Command declined",
                "exit_code": NSNull(), "status": "declined"]],
            ["type": "item.completed", "item": ["id": "search-error", "type": "web_search", "query": "example query",
                "action": ["type": "search", "queries": ["example query"]], "status": "failed",
                "error": ["message": "Example search failed"]]]
        ]) { path in
            let d = try XCTUnwrap(DetailReader.read(path: path, vendor: .codex))
            XCTAssertEqual(d.commands.map(\.command), ["web · open · https://example.com/docs",
                "web · find · example pattern", "cat /tmp/example/README.md", "search · example query"])
            XCTAssertEqual(d.commands.map(\.ok), [true, true, false, false])
            XCTAssertEqual(d.errors, [DetailError(text: "Command declined", count: 1),
                                     DetailError(text: "Example search failed", count: 1)])
        }
    }

    func codexRunErrors() throws {
        for rows: [Rec] in [
            [["type": "turn.failed", "error": ["message": "Example run failed"]]],
            [["type": "error", "message": "Example run failed"]],
            [["type": "error", "message": "Example run failed"],
             ["type": "turn.failed", "error": ["message": "Example run failed"]]],
            [["type": "event_msg", "payload": ["type": "error", "message": "Example run failed"]]]
        ] {
            try DetailChecks().fixture(rows) { path in
                XCTAssertEqual(DetailReader.read(path: path, vendor: .codex)?.errors,
                               [DetailError(text: "Example run failed", count: 1)])
            }
        }
    }
}
