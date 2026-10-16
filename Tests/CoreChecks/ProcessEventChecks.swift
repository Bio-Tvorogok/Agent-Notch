import Foundation

struct ProcessEventChecks {
    func coalescesChurnWithTrailingRefresh() {
        var gate = ProcessRefreshGate()
        var deadline = gate.request(now: 0)
        XCTAssertEqual(deadline, 0.1)
        var refreshes: [Double] = []
        for step in 1...60 {
            let now = Double(step) / 10
            if let due = deadline, now >= due {
                gate.refreshed(at: now)
                refreshes.append(now)
                deadline = nil
            }
            if let due = gate.request(now: now) { deadline = due }
        }
        if let due = deadline { gate.refreshed(at: due); refreshes.append(due) }
        XCTAssertTrue(refreshes.count <= 5, "10Hz churn must not produce 10Hz process scans")
        XCTAssertTrue(zip(refreshes, refreshes.dropFirst()).allSatisfy { $1 - $0 >= 1.5 - 0.000001 })
        XCTAssertTrue((refreshes.last ?? 0) > 6, "the final event gets a trailing refresh")
    }

    func cachesArgumentsUntilExitReuseOrExec() {
        let cache = ProcessArgumentsCache()
        let first = ProcessStart(seconds: 1, microseconds: 2)
        let reused = ProcessStart(seconds: 1, microseconds: 3)
        var reads = 0
        func read() -> ([String], [String]) { reads += 1; return (["node"], ["PARENT=\(reads)"]) }
        XCTAssertEqual(cache.value(pid: 42, start: first, read: read).1, ["PARENT=1"])
        for _ in 0..<50 { _ = cache.value(pid: 42, start: first, read: read) }
        XCTAssertEqual(reads, 1, "existing node processes must not reread KERN_PROCARGS2")
        XCTAssertEqual(cache.value(pid: 42, start: reused, read: read).1, ["PARENT=2"])
        cache.retain(pids: [])
        _ = cache.value(pid: 42, start: reused, read: read)
        XCTAssertEqual(reads, 3, "exit evicts the pid")
        cache.invalidate(42)
        _ = cache.value(pid: 42, start: reused, read: read)
        XCTAssertEqual(reads, 4, "exec invalidates arguments even with the same start time")
    }
}
