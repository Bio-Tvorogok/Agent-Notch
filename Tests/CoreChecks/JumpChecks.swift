import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

struct JumpChecks {
    func fixture(_ body: (URL) throws -> Void) throws {
        let home = URL(fileURLWithPath: "/tmp/an06-t8-jump-\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home)
    }

    func write(_ home: URL, _ path: String, _ record: [String: Any]) throws -> String {
        let file = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try JSONSerialization.data(withJSONObject: record)
        data.append(10)
        try data.write(to: file)
        return file.path
    }

    func agent(_ vendor: Vendor, _ path: String?, parent: String? = nil) -> Agent {
        Agent(id: "11111111-1111-4111-8111-111111111111", vendor: vendor, title: "test",
              state: .working, project: "project", parentId: parent, cwd: "/tmp/project", logPath: path)
    }

    func claudeCLI() throws {
        try fixture { home in
            let a = agent(.claude, try write(home, ".claude/projects/test/main.jsonl", ["entrypoint": "cli"]))
            _ = try write(home, ".claude/sessions/123.json", ["sessionId": a.id, "pid": 123])
            let targets = JumpResolver.resolve(agent: a, home: home)
            XCTAssertEqual(targets.first, .terminal(pid: 123, cwd: a.cwd))
            XCTAssertTrue(targets.contains(.claudeApp(try XCTUnwrap(URL(string: "claude://resume?session=\(a.id)")))))
            XCTAssertEqual(targets.last, .folder("/tmp/project"))
        }
    }

    func claudeDesktop() throws {
        try fixture { home in
            let a = agent(.claude, try write(home, ".claude/projects/test/main.jsonl", ["entrypoint": "claude-desktop"]))
            _ = try write(home, ".claude/sessions/123.json", ["sessionId": a.id, "pid": 123, "hostSessionId": "local_desktop-id"])
            XCTAssertEqual(JumpResolver.resolve(agent: a, home: home).first,
                           .claudeApp(try XCTUnwrap(URL(string: "claude://code/continue?session=local_desktop-id"))))
        }
    }

    func codex(_ origin: String, desktop: Bool) throws {
        try fixture { home in
            let path = try write(home, ".codex/sessions/2026/10/13/rollout-test.jsonl",
                                 ["type": "session_meta", "payload": ["id": "thread-test", "originator": origin]])
            let a = agent(.codex, path)
            let targets = JumpResolver.resolve(agent: a, home: home)
            let expected: JumpTarget = desktop ? .codexApp(try XCTUnwrap(URL(string: "codex://threads/thread-test")))
                : .terminal(pid: nil, cwd: a.cwd)
            XCTAssertEqual(targets.first, expected)
            XCTAssertEqual(targets.last, .folder("/tmp/project"))
        }
    }

    func subagents() throws {
        try fixture { home in
            let root = "22222222-2222-4222-8222-222222222222"
            _ = try write(home, ".claude/projects/test/\(root).jsonl", ["entrypoint": "claude-desktop"])
            let path = try write(home, ".claude/projects/test/\(root)/subagents/workflows/run/agent-child.jsonl", ["entrypoint": "sdk-cli"])
            _ = try write(home, ".claude/sessions/123.json", ["sessionId": root, "pid": 123, "hostSessionId": "local_parent"])
            XCTAssertEqual(JumpResolver.resolve(agent: agent(.claude, path, parent: root), home: home).first,
                           .claudeApp(try XCTUnwrap(URL(string: "claude://code/continue?session=local_parent"))))
            _ = try write(home, ".codex/sessions/2026/10/12/parent.jsonl",
                          ["type": "session_meta", "payload": ["id": root, "originator": "Codex Desktop", "cwd": "/tmp/parent"]])
            let child = try write(home, ".codex/sessions/2026/10/13/child.jsonl",
                                 ["type": "session_meta", "payload": ["id": "child", "originator": "codex_exec"]])
            let targets = JumpResolver.resolve(agent: agent(.codex, child, parent: root), home: home)
            XCTAssertEqual(targets.first, .codexApp(try XCTUnwrap(URL(string: "codex://threads/\(root)"))))
            XCTAssertEqual(targets.last, .folder("/tmp/parent"))
        }
    }

    func fallbackAndEditor() throws {
        try fixture { home in
            var a = agent(.claude, nil)
            a.cwd = nil
            XCTAssertEqual(JumpResolver.resolve(agent: a, home: home).last, .folder(home.path))
            let path = try write(home, ".claude/projects/test/editor.jsonl", ["entrypoint": "claude-vscode"])
            let editor = agent(.claude, path)
            XCTAssertEqual(JumpResolver.resolve(agent: editor, home: home).first,
                           .editor(bundleId: "com.microsoft.VSCode", cwd: "/tmp/project"))
            _ = try write(home, ".claude/sessions/123.json", ["sessionId": editor.id, "pid": 123])
            XCTAssertEqual(JumpResolver.resolve(agent: editor, home: home).first,
                           .terminal(pid: 123, cwd: "/tmp/project"))
        }
    }
    func metadataEdges() throws {
        try fixture { home in
            let path = try write(home, ".codex/sessions/2026/10/13/alternate.jsonl",
                                 ["type": "session_meta", "payload": ["session_id": "alternate", "originator": "Codex Desktop"]])
            XCTAssertEqual(JumpResolver.resolve(agent: agent(.codex, path), home: home).first,
                           .codexApp(try XCTUnwrap(URL(string: "codex://threads/alternate"))))
            try #"{"type":"other","payload":{"id":"wrong","originator":"Codex Desktop"}}"#.write(
                to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            XCTAssertEqual(JumpResolver.resolve(agent: agent(.codex, path), home: home).first,
                           .terminal(pid: nil, cwd: "/tmp/project"))
            let claude = try write(home, ".claude/projects/test/sdk.jsonl", ["type": "file-history-snapshot"])
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: claude))
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(#"{"entrypoint":"sdk-cli","cwd":"relative"}"#.utf8) + Data([10]))
            try handle.close()
            let a = agent(.claude, claude)
            _ = try write(home, ".claude/sessions/123.json", ["sessionId": a.id, "pid": 4294967297])
            XCTAssertEqual(JumpResolver.resolve(agent: a, home: home).first,
                           .terminal(pid: nil, cwd: "/tmp/project"))
        }
    }

