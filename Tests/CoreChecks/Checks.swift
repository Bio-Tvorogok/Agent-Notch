import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

struct LogTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func stamp(_ secondsAgo: Double) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: now.addingTimeInterval(-secondsAgo))
    }

    func write(_ url: URL, _ lines: [String]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
    }

    /// A fake home: a Claude session with a subagent in a worktree, a Codex thread waiting for approval, its subagent, an old log.
    func home() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("notch-\(UUID().uuidString)")
        let repo = home.appendingPathComponent("Projects/wedding-app")
        let tree = home.appendingPathComponent("tmp/wt-fix")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git/worktrees/wt-fix"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        try "gitdir: \(repo.path)/.git/worktrees/wt-fix\n".write(to: tree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        let proj = home.appendingPathComponent(".claude/projects/-tmp-wt-fix")
        let main = "11111111-1111-1111-1111-111111111111"
        try write(proj.appendingPathComponent("\(main).jsonl"), [
            #"{"type":"user","cwd":"\#(tree.path)","gitBranch":"fix/upload","timestamp":"\#(stamp(60))","message":{"content":"сожми видео"}}"#,
            #"{"type":"assistant","cwd":"\#(tree.path)","effort":"high","timestamp":"\#(stamp(50))","message":{"model":"claude-opus-4-7","stop_reason":"tool_use","content":[{"type":"tool_use","id":"t1","name":"Agent"}]}}"#,
        ])
        let sub = proj.appendingPathComponent("\(main)/subagents/agent-abc.jsonl")
        try write(sub, [
            #"{"type":"assistant","isSidechain":true,"cwd":"\#(tree.path)","timestamp":"\#(stamp(20))","message":{"model":"claude-haiku-4-5","content":[{"type":"tool_use","id":"b1","name":"Bash"}]}}"#,
            #"{"type":"user","isSidechain":true,"timestamp":"\#(stamp(15))","message":{"content":[{"type":"tool_result","tool_use_id":"b1","is_error":true}]}}"#,
        ])
        try #"{"agentType":"Explore","description":"найти роуты загрузки"}"#.write(
            to: sub.deletingPathExtension().appendingPathExtension("meta.json"), atomically: true, encoding: .utf8)

        let c = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let day = home.appendingPathComponent(String(format: ".codex/sessions/%04d/%02d/%02d", c.year!, c.month!, c.day!))
        try write(day.appendingPathComponent("rollout-a.jsonl"), [
            #"{"type":"session_meta","timestamp":"\#(stamp(200))","payload":{"id":"cx-1","cwd":"\#(repo.path)","source":"cli","git":{"branch":"CONF-360"}}}"#,
            #"{"type":"turn_context","timestamp":"\#(stamp(190))","payload":{"model":"gpt-6.1-sol","effort":"medium"}}"#,
            #"{"type":"event_msg","timestamp":"\#(stamp(30))","payload":{"type":"exec_approval_request","command":["bash","-lc","rm -rf dist"]}}"#,
            #"{"type":"event_msg","timestamp":"\#(stamp(29))","payload":{"type":"token_count"}}"#,
        ])
        try write(day.appendingPathComponent("rollout-b.jsonl"), [
            #"{"type":"session_meta","timestamp":"\#(stamp(100))","payload":{"id":"cx-2","cwd":"\#(repo.path)","source":{"subagent":{"thread_spawn":{"parent_thread_id":"cx-1","agent_path":"root/fix_lint"}}}}}"#,
            #"{"type":"event_msg","timestamp":"\#(stamp(10))","payload":{"type":"task_complete"}}"#,
        ])
        let old = day.appendingPathComponent("rollout-old.jsonl")
        try write(old, [#"{"type":"session_meta","timestamp":"\#(stamp(9000))","payload":{"id":"cx-old","cwd":"/x"}}"#])
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-9000)], ofItemAtPath: old.path)
        return home
    }

    func testScannerReadsBothVendorsIntoOneProject() throws {
        let agents = LogScanner(home: try home(), execRuns: { [] }).poll(now: now)!
        let byId = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        XCTAssertEqual(agents.count, 4, "old log is skipped")
        let main = try XCTUnwrap(byId["11111111-1111-1111-1111-111111111111"])
        XCTAssertEqual(main.state, .working)
        XCTAssertEqual(main.project, "wedding-app", "worktree resolves to its repo")
        XCTAssertEqual(main.title, "fix/upload")
        XCTAssertEqual(main.shortModel, "opus")
        XCTAssertEqual(main.effort, .high)

        let sub = try XCTUnwrap(byId["11111111-1111-1111-1111-111111111111/abc"])
        XCTAssertEqual(sub.parentId, main.id)
        XCTAssertEqual(sub.chatId, main.id)
        XCTAssertEqual(sub.title, "найти роуты загрузки")
        XCTAssertTrue(sub.isLight)

        let cx = try XCTUnwrap(byId["cx-1"])
        XCTAssertEqual(cx.state, .waiting)
        XCTAssertEqual(cx.ask, "rm -rf dist")
        XCTAssertEqual(cx.title, "CONF-360")
        XCTAssertEqual(cx.effort, .medium)
        XCTAssertEqual(cx.project, "wedding-app")

        let cxSub = try XCTUnwrap(byId["cx-2"])
        XCTAssertEqual(cxSub.parentId, "cx-1")
        XCTAssertEqual(cxSub.title, "fix lint")
        XCTAssertEqual(cxSub.state, .done)

        let tree = Tree.build(agents)
        XCTAssertEqual(tree.map(\.name), ["wedding-app"])
        XCTAssertEqual(tree[0].sessions.map(\.id), ["cx-1", main.id])
    }

    /// ~/.claude/sessions/<pid>.json beats silence in the log: waiting, idle, or the process gone.
    func testClaudeProcessStatusWins() throws {
        let home = try home()
        let main = "11111111-1111-1111-1111-111111111111"
        let dir = home.appendingPathComponent(".claude/sessions")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func status(_ s: String, pid: Int32 = getpid(), extra: String = "") throws {
            try #"{"pid":\#(pid),"sessionId":"\#(main)","status":"\#(s)","name":"Сжатие видео"\#(extra)}"#
                .write(to: dir.appendingPathComponent("1.json"), atomically: true, encoding: .utf8)
        }
        let scanner = LogScanner(home: home, execRuns: { [] })
        func agent(_ id: String = main) -> Agent? { scanner.poll(now: now)!.first { $0.id == id } }

        try status("waiting", extra: #","waitingFor":"dialog open""#)
        XCTAssertEqual(agent()?.state, .waiting)
        XCTAssertEqual(agent()?.ask, "подтверждение в окне Claude")
        XCTAssertEqual(agent()?.title, "Сжатие видео")
        try status("idle")
        XCTAssertEqual(agent()?.state, .working, "a live helper keeps the parent working")
        try status("busy")
        XCTAssertEqual(agent()?.state, .working)
        // The process is gone: the session and its subagent are done, whatever the log says.
        try status("busy", pid: 99_999_999)
        XCTAssertEqual(agent()?.state, .done)
        XCTAssertEqual(agent("\(main)/abc")?.state, .done)
    }

    func testStateRules() {
        let t = 10_000.0
        var s = SessionLog(id: "a", vendor: .claude)
        s.lastAt = t - 10
        XCTAssertEqual(s.state(now: t), .working)
        s.errorStreak = 3
        XCTAssertEqual(s.state(now: t), .error)
        s.turnEnded = true
        XCTAssertEqual(s.state(now: t), .done)
        s.lastAt = t - SessionLog.keepDone - 1
        XCTAssertNil(s.state(now: t))
        s.turnEnded = false
        s.errorStreak = 0
        s.lastAt = t - 600
        XCTAssertEqual(s.state(now: t), .working, "silence is not an end-of-turn signal")
        s.ask = "вопрос"
        XCTAssertEqual(s.state(now: t), .waiting)
    }

    func testSubagentHandbackEndsTheSubagent() throws {
        var s = SessionLog(id: "a/b", vendor: .claude, parentId: "a")
        let call = try JSONSerialization.jsonObject(with: Data(#"{"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","id":"h","name":"SubagentHandback","input":{}}]}}"#.utf8)) as! [String: Any]
        let delivered = try JSONSerialization.jsonObject(with: Data(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"h","content":[{"type":"text","text":"ok"}]}]}}"#.utf8)) as! [String: Any]
        ClaudeLine.apply(call, to: &s, isSubagent: true)
        ClaudeLine.apply(delivered, to: &s, isSubagent: true)
        s.lastAt = 10_000 - 5
        XCTAssertEqual(s.state(now: 10_000), .done, "a subagent that handed its report back is finished")
        XCTAssertNil(s.activity)
    }

    func testClaudeQuestionWaitsUntilAnswered() throws {
        var s = SessionLog(id: "a", vendor: .claude)
        let ask = try JSONSerialization.jsonObject(with: Data(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"q","name":"AskUserQuestion"}]}}"#.utf8)) as! [String: Any]
        let answer = try JSONSerialization.jsonObject(with: Data(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"q"}]}}"#.utf8)) as! [String: Any]
        ClaudeLine.apply(ask, to: &s, isSubagent: false)
        XCTAssertEqual(s.ask, "вопрос")
        ClaudeLine.apply(answer, to: &s, isSubagent: false)
        XCTAssertNil(s.ask)
    }
}

