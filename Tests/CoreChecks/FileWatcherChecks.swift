import CoreServices
import Foundation

struct FileWatcherChecks {
    func changedPathsAndLiveness() throws {
        let home = URL(fileURLWithPath: "/tmp/an06-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let dir = home.appendingPathComponent(".claude/projects/p")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let first = dir.appendingPathComponent("first.jsonl")
        let second = dir.appendingPathComponent("second.jsonl")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let working = "{\"type\":\"user\",\"timestamp\":\"\(stamp)\",\"message\":{\"content\":\"work\"}}\n"
        try working.write(to: first, atomically: true, encoding: .utf8)
        try working.write(to: second, atomically: true, encoding: .utf8)
        let scanner = LogScanner(home: home, execRuns: { [] }, rolloutParents: { [:] })
        XCTAssertEqual(scanner.poll()!.count, 2)
        var stats: [String] = [], bytes = 0
        scanner.didStat = { stats.append($0) }
        scanner.didRead = { bytes += $0 }
        _ = scanner.poll(changes: .paths([]))
        XCTAssertEqual(stats, [], "liveness does not stat logs")
        XCTAssertEqual(bytes, 0)
        let added = dir.appendingPathComponent("added.jsonl")
        try working.write(to: added, atomically: true, encoding: .utf8)
        let agents = scanner.poll(changes: .paths([added.path]))!
        XCTAssertEqual(Set(agents.map(\.id)), ["first", "second", "added"])
        XCTAssertFalse(stats.contains { URL(fileURLWithPath: $0).lastPathComponent == "first.jsonl" })
        let liveDir = home.appendingPathComponent(".claude/sessions")
        try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
        let live = liveDir.appendingPathComponent("live.json")
        try "{\"sessionId\":\"first\",\"status\":\"waiting\",\"pid\":\(getpid())}".write(to: live, atomically: true, encoding: .utf8)
        XCTAssertEqual(scanner.poll(changes: .paths([live.path]))!.first { $0.id == "first" }?.state, .waiting)
        try FileManager.default.removeItem(at: live)
        XCTAssertEqual(scanner.poll(changes: .paths([live.path]))!.first { $0.id == "first" }?.state, .working)
    }

    func subagentsAndOldCodexPaths() throws {
        let home = URL(fileURLWithPath: "/tmp/an06-paths-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: home) }
        let scanner = LogScanner(home: home, execRuns: { [] }, rolloutParents: { [:] })
        _ = scanner.poll(changes: .full)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let sub = home.appendingPathComponent(".claude/projects/p/main/subagents/workflows/run/agent-child.jsonl")
        try FileManager.default.createDirectory(at: sub.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{\"type\":\"user\",\"timestamp\":\"\(stamp)\",\"message\":{\"content\":\"work\"}}\n".write(to: sub, atomically: true, encoding: .utf8)
        let old = home.appendingPathComponent(".codex/sessions/2020/01/01/rollout.jsonl")
        try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{\"type\":\"session_meta\",\"timestamp\":\"\(stamp)\",\"payload\":{\"id\":\"resumed\"}}\n".write(to: old, atomically: true, encoding: .utf8)
        let agents = scanner.poll(changes: .paths([sub.path, old.deletingLastPathComponent().path]))!
        XCTAssertEqual(Set(agents.map(\.id)), ["main/child", "resumed"])
        XCTAssertEqual(agents.first { $0.id == "main/child" }?.parentId, "main")
        // An unreported append to an archived rollout must be recovered by the safety/drop scan.
        let missed = old.deletingLastPathComponent().appendingPathComponent("missed.jsonl")
        try "{\"type\":\"session_meta\",\"timestamp\":\"\(stamp)\",\"payload\":{\"id\":\"missed\"}}\n".write(to: missed, atomically: true, encoding: .utf8)
        XCTAssertTrue(scanner.poll(changes: .full)!.contains { $0.id == "missed" })
    }

    func processExitNeedsNoDiskRead() throws {
        let home = URL(fileURLWithPath: "/tmp/an06-live-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: home) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        let log = home.appendingPathComponent(".claude/projects/p/main.jsonl")
        let live = home.appendingPathComponent(".claude/sessions/live.json")
        for f in [log, live] { try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true) }
        let stamp = ISO8601DateFormatter().string(from: Date())
        try "{\"type\":\"user\",\"timestamp\":\"\(stamp)\",\"message\":{\"content\":\"work\"}}\n".write(to: log, atomically: true, encoding: .utf8)
        try "{\"sessionId\":\"main\",\"status\":\"waiting\",\"pid\":\(process.processIdentifier)}".write(to: live, atomically: true, encoding: .utf8)
        let scanner = LogScanner(home: home, execRuns: { [] }, rolloutParents: { [:] })
        XCTAssertEqual(scanner.poll(changes: .full)!.first?.state, .waiting)
        process.terminate()
        process.waitUntilExit()
        var stats = 0, reads = 0
        scanner.didStat = { _ in stats += 1 }
        scanner.didRead = { reads += $0 }
        XCTAssertEqual(scanner.poll(changes: .paths([]))!.first?.state, .done)
        XCTAssertEqual(stats, 0)
        XCTAssertEqual(reads, 0)
    }

    func queuedDropSurvivesLegacyPoll() throws {
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0), lock = NSLock()
        var calls = 0
        let now = Date()
        let scanner = LogScanner(home: URL(fileURLWithPath: "/tmp/an06-empty-\(UUID().uuidString)"), execRuns: {
            lock.lock(); calls += 1; let first = calls == 1; lock.unlock()
            if first { entered.signal(); _ = release.wait(timeout: .now() + 5) }
            return []
        }, rolloutParents: { [:] })
        DispatchQueue.global().async { _ = scanner.poll(now: now); finished.signal() }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)
        XCTAssertNil(scanner.poll(now: now, changes: .full))
        XCTAssertNil(scanner.poll(now: now))
        release.signal()
        XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(calls, 2, "a legacy poll must not downgrade a queued dropped-event rescan")
    }

    func droppedEventsRequestFullScan() {
        let path = "/tmp/an06-watch/projects/a.jsonl"
        XCTAssertEqual(FileChanges.events(paths: [path], flags: [UInt32(kFSEventStreamEventFlagItemModified)]), .paths([path]))
        for flag in [kFSEventStreamEventFlagMustScanSubDirs, kFSEventStreamEventFlagUserDropped,
                     kFSEventStreamEventFlagKernelDropped, kFSEventStreamEventFlagRootChanged,
                     kFSEventStreamEventFlagEventIdsWrapped, kFSEventStreamEventFlagMount, kFSEventStreamEventFlagUnmount] {
            XCTAssertEqual(FileChanges.events(paths: [path], flags: [UInt32(flag)]), .full)
        }
        XCTAssertEqual(FileChanges.paths([path]).merging(.full), .full)
        XCTAssertEqual(FileChanges.paths([path]).merging(.paths(["/b"])), .paths([path, "/b"]))
    }
}

extension FileWatcherChecks {
    func processDiscoveryDrainsExitedStreams() throws {
        let home = URL(fileURLWithPath: "/tmp/an06-exec-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent("stdout.jsonl")
        try Data().write(to: file)
        var runs: [ExecRun] = []
        let scanner = LogScanner(home: home, execRuns: { runs }, rolloutParents: { [:] })
        XCTAssertEqual(scanner.poll(changes: .full)!.count, 0)
        runs = [ExecRun(pid: getpid(), log: file.path, cwd: nil, model: nil, effort: nil)]
        XCTAssertEqual(scanner.poll(changes: .processes)!.first?.state, .working)
        try "{\"type\":\"thread.started\",\"thread_id\":\"final-id\"}\n{\"type\":\"turn.completed\"}\n".write(to: file, atomically: true, encoding: .utf8)
        runs = []
        let agents = scanner.poll(changes: .processes)!
        XCTAssertEqual(agents.map(\.id), ["final-id"])
        XCTAssertEqual(agents.map(\.state), [.done])
    }

    func remapsSymlinkedRootsAndStatusDirectories() throws {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: "/tmp/an06-links-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: home) }
        let stamp = ISO8601DateFormatter().string(from: Date())
        for name in ["old", "new"] {
            let project = home.appendingPathComponent(name + "/projects/p")
            let live = home.appendingPathComponent(name + "/sessions")
            try fm.createDirectory(at: project, withIntermediateDirectories: true)
            try fm.createDirectory(at: live, withIntermediateDirectories: true)
            try "{\"type\":\"user\",\"timestamp\":\"\(stamp)\",\"message\":{\"content\":\"work\"}}\n".write(to: project.appendingPathComponent(name + ".jsonl"), atomically: true, encoding: .utf8)
            try "{\"sessionId\":\"\(name)\",\"status\":\"waiting\",\"pid\":\(getpid())}".write(to: live.appendingPathComponent("live.json"), atomically: true, encoding: .utf8)
        }
        let link = home.appendingPathComponent(".claude")
        try fm.createSymbolicLink(at: link, withDestinationURL: home.appendingPathComponent("old"))
        let scanner = LogScanner(home: home, execRuns: { [] }, rolloutParents: { [:] })
        XCTAssertEqual(scanner.poll(changes: .full)!.map(\.id), ["old"])
        XCTAssertTrue(scanner.watchPaths.contains(link.path))
        try fm.removeItem(at: link)
        try fm.createSymbolicLink(at: link, withDestinationURL: home.appendingPathComponent("new"))
        let agents = scanner.poll(changes: .paths([link.path]))!
        XCTAssertEqual(agents.map(\.id), ["new"])
        XCTAssertEqual(agents.map(\.state), [.waiting])
        // Repoint only sessions while projects remains unchanged.
        let status = home.appendingPathComponent("new/sessions")
        try fm.removeItem(at: status)
        try fm.createSymbolicLink(at: status, withDestinationURL: home.appendingPathComponent("old/sessions"))
        XCTAssertEqual(scanner.poll(changes: .paths([status.path]))!.first?.state, .working)
        XCTAssertTrue(scanner.watchPaths.contains { $0.hasSuffix("/old/sessions") })
    }
}


extension FileWatcherChecks {
    func canonicalEventsAndLiveDelivery() throws {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: "/tmp/an06-events-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let projects = home.appendingPathComponent(".claude/projects")
        let sessions = home.appendingPathComponent(".codex/sessions")
        for dir in [projects, sessions] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        let files = [projects.appendingPathComponent("new/a.jsonl"),
                     sessions.appendingPathComponent("2026/10/16/a.jsonl"), home.appendingPathComponent("stdout.jsonl")]
        let canonical = ConfigRoots.physical(home).path
        XCTAssertEqual(FileChanges.events(paths: [canonical], flags: [UInt32(kFSEventStreamEventFlagItemCreated)]), .paths([canonical]), "existing /private/tmp paths must not be rewritten")
        let expected = Set(files.map { ConfigRoots.physical($0).path })
        XCTAssertEqual(FileChanges.events(paths: Array(expected), flags: Array(repeating: UInt32(kFSEventStreamEventFlagItemCreated), count: expected.count)), .paths(expected), "FSEvents canonical spellings must survive filtering")
        let delivered = EventDelivery(expected: expected)
        let watcher = FileWatcher(paths: [projects.path, sessions.path, files[2].path]) { delivered.receive($0) }
        guard watcher.isWatching else {
            if ProcessInfo.processInfo.environment["NOTCH_REQUIRE_FSEVENTS"] == "1" { XCTFail("FSEventStreamStart failed") }
            print("NOT verified: live /tmp FSEvents delivery (stream startup denied); canonical path check ran")
            return
        }
        for file in files {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "{}\n".write(to: file, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(delivered.ready.wait(timeout: .now() + 2), .success, "real /tmp JSONL events must arrive within 2s")
        withExtendedLifetime(watcher) {}
    }

    func execInterestsStayOnFiles() throws {
        let home = URL(fileURLWithPath: "/tmp/an06-interest-\(UUID().uuidString)")
        let file = home.appendingPathComponent("stdout.jsonl").path
        let scanner = LogScanner(home: home, execRuns: { [ExecRun(pid: getpid(), log: file, cwd: nil, model: nil, effort: nil)] }, rolloutParents: { [:] })
        _ = scanner.poll(changes: .full)
        XCTAssertTrue(scanner.watchPaths.contains(file))
        XCTAssertFalse(scanner.watchPaths.contains(home.path))
    }
}

private final class EventDelivery: @unchecked Sendable {
    let ready = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var remaining: Set<String>
    init(expected: Set<String>) { remaining = expected }
    func receive(_ changes: FileChanges) {
        lock.lock()
        defer { lock.unlock() }
        guard let paths = changes.changedPaths, !remaining.isEmpty else { return }
        remaining.subtract(paths)
        if remaining.isEmpty { ready.signal() }
    }
}


extension FileWatcherChecks {
    func narrowRootsAndInterests() throws {
        let fm = FileManager.default
        let home = ConfigRoots.physical(URL(fileURLWithPath: "/tmp/an06-roots-\(UUID().uuidString)"))
        defer { try? fm.removeItem(at: home) }
        let target = home.appendingPathComponent("external")
        for dir in [target.appendingPathComponent("projects"), target.appendingPathComponent("sessions")] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let claude = home.appendingPathComponent(".claude")
        try fm.createSymbolicLink(at: claude, withDestinationURL: target)
        let scanner = LogScanner(home: home, execRuns: { [] }, rolloutParents: { [:] })
        let plan = FileWatcher.plan(for: scanner.watchPaths, shallowPaths: scanner.watchRootPaths)
        XCTAssertTrue(plan.files.contains(target.appendingPathComponent("projects").path))
        XCTAssertTrue(plan.files.contains(target.appendingPathComponent("sessions").path))
        XCTAssertFalse(plan.files.contains(home.path))
        XCTAssertFalse(plan.files.contains(target.path))
        XCTAssertTrue(plan.directories.contains(home.path), "missing .codex and symlink entry need a directory-level parent watch")
        let watcher = FileWatcher(paths: scanner.watchPaths, shallowPaths: scanner.watchRootPaths) { _ in }
        XCTAssertTrue(watcher.accepts(target.path))
        XCTAssertTrue(watcher.accepts(target.appendingPathComponent("projects/p/a.jsonl").path))
        for unrelated in ["todos/a.json", "debug/a", "history.jsonl", "file-history/a"] {
            let path = target.appendingPathComponent(unrelated).path
            XCTAssertFalse(watcher.accepts(path))
            XCTAssertNil(watcher.eventChanges(paths: [path], flags: [UInt32(kFSEventStreamEventFlagMustScanSubDirs)]))
        }
        XCTAssertFalse(watcher.accepts(home.appendingPathComponent("Library/a").path))
        XCTAssertTrue(watcher.eventChanges(paths: [home.path + "/"], flags: [0]) != nil, "directory streams report folders with a trailing slash")
        let log = home.appendingPathComponent("stdout.jsonl").path
        let execWatcher = FileWatcher(paths: [log]) { _ in }
        XCTAssertTrue(execWatcher.accepts(log))
        XCTAssertFalse(execWatcher.accepts(home.appendingPathComponent("unrelated.jsonl").path))
    }

    func nextFinishedExpiry() throws {
        let home = URL(fileURLWithPath: "/tmp/an06-expiry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let log = home.appendingPathComponent(".claude/projects/p/done.jsonl")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-10))
        try "{\"type\":\"assistant\",\"timestamp\":\"\(stamp)\",\"message\":{\"stop_reason\":\"end_turn\",\"content\":[]}}\n".write(to: log, atomically: true, encoding: .utf8)
        let scanner = LogScanner(home: home, execRuns: { [] }, rolloutParents: { [:] })
        XCTAssertEqual(scanner.poll(now: now, finishedRetention: 20, changes: .full)!.first?.state, .done)
        let expiry = try XCTUnwrap(scanner.nextRetentionExpiry)
        XCTAssertTrue(expiry.timeIntervalSince(now) > 8 && expiry.timeIntervalSince(now) <= 10)
        XCTAssertEqual(scanner.poll(now: expiry, finishedRetention: 20, changes: .paths([]))!.count, 0)
        XCTAssertNil(scanner.nextRetentionExpiry)
    }
}