    func preciseCodexAndResume() throws {
        try fixture { home in
            for origin in ["codex_cli_rs", "codex_exec", "codex_vscode", "Codex Desktop"] {
                let path = try write(home, ".codex/sessions/rollout-test.jsonl",
                    ["type": "session_meta", "payload": ["id": "thread-test", "originator": origin, "cwd": "/tmp/a b'c"]])
                let a = agent(.codex, path)
                let plan = JumpResolver.plan(agent: a, home: home,
                    processes: [CodexProcess(pid: 321, paths: [path])])
                if origin == "Codex Desktop" {
                    XCTAssertEqual(plan.targets.first, .codexApp(try XCTUnwrap(URL(string: "codex://threads/thread-test"))))
                } else if origin == "codex_vscode" {
                    XCTAssertEqual(plan.targets.first, .editor(bundleId: "com.microsoft.VSCode", cwd: "/tmp/a b'c"))
                    XCTAssertTrue(plan.targets.contains(.terminal(pid: 321, cwd: "/tmp/a b'c")))
                } else {
                    XCTAssertEqual(plan.targets.first, .terminal(pid: 321, cwd: "/tmp/a b'c"))
                }
                XCTAssertEqual(plan.resumeCommand, "cd '/tmp/a b'\"'\"'c' && codex resume 'thread-test'")
            }
            let path = try write(home, ".claude/projects/cli.jsonl", ["cwd": "/tmp/a b'c", "entrypoint": "cli"])
            let a = agent(.claude, path)
            XCTAssertEqual(JumpResolver.plan(agent: a, home: home).resumeCommand,
                "cd '/tmp/a b'\"'\"'c' && claude --resume '\(a.id)'")
            let exec = try write(home, "exec.jsonl", ["type": "thread.started", "thread_id": "exec-thread"])
            XCTAssertEqual(JumpResolver.plan(agent: agent(.codex, exec), home: home,
                processes: [CodexProcess(pid: 654, paths: [exec])]).targets.first, .terminal(pid: 654, cwd: "/tmp/project"))
            XCTAssertNil(JumpResolver.plan(agent: agent(.codex, exec), home: home).resumeCommand)
            _ = try write(home, ".codex/sessions/saved.jsonl", ["type": "session_meta", "payload": ["id": "exec-thread"]])
            XCTAssertEqual(JumpResolver.plan(agent: agent(.codex, exec), home: home).resumeCommand,
                "cd '/tmp/project' && codex resume 'exec-thread'")

            let id = "33333333-3333-4333-8333-333333333333"
            let saved = try write(home, ".codex/sessions/rollout-\(id).jsonl",
                ["type": "session_meta", "payload": ["id": id, "originator": "codex_cli_rs"]])
            let alias = home.appendingPathComponent("linked-sessions")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: home.appendingPathComponent(".codex/sessions"))
            let linked = alias.appendingPathComponent("rollout-\(id).jsonl").path
            var hook = agent(.codex, nil)
            hook.chatId = id
            XCTAssertEqual(JumpResolver.plan(agent: hook, home: home,
                processes: [CodexProcess(pid: 987, paths: [saved])]).targets.first, .terminal(pid: 987, cwd: hook.cwd))
            XCTAssertEqual(JumpResolver.plan(agent: agent(.codex, linked), home: home,
                processes: [CodexProcess(pid: 987, paths: [saved])]).targets.first, .terminal(pid: 987, cwd: hook.cwd))
        }
    }

}
