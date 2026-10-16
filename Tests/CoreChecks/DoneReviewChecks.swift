import Foundation

struct DoneReviewChecks {
    private func write(_ rows: [Rec], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data()
        for row in rows { data += try JSONSerialization.data(withJSONObject: row); data.append(10) }
        try data.write(to: file)
    }

    private func assistant(_ text: String, at: String) -> Rec {
        ["type": "assistant", "timestamp": at,
         "message": ["content": [["type": "text", "text": text]]]]
    }

    func stopSurvivesExit() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("stop-exit-" + UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        try write([assistant("finished", at: "1970-01-01T00:01:40Z")], to: file)
        var log = SessionLog(id: "exit", vendor: .claude)
        log.lastAt = 100
        let working = log.agent(now: 101, project: { _ in "p" })!
        var watcher = FinishWatcher(), sound = SoundAgentWatcher()
        _ = watcher.update([working], now: 101)
        _ = sound.update([working])
        var hooks = HookState()
        let stop = try XCTUnwrap(HookEvent(vendor: .claude, payload: ["session_id": log.id, "hook_event_name": "Stop",
            "transcript_path": file.path, "last_assistant_message": "finished"]))
        _ = hooks.receive(stop, ticket: nil, now: 102)
        log.live = ClaudeLive(status: "busy", waitingFor: nil, name: nil, alive: false)
        let exited = log.agent(now: 103, project: { _ in "p" })!
        XCTAssertTrue(exited.interrupted)
        let completed = hooks.apply(to: [exited], now: 103, project: { _ in "p" })
        XCTAssertEqual(completed.first?.turnEnded, true)
        XCTAssertEqual(completed.first?.interrupted, false)
        XCTAssertEqual(watcher.update(completed, now: 103).count, 1)
        XCTAssertTrue(sound.update(completed).contains(.agentFinished))
        log.interrupted = true
        let aborted = hooks.apply(to: [log.agent(now: 103, project: { _ in "p" })!], now: 103, project: { _ in "p" })
        XCTAssertEqual(aborted.first?.interrupted, true, "an explicit abort still wins")
    }

    func lastHelperRestoresParent() {
        var parent = Agent(id: "root", vendor: .claude, title: "root", state: .done, project: "p")
        parent.turnEnded = true
        let child = Agent(id: "root/child", vendor: .claude, title: "child", state: .working, project: "p", parentId: "root")
        let promoted = Tree.withHelpers([parent, child])
        var watcher = FinishWatcher()
        _ = watcher.update(promoted, now: 1)
        var hooks = HookState()
        _ = hooks.receive(HookEvent(vendor: .claude, name: "SubagentStop", sessionId: "root", agentId: "child"), ticket: nil, now: 2)
        let completed = hooks.apply(to: promoted, now: 2, project: { _ in "p" })
        XCTAssertEqual(completed.first?.state, .done)
        XCTAssertEqual(completed.first?.helperCount, 0)
        XCTAssertEqual(watcher.update(completed, now: 2).map(\.agent.id), ["root"])
        XCTAssertEqual(Tree.withHelpers(completed), completed)
    }

