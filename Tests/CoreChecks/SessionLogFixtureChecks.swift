import Foundation

struct SessionLogFixtureChecks {
    private let fm = FileManager.default
    private let now = Date(timeIntervalSince1970: LogText.time("2026-10-13T10:00:10Z")!)
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/SessionLogs")
    }

    private func data(_ name: String) throws -> Data {
        try Data(contentsOf: fixtures.appendingPathComponent(name))
    }

    private func home(_ body: (URL) throws -> Void) throws {
        let root = fm.temporaryDirectory.appendingPathComponent("session-fixtures-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try body(root)
    }

    @discardableResult
    private func install(_ name: String, at path: String, in root: URL) throws -> URL {
        let file = root.appendingPathComponent(path)
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data(name).write(to: file)
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
        return file
    }

    private func codexPath(daysAgo: Int = 0) -> String {
        let day = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return String(format: ".codex/sessions/%04d/%02d/%02d/rollout-fixture.jsonl", c.year!, c.month!, c.day!)
    }

    private func session(_ name: String, vendor: Vendor, id: String, parent: String? = nil) throws -> SessionLog {
        var log = SessionLog(id: id, vendor: vendor, parentId: parent)
        for line in try data(name).split(separator: 10) {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? Rec else { continue }
            if vendor == .claude { ClaudeLine.apply(record, to: &log, isSubagent: parent != nil) }
            else { CodexLine.apply(record, to: &log) }
        }
        return log
    }

    func claudeSubagents() throws {
        try home { root in
            let base = ".claude/projects/sample/"
            let parent = try install("claude/parent.jsonl", at: base + "parent.jsonl", in: root)
            let child = try install("claude/agent-inspect.jsonl", at: base + "parent/subagents/agent-inspect.jsonl", in: root)
            try install("claude/agent-plan.jsonl", at: base + "parent/subagents/workflows/sample/agent-plan.jsonl", in: root)
            let agents = LogScanner(home: root, execRuns: { [] }).poll(now: now)!
            XCTAssertEqual(agents.count, 3)
            let main = try XCTUnwrap(agents.first { $0.id == "parent" })
            XCTAssertEqual(main.state, .working)
            XCTAssertEqual(main.model, "claude-sonnet-4-6")
            XCTAssertEqual(main.title, "fixture/readers")
            XCTAssertEqual(main.chatId, "parent")
            let inspect = try XCTUnwrap(agents.first { $0.id == "parent/inspect" })
            XCTAssertEqual(inspect.parentId, "parent")
            XCTAssertEqual(inspect.state, .done)
            XCTAssertEqual(inspect.model, "claude-haiku-4-5")
            XCTAssertNil(inspect.activity)
            XCTAssertEqual(inspect.chatId, "parent")
            let plan = try XCTUnwrap(agents.first { $0.id == "parent/plan" })
            XCTAssertEqual(plan.parentId, "parent")
            XCTAssertEqual(plan.state, .working)
            XCTAssertEqual(plan.activity, "Bash · find Tests -type f")
            let log = try session("claude/agent-inspect.jsonl", vendor: .claude, id: "parent/inspect", parent: "parent")
            XCTAssertTrue(log.turnEnded)
            XCTAssertEqual(log.state(now: now.timeIntervalSince1970), .done)
            let detail = try XCTUnwrap(DetailReader.read(path: parent.path, vendor: .claude))
            XCTAssertEqual(detail.prompts.map(\.text), ["Check the sample project."])
            XCTAssertEqual(detail.commands.map(\.command), ["swift test"])
            XCTAssertEqual(detail.commands.map(\.ok), [true])
            XCTAssertEqual(detail.lastMessage, "Sample checks passed.")
            let sub = try XCTUnwrap(DetailReader.read(path: child.path, vendor: .claude, agentId: inspect.id))
            XCTAssertTrue(sub.prompts.isEmpty)
            XCTAssertEqual(sub.commands.map(\.command), ["ls Sources"])
            XCTAssertEqual(sub.lastMessage, "Sources inspected.")
            XCTAssertNil(DetailReader.read(path: child.path, vendor: .claude))
        }
    }

    func codexCurrent() throws {
        try home { root in
            let file = try install("codex/current.jsonl", at: codexPath(), in: root)
            let agent = try XCTUnwrap(LogScanner(home: root, execRuns: { [] }).poll(now: now)!.first)
            XCTAssertEqual(agent.id, "fixture-current")
            XCTAssertEqual(agent.state, .waiting)
            XCTAssertEqual(agent.ask, "echo approved")
            XCTAssertEqual(agent.model, "gpt-6.1-sol")
            XCTAssertEqual(agent.effort, .high)
            XCTAssertEqual(agent.title, "fixture/current")
            XCTAssertEqual(agent.activity, "shell · swift test")
            let log = try session("codex/current.jsonl", vendor: .codex, id: "filename")
            XCTAssertEqual(log.agent(now: now.timeIntervalSince1970, project: { _ in "sample" })?.ask, agent.ask)
            let detail = try XCTUnwrap(DetailReader.read(path: file.path, vendor: .codex))
            XCTAssertEqual(detail.prompts.map(\.text), ["Run the sample checks."])
            XCTAssertEqual(detail.commands.map(\.command), ["swift test"])
            XCTAssertEqual(detail.commands.map(\.ok), [true])
            XCTAssertEqual(detail.lastMessage, "Current checks passed.")
            XCTAssertEqual(detail.meta.effort, .high)
        }
    }

    func codexLegacy() throws {
        try home { root in
            let file = try install("codex/legacy.jsonl", at: codexPath(), in: root)
            let agent = try XCTUnwrap(LogScanner(home: root, execRuns: { [] }).poll(now: now)!.first)
            XCTAssertEqual(agent.id, "fixture-legacy")
            XCTAssertEqual(agent.state, .done)
            XCTAssertEqual(agent.model, "gpt-5-codex")
            XCTAssertEqual(agent.effort, .medium)
            XCTAssertEqual(agent.title, "fixture/legacy")
            XCTAssertNil(agent.ask)
            XCTAssertNil(agent.activity)
            let log = try session("codex/legacy.jsonl", vendor: .codex, id: "filename")
            XCTAssertEqual(log.id, agent.id)
            XCTAssertTrue(log.turnEnded)
            let detail = try XCTUnwrap(DetailReader.read(path: file.path, vendor: .codex))
            XCTAssertEqual(detail.prompts.map(\.text), ["Check the older sample."])
            XCTAssertEqual(detail.commands.map(\.command), ["sh -c swift test"])
            XCTAssertEqual(detail.commands.map(\.ok), [true])
            XCTAssertEqual(detail.lastMessage, "Older checks passed.")
            XCTAssertEqual(detail.meta.model, "gpt-5-codex")
        }
    }

    func resumedReaders() throws {
        try home { root in
            let file = try install("codex/resumed.jsonl", at: codexPath(daysAgo: 12), in: root)
            let log = try session("codex/resumed.jsonl", vendor: .codex, id: "filename")
            XCTAssertEqual(log.id, "fixture-resumed")
            XCTAssertEqual(log.startedAt, LogText.time("2026-10-01T10:00:00Z"))
            XCTAssertEqual(log.lastAt, LogText.time("2026-10-13T10:00:04Z"))
            XCTAssertEqual(log.state(now: now.timeIntervalSince1970), .working)
            let detail = try XCTUnwrap(DetailReader.read(path: file.path, vendor: .codex))
            XCTAssertEqual(detail.lastMessage, "Resumed sample is running.")
            XCTAssertEqual(detail.prompts.map(\.text), ["Continue the sample checks."])
            XCTAssertEqual(detail.meta.startedAt, log.startedAt)
        }
    }

    func resumedDiscoveryExpectedFail() throws {
        try home { root in
            let file = try install("codex/resumed.jsonl", at: codexPath(daysAgo: 12), in: root)
            XCTAssertEqual(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, now)
            let agents = LogScanner(home: root, execRuns: { [] }).poll(now: now)!
            XCTAssertEqual(agents.map(\.id), ["fixture-resumed"], "EXPECTED-FAIL: fresh mtime must outweigh the old date folder")
        }
    }

    private func append(_ data: Data, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    func truncatedRecovery() throws {
        try home { root in
            let file = try install("codex/truncated.jsonl", at: codexPath(), in: root)
            let scanner = LogScanner(home: root, execRuns: { [] })
            XCTAssertEqual(scanner.poll(now: now)!.map(\.state), [.working])
            XCTAssertEqual(DetailReader.read(path: file.path, vendor: .codex)?.lastMessage, "Complete message before tail.")
            let log = try session("codex/truncated.jsonl", vendor: .codex, id: "filename")
            XCTAssertEqual(log.lastAt, LogText.time("2026-10-13T10:00:02Z"))
            try append(data("codex/truncated-suffix.txt"), to: file)
            // Valid JSON is still pending until the writer commits its newline.
            XCTAssertNil(scanner.poll(now: now)!.first?.activity)
            try append(Data([10]), to: file)
            XCTAssertEqual(scanner.poll(now: now)!.first?.activity, "exec_command · echo recovered")
            XCTAssertEqual(DetailReader.read(path: file.path, vendor: .codex)?.commands.map(\.command), ["echo recovered"])
        }
    }

    func truncatedTailExpectedFail() throws {
        try home { root in
            let file = try install("codex/truncated.jsonl", at: codexPath(), in: root)
            try append(data("codex/truncated-suffix.txt"), to: file)
            XCTAssertEqual(DetailReader.read(path: file.path, vendor: .codex)?.commands.map(\.command),
                           [], "EXPECTED-FAIL: detail must leave the uncommitted tail pending like the scanner")
        }
    }

    func rotation() throws {
        try home { root in
            let file = try install("codex/current.jsonl", at: codexPath(), in: root)
            let scanner = LogScanner(home: root, execRuns: { [] })
            XCTAssertEqual(scanner.poll(now: now)!.map(\.state), [.waiting])
            let inode = try fm.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber
            XCTAssertTrue(try data("codex/rotated.jsonl").count > data("codex/current.jsonl").count)
            // Keep the original inode alive while replacing the path with a larger file.
            try fm.moveItem(at: file, to: file.appendingPathExtension("old"))
            try install("codex/rotated.jsonl", at: codexPath(), in: root)
            let replacement = try fm.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber
            XCTAssertTrue(inode != nil && replacement != nil && inode != replacement)
            let agents = scanner.poll(now: now.addingTimeInterval(1))!
            XCTAssertEqual(agents.count, 1)
            let agent = try XCTUnwrap(agents.first)
            XCTAssertEqual(agent.id, "fixture-rotated")
            XCTAssertEqual(agent.state, .done)
            XCTAssertEqual(agent.title, "fixture/rotated")
            XCTAssertEqual(agent.effort, .low)
            XCTAssertNil(agent.ask)
            XCTAssertNil(agent.activity)
            let detail = try XCTUnwrap(DetailReader.read(path: file.path, vendor: .codex))
            XCTAssertEqual(detail.prompts.map(\.text), ["Read the replacement sample."])
            XCTAssertTrue(detail.commands.isEmpty)
            XCTAssertEqual(detail.lastMessage, "Replacement checks passed.")
            let log = try session("codex/rotated.jsonl", vendor: .codex, id: "filename")
            XCTAssertEqual(log.id, agent.id)
            XCTAssertEqual(log.state(now: now.timeIntervalSince1970), agent.state)
        }
    }
}
