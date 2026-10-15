import Foundation

struct ExecIdentityChecks {
    func relativeDirectoryUsesTheRunningProcess() {
        let run = ExecRun.parse(pid: getpid(), args: ["codex", "exec", "--json", "-C", "."], stdout: "/tmp/job.jsonl")
        XCTAssertEqual(run?.cwd, FileManager.default.currentDirectoryPath,
                       "a relative -C must resolve against the Codex process, not the app")
        let base = FileManager.default.currentDirectoryPath
        for (relative, expected) in [("child", base + "/child"), ("..", (base as NSString).deletingLastPathComponent)] {
            let run = ExecRun.parse(pid: getpid(), args: ["codex", "exec", "--json", "-C", relative], stdout: "/tmp/job.jsonl")
            XCTAssertEqual(run?.cwd, expected, "keep the relative -C operand")
        }
    }

    func resumedRunUsesTheRunningProcessDirectory() {
        let run = ExecRun.parse(pid: getpid(), args: ["codex", "exec", "resume", "--json", "thread", "-"], stdout: "/tmp/job.jsonl")
        XCTAssertEqual(run?.cwd, FileManager.default.currentDirectoryPath,
                       "resume has no -C; its process still has a working directory")
    }

    func retainedSessionAndExecStreamMakeOneRow() throws {
        let now = Date()
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("identity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let day = home.appendingPathComponent(String(format: ".codex/sessions/%04d/%02d/%02d", components.year!, components.month!, components.day!))
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let session = day.appendingPathComponent("rollout-thread.jsonl")
        let stamp = ISO8601DateFormatter().string(from: now)
        let rows: [Rec] = [
            ["type": "session_meta", "timestamp": stamp, "payload": ["id": "thread", "cwd": "/tmp/man-clarity", "git": ["branch": "fix/man-clarity"]]],
            ["type": "event_msg", "timestamp": stamp, "payload": ["type": "user_message", "message": "Check the menu"]],
            ["type": "response_item", "timestamp": stamp, "payload": ["type": "message", "role": "user", "content": [["type": "input_text", "text": "Check the menu"]]]],
            ["type": "event_msg", "timestamp": stamp, "payload": ["type": "exec_approval_request", "command": "touch menu.swift"]],
        ]
        try write(rows, to: session)
        let exec = home.appendingPathComponent("job.jsonl")
        try write([["type": "thread.started", "thread_id": "thread"], ["type": "turn.started"]], to: exec)
        let run = ExecRun(pid: 7, log: exec.path, cwd: "/tmp/man-clarity", model: "gpt-6.1-sol", effort: .medium)
        let scanner = LogScanner(home: home, execRuns: { [run] })
        var sounds = SoundAgentWatcher()
        for at in [now, now.addingTimeInterval(6), now.addingTimeInterval(12)] {
            let agents = scanner.poll(now: at)!
            XCTAssertEqual(agents.count, 1, "the rollout and stdout belong to the same thread")
            let agent = try XCTUnwrap(agents.first { $0.chatId == "thread" })
            XCTAssertEqual(URL(fileURLWithPath: agent.logPath ?? "").resolvingSymlinksInPath().path, session.resolvingSymlinksInPath().path)
            XCTAssertEqual(sounds.update(agents), [], "one unchanged approval must not beep on every poll")
            XCTAssertEqual(agent.title, "fix/man-clarity")
            XCTAssertEqual(agent.state, .waiting, "the full session retains pending approval")
            XCTAssertEqual(agent.chatId, "thread", "the retained thread stays resumable")
            XCTAssertEqual(DetailReader.read(path: session.path, vendor: .codex)?.prompts.count, 1, "the card keeps the user's prompts")
        }
    }

    func distinctThreadsInOneDirectoryStaySeparate() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        var runs: [ExecRun] = []
        for id in ["one", "two"] {
            let path = home.appendingPathComponent("\(id).jsonl")
            try write([["type": "thread.started", "thread_id": id], ["type": "turn.started"]], to: path)
            runs.append(ExecRun(pid: 7, log: path.path, cwd: "/tmp/shared", model: nil, effort: nil))
        }
        let scanner = LogScanner(home: home, execRuns: { runs })
        XCTAssertEqual(Set(scanner.poll()!.map(\.id)), ["one", "two"], "matching project or title is not matching identity")
    }

