import Foundation

struct CodexDiscoveryChecks {
    private let now = Date(timeIntervalSince1970: 1_792_065_600)
    private let fm = FileManager.default

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/codex-discovery/\(name).jsonl"))
    }

    private func file(in home: URL, daysAgo: Int = 0) throws -> URL {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: now.addingTimeInterval(Double(-daysAgo) * 86_400))
        let dir = home.appendingPathComponent(String(format: ".codex/sessions/%04d/%02d/%02d", c.year!, c.month!, c.day!))
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rollout.jsonl")
    }

    func resumedOldFolderAndAppendedTail() throws {
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let old = try file(in: home, daysAgo: 5)
        let recent = try file(in: home)
        try fixture("working").write(to: old)
        try fixture("done").write(to: recent)
        for f in [old, recent] { try fm.setAttributes([.modificationDate: now], ofItemAtPath: f.path) }
        let dir = old.deletingLastPathComponent()
        let stale = now.addingTimeInterval(-5 * 86_400)
        try fm.setAttributes([.modificationDate: stale], ofItemAtPath: old.path)
        try fm.setAttributes([.modificationDate: stale], ofItemAtPath: dir.path)
        let scanner = LogScanner(home: home, execRuns: { [] })
        XCTAssertEqual(scanner.poll(now: now)!.map(\.id), ["reset"])
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: old.path)
        XCTAssertEqual(scanner.poll(now: now.addingTimeInterval(60))!.map(\.id).sorted(), ["reset", "resumed"])
        let handle = try FileHandle(forWritingTo: old)
        // Previously consumed bytes must not be parsed again when only a tail is appended.
        let changedHead = try fixture("working")
        try handle.write(contentsOf: Data(String(decoding: changedHead, as: UTF8.self).replacingOccurrences(of: "resumed", with: "changed").utf8))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"type\":\"event_msg\",\"timestamp\":\"2026-10-15T12:00:01Z\",\"payload\":{\"type\":\"task_complete\"}}".utf8))
        XCTAssertEqual(scanner.poll(now: now.addingTimeInterval(61))!.first { $0.id == "resumed" }?.state, .working)
        try handle.write(contentsOf: Data([10]))
        try handle.close()
        XCTAssertEqual(scanner.poll(now: now.addingTimeInterval(62))!.first { $0.id == "resumed" }?.state, .done)
        // Appending an existing old file does not change its directory's modification date.
        XCTAssertEqual(try fm.attributesOfItem(atPath: dir.path)[.modificationDate] as? Date, stale)
        let added = dir.appendingPathComponent("added.jsonl")
        let addedLog = String(decoding: try fixture("working"), as: UTF8.self).replacingOccurrences(of: "resumed", with: "added")
        try Data(addedLog.utf8).write(to: added)
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: added.path)
        XCTAssertEqual(scanner.poll(now: now.addingTimeInterval(66))!.first { $0.id == "added" }?.state, .working)
    }

    func resetReadsBoundedTail(replaced: Bool) throws {
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let path = try file(in: home)
        let padding = Data((String(repeating: " ", count: 4096) + "\n").utf8)
        var initial = try fixture("working")
        for _ in 0..<800 { initial.append(padding) }
        try initial.write(to: path)
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: path.path)
        let scanner = LogScanner(home: home, execRuns: { [] })
        _ = scanner.poll(now: now)!
        var bytes = 0
        scanner.didRead = { bytes += $0 }
        var reset = try fixture("working")
        for _ in 0..<(replaced ? 900 : 600) { reset.append(padding) }
        reset.append(try fixture("done").split(separator: 10).last!)
        reset.append(10)
        let firstLineBytes = reset.firstIndex(of: 10)! + 1
        try reset.write(to: path, options: replaced ? .atomic : [])
        XCTAssertEqual(scanner.poll(now: now.addingTimeInterval(1))!.map(\.id), ["resumed"])
        XCTAssertEqual(scanner.poll(now: now.addingTimeInterval(2))!.map(\.state), [.done], "final state comes from the tail")
        XCTAssertTrue(bytes <= Int(LogScanner.tailBytes) + firstLineBytes, "reset read \(bytes) bytes, exceeding tail plus metadata")
    }


    func coldFoldersBoundStats() throws {
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let old = try file(in: home, daysAgo: 5)
        let dir = old.deletingLastPathComponent()
        let stale = now.addingTimeInterval(-5 * 86_400)
        for i in 0..<2_000 {
            let path = dir.appendingPathComponent("rollout-\(i).jsonl")
            try fixture("working").write(to: path)
            try fm.setAttributes([.modificationDate: stale], ofItemAtPath: path.path)
        }
        try fm.setAttributes([.modificationDate: stale], ofItemAtPath: dir.path)
        let scanner = LogScanner(home: home, execRuns: { [] })
        var stats = 0
        scanner.didStat = { if $0.hasSuffix(".jsonl") { stats += 1 } }
        _ = scanner.poll(now: now)!
        XCTAssertEqual(stats, 2_000)
        stats = 0
        _ = scanner.poll(now: now.addingTimeInterval(6))!
        XCTAssertEqual(stats, 0, "cold folders must skip per-file stats on the next pass")
        let resumed = dir.appendingPathComponent("rollout-0.jsonl")
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: resumed.path)
        var found = false
        for second in stride(from: 12, through: 60, by: 6) {
            if scanner.poll(now: now.addingTimeInterval(Double(second)))!.contains(where: { $0.id == "resumed" }) { found = true; break }
        }
        XCTAssertTrue(found, "an old rollout resumed without a directory change must appear within 60 seconds")
    }

    func recentListingsAreNeverTrusted(today: Bool) throws {
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let path = try file(in: home, daysAgo: today ? 0 : 5)
        let dir = path.deletingLastPathComponent()
        try fixture("working").write(to: path)
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: path.path)
        // Force equal directory stamps across a listing change (coarse filesystem timestamps).
        let stamp = now.addingTimeInterval(today ? -100 : -1)
        try fm.setAttributes([.modificationDate: stamp], ofItemAtPath: dir.path)
        let scanner = LogScanner(home: home, execRuns: { [] })
        _ = scanner.poll(now: now)!
        let added = dir.appendingPathComponent("added.jsonl")
        try fixture("done").write(to: added)
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: added.path)
        try fm.setAttributes([.modificationDate: stamp], ofItemAtPath: dir.path)
        // A retention change forces discovery inside the two-second timestamp window.
        XCTAssertTrue(scanner.poll(now: now.addingTimeInterval(0.5), finishedRetention: 1_801)!.contains { $0.id == "reset" })
    }

    func overlappingPollsCoalesce() throws {
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var calls = 0, active = 0, peak = 0
        let scanner = LogScanner(home: home, execRuns: {
            lock.lock()
            calls += 1; active += 1; peak = max(peak, active)
            let first = calls == 1
            lock.unlock()
            if first { entered.signal(); _ = release.wait(timeout: .now() + 10) }
            lock.lock(); active -= 1; lock.unlock()
            return []
        })
        DispatchQueue.global().async { _ = scanner.poll(now: now)!; finished.signal() }
        XCTAssertEqual(entered.wait(timeout: .now() + 10), .success)
        for i in 1...8 { XCTAssertNil(scanner.poll(now: now.addingTimeInterval(Double(i * 6))), "folded calls must not publish a snapshot") }
        release.signal()
        XCTAssertEqual(finished.wait(timeout: .now() + 10), .success)
        lock.lock(); let count = calls, maximum = peak; lock.unlock()
        XCTAssertEqual(maximum, 1, "no overlapping discovery")
        XCTAssertEqual(count, 2, "triggers become one pending scan with the latest time")
    }
}
