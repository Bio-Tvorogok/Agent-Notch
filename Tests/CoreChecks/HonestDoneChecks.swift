import Foundation

struct HonestDoneChecks {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/HonestDone")
    }

    func log(_ name: String, vendor: Vendor = .claude, parent: String? = nil) throws -> SessionLog {
        var s = SessionLog(id: name, vendor: vendor, parentId: parent)
        for line in try Data(contentsOf: fixtures.appendingPathComponent(name + ".jsonl")).split(separator: 10) {
            let r = try JSONSerialization.jsonObject(with: Data(line)) as! Rec
            if vendor == .claude { ClaudeLine.apply(r, to: &s, isSubagent: parent != nil) }
            else { CodexLine.apply(r, to: &s) }
        }
        return s
    }

    func silence() throws {
        let s = try log("silent")
        XCTAssertEqual(s.state(now: s.lastAt + 600), .working)
        XCTAssertNil(s.state(now: s.lastAt + 10_000), "stale silence may disappear, but never becomes done")
        var watcher = FinishWatcher()
        _ = watcher.update([s.agent(now: s.lastAt + 1, project: { _ in "p" })!], now: s.lastAt + 1)
        XCTAssertTrue(watcher.update([s.agent(now: s.lastAt + 600, project: { _ in "p" })!], now: s.lastAt + 600).isEmpty)
    }

    func interrupted() throws {
        var s = try log("silent")
        let now = s.lastAt + 10
        var w = FinishWatcher()
        _ = w.update([s.agent(now: now, project: { _ in "p" })!], now: now)
        s.live = ClaudeLive(status: "busy", waitingFor: nil, name: nil, alive: false)
        let a = s.agent(now: now + 1, project: { _ in "p" })!
        XCTAssertEqual(a.state, .done)
        XCTAssertEqual(a.activity, "прервано")
        XCTAssertTrue(w.update([a], now: now + 1).isEmpty)
        s.turnEnded = true
        XCTAssertEqual(w.update([s.agent(now: now + 2, project: { _ in "p" })!], now: now + 2).count, 0)
    }

    func helpers() throws {
        var parent = try log("background")
        parent.live = ClaudeLive(status: "waiting", waitingFor: "input needed", name: nil, alive: true)
        let now = parent.lastAt + 600
        let a = parent.agent(now: now, project: { _ in "p" })!
        var one = try log("silent", parent: a.id)
        one.id = "helper-one"
        var alive = one
        alive.live = ClaudeLive(status: "idle", waitingFor: nil, name: nil, alive: true)
        XCTAssertEqual(alive.state(now: now + 10_000), .working, "a live parent process keeps an unfinished helper alive")
        alive.turnEnded = true
        XCTAssertNil(alive.state(now: now + 10_000), "a helper's own end signal still wins over parent liveness")
        var two = one; two.id = "helper-two"
        let kids = [one, two].map { $0.agent(now: now, project: { _ in "p" })! }
        let row = Tree.build([a] + kids)[0].sessions[0]
        XCTAssertEqual(row.agent.state, .working)
        XCTAssertNil(row.agent.ask)
        XCTAssertEqual(row.agent.activity, "working · waiting for 2 helpers")
        var w = FinishWatcher()
        _ = w.update([a] + kids, now: now)
        var done = a; done.state = .done; done.ask = nil
        XCTAssertTrue(w.update([done] + kids, now: now + 1).isEmpty)
        var finishedKid = kids[0]; finishedKid.state = .done
        let remaining = Tree.build([a, finishedKid, kids[1]])[0].sessions[0].agent
        XCTAssertEqual(remaining.state, .working)
        XCTAssertEqual(remaining.activity, "working · waiting for 1 helper")
        parent.ask = "approve command"
        let asking = parent.agent(now: now, project: { _ in "p" })!
        XCTAssertEqual(Tree.build([asking] + kids)[0].sessions[0].agent.state, .waiting)
        var hooks = HookState()
        _ = hooks.receive(HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: a.id, tool: "Bash"), ticket: 7, now: now)
        XCTAssertEqual(hooks.receive(HookEvent(vendor: .claude, name: "SubagentStop", sessionId: a.id), ticket: nil, now: now + 1), [])
        XCTAssertEqual(hooks.pending.count, 1)
        XCTAssertEqual(hooks.receive(HookEvent(vendor: .claude, name: "SubagentStop", sessionId: a.id, agentId: "helper-one"), ticket: nil, now: now + 1), [])
        XCTAssertEqual(hooks.pending.count, 1)
        XCTAssertEqual(hooks.apply(to: [a] + kids, now: now + 2, project: { _ in "p" }).first?.state, .waiting)
    }

    func nestedHelpers() {
        let root = Agent(id: "root", vendor: .codex, title: "root", state: .done, project: "p")
        let child = Agent(id: "child", vendor: .codex, title: "child", state: .done, project: "p", parentId: "root")
        let leaf = Agent(id: "leaf", vendor: .codex, title: "leaf", state: .working, project: "p", parentId: "child")
        let once = Tree.withHelpers([root, child, leaf])
        XCTAssertEqual(once.first?.activity, "работает · ждёт 2 помощников")
        XCTAssertEqual(Tree.withHelpers(once), once)
    }

    func aborted() {
        for vendor in [Vendor.claude, .codex] {
            var s = SessionLog(id: "aborted", vendor: vendor)
            s.lastAt = 100
            var w = FinishWatcher()
            var sound = SoundAgentWatcher()
            let working = s.agent(now: 101, project: { _ in "p" })!
            _ = w.update([working], now: 101)
            _ = sound.update([working])
            if vendor == .codex {
                CodexLine.apply(["type": "event_msg", "payload": ["type": "turn_aborted"]], to: &s)
            } else {
                s.live = ClaudeLive(status: "busy", waitingFor: nil, name: nil, alive: false)
            }
            let ended = s.agent(now: 102, project: { _ in "p" })!
            XCTAssertEqual(ended.activity, "прервано")
            XCTAssertTrue(w.update([ended], now: 102).isEmpty)
            XCTAssertFalse(sound.update([ended]).contains(.agentFinished))
        }
    }

    func hookEnds() throws {
        let s = try log("silent")
        let now = s.lastAt + 10
        let a = s.agent(now: now, project: { _ in "p" })!
        var hooks = HookState()
        _ = hooks.receive(HookEvent(vendor: .claude, name: "Stop", sessionId: a.id, occurredAt: now), ticket: nil, now: now)
        XCTAssertEqual(hooks.apply(to: [a], now: now + 1, project: { _ in "p" }).first?.state, .done)
        var active = s
        ClaudeLine.apply(["type": "assistant", "timestamp": "2026-10-16T10:00:12Z",
                          "message": ["content": [["type": "text", "text": "new activity"]]]], to: &active, isSubagent: false)
        let fresh = active.agent(now: now + 3, project: { _ in "p" })!
        XCTAssertEqual(hooks.apply(to: [fresh], now: now + 3, project: { _ in "p" }).first?.state, .working)
        _ = hooks.receive(HookEvent(vendor: .claude, name: "UserPromptSubmit", sessionId: a.id), ticket: nil, now: now + 2)
        XCTAssertEqual(hooks.apply(to: [a], now: now + 3, project: { _ in "p" }).first?.state, .working)
        _ = hooks.receive(HookEvent(vendor: .claude, name: "SessionEnd", sessionId: a.id), ticket: nil, now: now + 4)
        XCTAssertEqual(hooks.apply(to: [a], now: now + 5, project: { _ in "p" }).first?.activity, "прервано")
        _ = hooks.receive(HookEvent(vendor: .claude, name: "SessionEnd", sessionId: a.id), ticket: nil, now: now + 6)
        XCTAssertEqual(hooks.apply(to: [a], now: now + 7, project: { _ in "p" }).first?.activity, "прервано")
        var aborted = a; aborted.turnEnded = true; aborted.interrupted = true
        XCTAssertEqual(hooks.apply(to: [aborted], now: now + 7, project: { _ in "p" }).first?.activity, "прервано")
    }

    func retainedFailedExec() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("honest-exec-" + UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let now = Date()
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let day = home.appendingPathComponent(String(format: ".codex/sessions/%04d/%02d/%02d", parts.year!, parts.month!, parts.day!))
        try fm.createDirectory(at: day, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: now)
        func write(_ rows: [Rec], _ url: URL) throws {
            var data = Data()
            for row in rows { data += try JSONSerialization.data(withJSONObject: row); data.append(10) }
            try data.write(to: url)
        }
        try write([["type": "session_meta", "timestamp": stamp, "payload": ["id": "failed"]],
                   ["type": "event_msg", "timestamp": stamp, "payload": ["type": "task_started"]]], day.appendingPathComponent("rollout-failed.jsonl"))
        let stream = home.appendingPathComponent("stream.jsonl")
        try write([["type": "thread.started", "thread_id": "failed"], ["type": "turn.started"]], stream)
        let run = ExecRun(pid: 7, log: stream.path, cwd: nil, model: nil, effort: nil)
        let scanner = LogScanner(home: home, execRuns: { [run] }, rolloutParents: { [:] })
        var watcher = FinishWatcher()
        _ = watcher.update(scanner.poll(now: now)!, now: now.timeIntervalSince1970)
        try write([["type": "thread.started", "thread_id": "failed"], ["type": "turn.started"], ["type": "turn.failed"]], stream)
        let ended = scanner.poll(now: now.addingTimeInterval(6))!
        XCTAssertEqual(ended.first?.activity, "прервано")
        XCTAssertTrue(watcher.update(ended, now: now.timeIntervalSince1970 + 6).isEmpty)
    }

    func retainedParent() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("honest-parent-" + UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let base = home.appendingPathComponent(".claude/projects/fixture")
        let kids = base.appendingPathComponent("background/subagents")
        try fm.createDirectory(at: kids, withIntermediateDirectories: true)
        try Data(contentsOf: fixtures.appendingPathComponent("background.jsonl")).write(to: base.appendingPathComponent("background.jsonl"))
        try Data(contentsOf: fixtures.appendingPathComponent("silent.jsonl")).write(to: kids.appendingPathComponent("agent-child.jsonl"))
        let now = Date(timeIntervalSince1970: LogText.time("2026-10-16T10:10:00Z")!)
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: kids.appendingPathComponent("agent-child.jsonl").path)
        // The parent log is outside the discovery window, but its helper is still alive.
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-3700)], ofItemAtPath: base.appendingPathComponent("background.jsonl").path)
        let agents = LogScanner(home: home, execRuns: { [] }, rolloutParents: { [:] }).poll(now: now, finishedRetention: 60)!
        XCTAssertEqual(agents.count, 2)
        let parent = try XCTUnwrap(agents.first { $0.id == "background" })
        XCTAssertEqual(parent.state, .working)
        XCTAssertEqual(parent.activity, "работает · ждёт 1 помощника")
    }

    func coldCodexParent() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("honest-cold-codex-" + UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let now = Date()
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let day = home.appendingPathComponent(String(format: ".codex/sessions/%04d/%02d/%02d", parts.year!, parts.month!, parts.day!))
        try fm.createDirectory(at: day, withIntermediateDirectories: true)
        func write(_ rows: [Rec], _ url: URL, at: Date) throws {
            var data = Data()
            for row in rows { data += try JSONSerialization.data(withJSONObject: row); data.append(10) }
            try data.write(to: url)
            try fm.setAttributes([.modificationDate: at], ofItemAtPath: url.path)
        }
        let old = now.addingTimeInterval(-3700)
        let stamp = ISO8601DateFormatter().string(from: now)
        let oldStamp = ISO8601DateFormatter().string(from: old)
        try write([["type": "session_meta", "timestamp": oldStamp, "payload": ["id": "parent"]],
                   ["type": "event_msg", "timestamp": oldStamp, "payload": ["type": "task_complete"]]],
                  day.appendingPathComponent("rollout-parent.jsonl"), at: old)
        try write([["type": "session_meta", "timestamp": stamp, "payload": ["id": "child", "source": ["subagent": ["thread_spawn": ["parent_thread_id": "parent"]]]]],
                   ["type": "event_msg", "timestamp": stamp, "payload": ["type": "task_started"]]],
                  day.appendingPathComponent("rollout-child.jsonl"), at: now)
        let agents = LogScanner(home: home, execRuns: { [] }, rolloutParents: { [:] }).poll(now: now, finishedRetention: 60)!
        XCTAssertEqual(agents.count, 2)
        XCTAssertEqual(agents.first { $0.id == "parent" }?.state, .working)
        XCTAssertEqual(agents.first { $0.id == "parent" }?.activity, "работает · ждёт 1 помощника")
    }

    func hookRetention() {
        var hooks = HookState()
        let a = Agent(id: "stopped", vendor: .claude, title: "stopped", state: .working, project: "p")
        _ = hooks.receive(HookEvent(vendor: .claude, name: "Stop", sessionId: a.id, occurredAt: 1), ticket: nil, now: 1)
        XCTAssertEqual(hooks.apply(to: [a], now: 2, project: { _ in "p" }).first?.state, .done)
        XCTAssertTrue(hooks.apply(to: [a], now: 3602, project: { _ in "p" }).isEmpty)
    }

    func helperHookCount() {
        let parent = Agent(id: "root", vendor: .claude, title: "root", state: .done, project: "p")
        let child = Agent(id: "root/child", vendor: .claude, title: "child", state: .working, project: "p", parentId: "root")
        let normalized = Tree.withHelpers([parent, child])
        var hooks = HookState()
        _ = hooks.receive(HookEvent(vendor: .claude, name: "SubagentStop", sessionId: "root", agentId: "child"), ticket: nil, now: 1)
        let after = hooks.apply(to: normalized, now: 2, project: { _ in "p" })
        XCTAssertEqual(after.first?.state, .working, "child completion alone cannot finish its parent")
        XCTAssertNil(after.first?.activity, "a finished helper is no longer counted")
        XCTAssertEqual(after.last?.state, .done)
        var interrupted = normalized[0]; interrupted.interrupted = true
        let stopped = hooks.apply(to: [interrupted, child], now: 2, project: { _ in "p" })
        XCTAssertEqual(stopped.first?.activity, "прервано")
        XCTAssertEqual(stopped.first?.helperCount, 0)
    }

    func toast() throws {
        let forced = Loc.forced
        defer { Loc.forced = forced }
        let git = Process(), output = Pipe()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["rev-parse", "--short", "HEAD"]
        git.standardOutput = output
        try git.run()
        let head = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        git.waitUntilExit()
        XCTAssertEqual(git.terminationStatus, 0)
        XCTAssertTrue(!head.hasPrefix("a1b2c3d"), "the fixture's session commit differs from this repository's HEAD")
        for vendor in [Vendor.claude, .codex] {
            let path = fixtures.appendingPathComponent("toast-\(vendor.rawValue).jsonl").path
            var detail = try XCTUnwrap(DetailReader.read(path: path, vendor: vendor))
            detail.meta.cwd = FileManager.default.currentDirectoryPath
            Loc.forced = .en
            XCTAssertEqual(FinishSummary.line(detail), "done · 2 of 7 left · commit a1b2c3d")
            Loc.forced = .ru
            XCTAssertEqual(FinishSummary.line(detail), "готово · осталось 2 из 7 · коммит a1b2c3d")
        }
    }
}
