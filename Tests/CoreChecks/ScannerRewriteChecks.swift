import Foundation

struct ScannerRewriteChecks {
    func partialLinesWaitForTheirNewline() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("partial-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent("exec.jsonl")
        try Data("{\"type\":\"thread.started\",\"thread_id\":\"partial\"}\n{\"type\":\"turn.started\"}\n\ninvalid\n{\"type\":\"turn.comp".utf8).write(to: file)
        let run = ExecRun(pid: 1, log: file.path, cwd: "/tmp", model: nil, effort: nil)
        let scanner = LogScanner(home: home, execRuns: { [run] })
        XCTAssertEqual(scanner.poll().map(\.state), [.working])
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("leted\",\"note\":\"Привет\\nмир\"}".utf8))
        XCTAssertEqual(scanner.poll().map(\.state), [.working], "a complete JSON value without newline is still pending")
        try handle.write(contentsOf: Data([10]))
        XCTAssertEqual(scanner.poll().map(\.state), [.done])
    }

    func rewrittenLogClearsThePreviousTurn() throws {
        let now = Date()
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rewrite-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let day = home.appendingPathComponent(String(format: ".codex/sessions/%04d/%02d/%02d", c.year!, c.month!, c.day!))
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let file = day.appendingPathComponent("rollout.jsonl")
        let stamp = ISO8601DateFormatter().string(from: now)
        func log(_ turn: String, padding: Int = 0) -> Data {
            Data(("{\"type\":\"session_meta\",\"timestamp\":\"\(stamp)\",\"payload\":{\"id\":\"rewrite\",\"cwd\":\"/tmp\"}}\n" +
                  "{\"type\":\"event_msg\",\"timestamp\":\"\(stamp)\",\"payload\":{\"type\":\"\(turn)\"}}\n" +
                  String(repeating: " ", count: padding) + "\n").utf8)
        }
        try log("task_started", padding: 1024).write(to: file)
        let scanner = LogScanner(home: home, execRuns: { [] })
        XCTAssertEqual(scanner.poll(now: now).map(\.state), [.working])
        // Same inode, shorter contents: offsets from the old log must be discarded.
        try log("task_complete").write(to: file)
        XCTAssertEqual(scanner.poll(now: now.addingTimeInterval(1)).map(\.state), [.done])
        // Atomic replacement can be larger than the previous file and still needs a fresh parse.
        try log("task_started", padding: 2048).write(to: file, options: .atomic)
        XCTAssertEqual(scanner.poll(now: now.addingTimeInterval(2)).map(\.state), [.working])
        try log("task_complete", padding: 4096).write(to: file, options: .atomic)
        XCTAssertEqual(scanner.poll(now: now.addingTimeInterval(3)).map(\.state), [.done])
    }
}