struct TreeTests {
    func testNestsGrandchildrenUnderTheRootAndOrphansBecomeRoots() {
        let agents = [
            Agent(id: "r", vendor: .claude, title: "root", state: .working, project: "p"),
            Agent(id: "k", vendor: .claude, title: "kid", state: .working, project: "p", parentId: "r"),
            Agent(id: "g", vendor: .codex, title: "grandkid", state: .waiting, project: "p", parentId: "k"),
            Agent(id: "o", vendor: .codex, title: "orphan", state: .working, project: "p", parentId: "gone"),
        ]
        let p = Tree.build(agents)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].sessions.map(\.id), ["r", "o"])
        XCTAssertEqual(p[0].sessions[0].kids.map(\.id), ["g", "k"], "waiting kid sorts first")
        XCTAssertEqual(p[0].worst, .waiting)
    }

    func testProjectsWithOnlyFinishedAgentsAreDropped() {
        let p = Tree.build([Agent(id: "a", vendor: .claude, title: "a", state: .done, project: "old"),
                            Agent(id: "b", vendor: .claude, title: "b", state: .working, project: "new")])
        XCTAssertEqual(p.map(\.name), ["new"])
    }

    func testProjectWithAttentionSortsFirst() {
        let p = Tree.build(Fixtures.agents("projects")!)
        XCTAssertEqual(p.map(\.name), ["hexhaven", "wedding-app", "agents-village"])
    }
}

