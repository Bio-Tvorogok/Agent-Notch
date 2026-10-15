import Foundation

struct RolloutLineageChecks {
    let thread = "019abcde-1234-7000-8000-0123456789ab"

    func rolloutPaths() {
        let root = URL(fileURLWithPath: "/home/test/.codex/sessions")
        let name = "rollout-2026-10-15T12-00-00-\(thread).jsonl"
        XCTAssertEqual(Proc.rolloutThread(root.appendingPathComponent("2026/10/15/" + name).path, in: root), thread)
        let base: String = root.path
        let outside: [String] = ["/tmp/\(name)", "\(base)-other/\(name)", "\(base)/\(name).bak",
                                 "\(base)/other-\(thread).jsonl", "\(base)/rollout-short.jsonl",
                                 "\(base)/rollout-019abcde-1234-7000-8000-0123456789az.jsonl",
                                 "\(base)/../\(name)"]
        for path in outside {
            XCTAssertNil(Proc.rolloutThread(path, in: root), path)
        }
    }

    func openRolloutFile() throws {
        let f = Fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        let file = try f.rollout(thread)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let paths = Proc.openPaths(getpid()).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        XCTAssertTrue(paths.contains(file.resolvingSymlinksInPath().path))
    }

    func workerKeepsItsParentAfterExitAndReset() throws {
        let f = Fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        try f.claude("claude")
        try f.rollout(thread, padding: 1024)
        var reported = [thread: ["claude"]]
        let scanner = LogScanner(home: f.home, execRuns: { [] }, rolloutParents: { reported })
        func check(_ at: Date, state: AgentState) throws {
            let agents = scanner.poll(now: at)!
            let worker = try XCTUnwrap(agents.first { $0.id == thread })
            XCTAssertEqual(worker.parentId, "claude")
            XCTAssertEqual(worker.state, state)
            let sessions = Tree.build(agents, includeFinished: true).flatMap(\.sessions)
            XCTAssertEqual(sessions.map(\.id), ["claude"])
            XCTAssertEqual(sessions.first?.kids.map(\.id), [thread])
        }
        try check(f.now, state: .working)
        reported = [:]
        try check(f.now.addingTimeInterval(6), state: .working)
        // Same inode, shorter log, between discoveries: the cached ancestry must survive read's reset.
        try f.rollout(thread, turn: "task_complete")
        try check(f.now.addingTimeInterval(7), state: .done)
        try check(f.now.addingTimeInterval(12), state: .done)
        // Once the thread is no longer tracked, rediscovery must not reuse its former ancestry.
        XCTAssertEqual(scanner.poll(now: f.now.addingTimeInterval(3601))!.count, 0)
        try f.rollout(thread, at: f.now.addingTimeInterval(3607))
        let rediscovered = scanner.poll(now: f.now.addingTimeInterval(3607))!
        XCTAssertNil(rediscovered.first { $0.id == thread }?.parentId)
    }

    func nativeParentWins() throws {
        let f = Fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        try f.claude("claude")
        try f.rollout("native-parent")
        try f.rollout(thread, parent: "native-parent")
        let scanner = LogScanner(home: f.home, execRuns: { [] }, rolloutParents: { [thread: ["claude"]] })
        XCTAssertEqual(scanner.poll(now: f.now)!.first { $0.id == thread }?.parentId, "native-parent")
    }

    func nearestParentAcrossVendors() throws {
        let f = Fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        try f.rollout("root")
        try f.claude("claude")
        try f.rollout(thread)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["--lineage-child"]
        process.environment = ["CODEX_THREAD_ID": "root"]
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let live = f.home.appendingPathComponent(".claude/sessions/live.json")
        try f.write([["pid": process.processIdentifier, "sessionId": "claude", "status": "busy"]], to: live)
        // The worker inherits both ids; CODEX_THREAD_ID appears first but is the more distant ancestor.
        let scanner = LogScanner(home: f.home, execRuns: { [] }, rolloutParents: { [thread: ["root", "claude"]] })
        let agents = scanner.poll(now: f.now)!
        XCTAssertEqual(agents.first { $0.id == "claude" }?.parentId, "root")
        XCTAssertEqual(agents.first { $0.id == thread }?.parentId, "claude")
        let sessions = Tree.build(agents).flatMap(\.sessions)
        XCTAssertEqual(sessions.map(\.id), ["root"])
        XCTAssertEqual(Set(sessions.first?.kids.map(\.id) ?? []), ["claude", thread])
    }

    func execStreamStillMerges() throws {
        let f = Fixture()
        defer { try? FileManager.default.removeItem(at: f.home) }
        try f.claude("claude")
        let rollout = try f.rollout(thread)
        let stream = f.home.appendingPathComponent("exec.jsonl")
        try f.write([["type": "thread.started", "thread_id": thread], ["type": "turn.started"]], to: stream)
        let run = ExecRun(pid: 7, log: stream.path, cwd: "/tmp/project", model: nil, effort: nil, parents: ["claude"])
        let scanner = LogScanner(home: f.home, execRuns: { [run] }, rolloutParents: { [thread: ["claude"]] })
        let agents = scanner.poll(now: f.now)!
        XCTAssertEqual(agents.count, 2)
        let worker = try XCTUnwrap(agents.first { $0.id == thread })
        XCTAssertEqual(worker.parentId, "claude")
        XCTAssertEqual(URL(fileURLWithPath: worker.logPath ?? "").resolvingSymlinksInPath().path,
                       rollout.resolvingSymlinksInPath().path)
    }

    private struct Fixture {
        let now = Date()
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rollout-lineage-\(UUID().uuidString)")

        func claude(_ id: String) throws {
            try write([["type": "user", "timestamp": ISO8601DateFormatter().string(from: now), "cwd": "/tmp/project",
                        "message": ["content": "go"]]], to: home.appendingPathComponent(".claude/projects/p/\(id).jsonl"))
        }

        @discardableResult
        func rollout(_ id: String, parent: String? = nil, turn: String = "task_started", padding: Int = 0, at: Date? = nil) throws -> URL {
            let date = at ?? now
            let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
            let day = String(format: ".codex/sessions/%04d/%02d/%02d", c.year!, c.month!, c.day!)
            let file = home.appendingPathComponent(day + "/rollout-2026-10-15T12-00-00-\(id).jsonl")
            var meta: Rec = ["id": id, "cwd": "/tmp/project"]
            if let parent { meta["source"] = ["subagent": ["thread_spawn": ["parent_thread_id": parent]]] }
            let stamp = ISO8601DateFormatter().string(from: date)
            try write([["type": "session_meta", "timestamp": stamp, "payload": meta],
                       ["type": "event_msg", "timestamp": stamp, "payload": ["type": turn, "padding": String(repeating: "x", count: padding)]]], to: file)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
            return file
        }

        func write(_ rows: [Rec], to file: URL) throws {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = Data()
            for row in rows { data.append(try JSONSerialization.data(withJSONObject: row)); data.append(10) }
            try data.write(to: file)
        }
    }
}