    func parentRetainedAfterHelper() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("done-review-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let base = home.appendingPathComponent(".claude/projects/fixture")
        let parent = base.appendingPathComponent("root.jsonl")
        let child = base.appendingPathComponent("root/subagents/agent-child.jsonl")
        let now = LogText.time("2026-10-16T10:10:00Z")!
        try write([["type": "assistant", "timestamp": "2026-10-16T10:00:00Z",
                    "message": ["stop_reason": "end_turn"]]], to: parent)
        try write([assistant("working", at: "2026-10-16T10:09:59Z")], to: child)
        for file in [parent, child] {
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: now)], ofItemAtPath: file.path)
        }
        let scanner = LogScanner(home: home, execRuns: { [] }, rolloutParents: { [:] })
        var watcher = FinishWatcher()
        let working = scanner.poll(now: Date(timeIntervalSince1970: now), finishedRetention: 60)!
        XCTAssertEqual(working.first { $0.id == "root" }?.state, .working)
        _ = watcher.update(working, now: now)
        let handle = try FileHandle(forWritingTo: child)
        try handle.seekToEnd()
        var row = assistant("finished", at: "2026-10-16T10:10:01Z")
        row["message"] = ["stop_reason": "end_turn"]
        try handle.write(contentsOf: JSONSerialization.data(withJSONObject: row) + [10])
        try handle.close()
        let completed = scanner.poll(now: Date(timeIntervalSince1970: now + 1), finishedRetention: 60)!
        XCTAssertEqual(completed.first { $0.id == "root" }?.state, .done)
        XCTAssertEqual(watcher.update(completed, now: now + 1).map(\.agent.id), ["root"])
        XCTAssertEqual(scanner.poll(now: Date(timeIntervalSince1970: now + 59), finishedRetention: 60)!.first { $0.id == "root" }?.state, .done)
        XCTAssertFalse(scanner.poll(now: Date(timeIntervalSince1970: now + 62), finishedRetention: 60)!.contains { $0.id == "root" })
    }

    func delayedStopDoesNotFinishNextTurn() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("stop-review-" + UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let old = assistant("first answer", at: "2026-10-16T10:00:00Z")
        let prompt: Rec = ["type": "user", "timestamp": "2026-10-16T10:01:00Z", "message": ["content": "next prompt"]]
        let next = assistant("still working", at: "2026-10-16T10:01:01Z")
        try write([old, prompt, next], to: file)
        var log = SessionLog(id: "delayed", vendor: .claude)
        for row in [old, prompt, next] { ClaudeLine.apply(row, to: &log, isSubagent: false) }
        let now = log.lastAt + 1
        let working = log.agent(now: now, project: { _ in "p" })!
        var hooks = HookState(), watcher = FinishWatcher()
        _ = watcher.update([working], now: now)
        _ = hooks.receive(HookEvent(vendor: .claude, name: "UserPromptSubmit", sessionId: log.id), ticket: nil, now: now - 1)
        func stop(_ text: String) throws -> HookEvent {
            try XCTUnwrap(HookEvent(vendor: .claude, payload: ["hook_event_name": "Stop", "session_id": log.id,
                "transcript_path": file.path, "last_assistant_message": text]))
        }
        _ = hooks.receive(try stop("first answer"), ticket: nil, now: now + 1)
        let afterStale = hooks.apply(to: [working], now: now + 1, project: { _ in "p" })
        XCTAssertEqual(afterStale.first?.state, .working)
        XCTAssertTrue(watcher.update(afterStale, now: now + 1).isEmpty)
        _ = hooks.receive(try stop("still working"), ticket: nil, now: now + 2)
        let completed = hooks.apply(to: [working], now: now + 2, project: { _ in "p" })
        XCTAssertEqual(completed.first?.state, .done)
        XCTAssertEqual(watcher.update(completed, now: now + 2).count, 1)

        // Log activity alone rejects an earlier Stop, even if this app missed the prompt hook.
        var lateHooks = HookState()
        _ = lateHooks.receive(try stop("first answer"), ticket: nil, now: now + 3)
        XCTAssertEqual(lateHooks.apply(to: [working], now: now + 3, project: { _ in "p" }).first?.state, .working)

        // A delayed prompt hook can still be ordered before the real Stop by transcript time.
        var delayedPrompt = HookState()
        let promptEvent = try XCTUnwrap(HookEvent(vendor: .claude, payload: ["session_id": log.id,
            "hook_event_name": "UserPromptSubmit", "transcript_path": file.path, "prompt": "next prompt"]))
        _ = delayedPrompt.receive(promptEvent, ticket: nil, now: now + 4)
        _ = delayedPrompt.receive(try stop("still working"), ticket: nil, now: now + 5)
        XCTAssertEqual(delayedPrompt.apply(to: [working], now: now + 5, project: { _ in "p" }).first?.state, .done)

        // Tool hooks must not erase the newer prompt's ordering evidence, even during scanner lag.
        var tools = HookState()
        _ = tools.receive(promptEvent, ticket: nil, now: now)
        for name in ["PreToolUse", "PostToolUse"] {
            _ = tools.receive(HookEvent(vendor: .claude, name: name, sessionId: log.id), ticket: nil, now: now + 1)
        }
        var lagging = SessionLog(id: log.id, vendor: .claude)
        ClaudeLine.apply(old, to: &lagging, isSubagent: false)
        let oldSnapshot = lagging.agent(now: now, project: { _ in "p" })!
        _ = tools.receive(try stop("first answer"), ticket: nil, now: now + 2)
        XCTAssertEqual(tools.apply(to: [oldSnapshot], now: now + 2, project: { _ in "p" }).first?.state, .working)

        // A missed prompt hook does not let an old Stop dismiss a newer approval or shown prompt.
        var approval = HookState()
        let request = HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: log.id, tool: "Bash", toolUseID: "new-tool")
        _ = approval.receive(request, ticket: 7, now: now)
        XCTAssertEqual(approval.receive(try stop("first answer"), ticket: nil, now: now + 1), [])
        XCTAssertEqual(approval.pending.count, 1)
        XCTAssertEqual(approval.apply(to: [working], now: now + 1, project: { _ in "p" }).first?.state, .waiting)
        var shown = HookState()
        _ = shown.receive(HookEvent(vendor: .claude, name: "Notification", sessionId: log.id,
                                   notificationType: "permission_prompt"), ticket: nil, now: now)
        _ = shown.receive(try stop("first answer"), ticket: nil, now: now + 1)
        XCTAssertEqual(shown.apply(to: [working], now: now + 1, project: { _ in "p" }).first?.state, .waiting)

        // Missing or ambiguous source evidence cannot complete the active turn.
        for event in [HookEvent(vendor: .claude, name: "Stop", sessionId: log.id), try stop("not in transcript")] {
            var unknown = HookState()
            _ = unknown.receive(event, ticket: nil, now: now + 6)
            XCTAssertEqual(unknown.apply(to: [working], now: now + 6, project: { _ in "p" }).first?.state, .working)
        }
        try write([old, prompt, assistant("first answer", at: "2026-10-16T10:01:01Z")], to: file)
        var ambiguous = HookState()
        _ = ambiguous.receive(try stop("first answer"), ticket: nil, now: now + 7)
        XCTAssertEqual(ambiguous.apply(to: [working], now: now + 7, project: { _ in "p" }).first?.state, .working)
    }
}