struct WingTests {
    func testSmallProjectDrawsEveryLiveAgent() {
        let l = Wing.layout(Tree.build(Fixtures.agents("multi")!), cramped: false)
        XCTAssertFalse(l.collapsed)
        guard case let .detailed(letter, sessions) = l.groups.first else { return XCTFail("\(l)") }
        XCTAssertNil(letter, "one project needs no letter")
        XCTAssertEqual(sessions.map(\.count), [1, 3, 1], "finished subagent is not drawn")
        XCTAssertEqual(sessions[0][0].state, .waiting)
    }

    func testBusyProjectSwitchesToCountersAndKeepsExceptions() {
        let l = Wing.layout(Tree.build(Fixtures.agents("heavy")!), cramped: false, maxWidth: 400)
        XCTAssertEqual(l.groups.count, 3)
        guard case let .counters(letter, claude, codex, exceptions) = l.groups[1] else { return XCTFail("\(l.groups)") }
        XCTAssertEqual(letter, "w")
        XCTAssertEqual(claude, 6)
        XCTAssertEqual(codex, 7)
        XCTAssertEqual(exceptions.map(\.state), [.error, .waiting])
    }

    func testCrampedOrTooWideCollapsesIntoOneSummary() {
        let projects = Tree.build(Fixtures.agents("heavy")!)
        for l in [Wing.layout(projects, cramped: true), Wing.layout(projects, cramped: false, maxWidth: 40)] {
            XCTAssertTrue(l.collapsed)
            guard case let .counters(letter, claude, codex, exceptions) = l.groups.first, l.groups.count == 1
            else { return XCTFail("\(l.groups)") }
            XCTAssertNil(letter)
            XCTAssertEqual(claude + codex, 14)
            XCTAssertEqual(exceptions.count, 3)
        }
    }

    func testNothingLiveDrawsNothing() {
        let l = Wing.layout(Tree.build([Agent(id: "a", vendor: .claude, title: "a", state: .done, project: "p")]), cramped: false)
        XCTAssertEqual(l.groups, [])
    }
}