    func retainedSessionUsesExecLifecycle() throws {
        let now = Date()
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("lifecycle-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let day = home.appendingPathComponent(String(format: ".codex/sessions/%04d/%02d/%02d", components.year!, components.month!, components.day!))
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let session = day.appendingPathComponent("rollout-thread.jsonl")
        let stamp = ISO8601DateFormatter().string(from: now)
        try write([
            ["type": "session_meta", "timestamp": stamp, "payload": ["id": "thread", "cwd": "/tmp/man", "source": ["subagent": ["thread_spawn": ["parent_thread_id": "parent", "agent_path": "root/menu"]]]]],
            ["type": "event_msg", "timestamp": stamp, "payload": ["type": "task_complete"]]
        ], to: session)
        let exec = home.appendingPathComponent("job.jsonl")
        try write([["type": "thread.started", "thread_id": "thread"], ["type": "turn.started"]], to: exec)
        var running = [ExecRun(pid: 7, log: exec.path, cwd: "/tmp/man", model: "gpt-6.1-sol", effort: .medium)]
        let scanner = LogScanner(home: home, execRuns: { running })
        var sounds = SoundAgentWatcher()
        let resumed = scanner.poll(now: now)!
        XCTAssertEqual(resumed.map(\.state), [.working], "the previous completed turn cannot hide a running resume")
        XCTAssertEqual(resumed.first?.parentId, "parent")
        XCTAssertEqual(sounds.update(resumed), [])
        XCTAssertEqual(sounds.update(scanner.poll(now: now.addingTimeInterval(6))!), [], "a stale completed rollout must not repeatedly sound finished")
        running = []
        let ended = scanner.poll(now: now.addingTimeInterval(12))!
        XCTAssertEqual(ended.map(\.state), [.done], "a process exit ends the run even without a final rollout event")
        XCTAssertEqual(sounds.update(ended), [.agentFinished])
        XCTAssertEqual(sounds.update(scanner.poll(now: now.addingTimeInterval(18))!), [])
        let handle = try FileHandle(forWritingTo: session)
        try handle.seekToEnd()
        for (type, second) in [("task_started", 24), ("exec_approval_request", 30)] {
            let stamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(Double(second)))
            let payload: Rec = ["type": type, "command": "touch menu.swift"]
            var data = try JSONSerialization.data(withJSONObject: ["type": "event_msg", "timestamp": stamp, "payload": payload])
            data.append(10)
            try handle.write(contentsOf: data)
            let resumed = scanner.poll(now: now.addingTimeInterval(Double(second)))!
            XCTAssertEqual(resumed.map(\.state), [type == "task_started" ? .working : .waiting], "old stdout cannot mask a later interactive turn")
        }
        try handle.close()

    }

    func longExecStreamKeepsThreadIdentity() throws {
        let now = Date()
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("long-identity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let day = home.appendingPathComponent(String(format: ".codex/sessions/%04d/%02d/%02d", components.year!, components.month!, components.day!))
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: now)
        try write([["type": "session_meta", "timestamp": stamp, "payload": ["id": "thread", "cwd": "/tmp/man"]]], to: day.appendingPathComponent("rollout-thread.jsonl"))
        let exec = home.appendingPathComponent("job.jsonl")
        try write([["type": "thread.started", "thread_id": "thread"],
                   ["type": "item.completed", "item": ["id": "large", "type": "agent_message", "text": String(repeating: "x", count: Int(LogScanner.tailBytes) + 100)]],
                   ["type": "turn.started"]], to: exec)
        let run = ExecRun(pid: 7, log: exec.path, cwd: "/tmp/man", model: nil, effort: nil)
        let agents = LogScanner(home: home, execRuns: { [run] }).poll(now: now)!
        XCTAssertEqual(agents.map(\.id), ["thread"], "tailing must not skip the identity in the first line")
    }

    private func write(_ rows: [Rec], to url: URL) throws {
        var data = Data()
        for row in rows { data.append(try JSONSerialization.data(withJSONObject: row)); data.append(0x0A) }
        try data.write(to: url)
    }
}
