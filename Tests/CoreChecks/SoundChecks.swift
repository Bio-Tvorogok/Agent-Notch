import Foundation

struct SoundChecks {
    func preferences() throws {
        var prefs = SoundPrefs(legacyName: "Ping")
        XCTAssertEqual(prefs[.permissionRequested], "Ping")
        XCTAssertTrue(SoundEvent.allCases.filter { $0 != .permissionRequested }.allSatisfy { prefs[$0].isEmpty })
        prefs[.agentFinished] = "Hero"
        prefs[.permissionRequested] = ""
        prefs.volume = 0.35
        let suite = "NOTCH-sounds-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsStorage.write(prefs, key: "soundEvents", in: defaults)
        let restored = SettingsStorage.read(SoundPrefs.self, key: "soundEvents", default: SoundPrefs(), in: defaults)
        XCTAssertEqual(restored[.agentFinished], "Hero")
        XCTAssertEqual(restored[.permissionRequested], "")
        XCTAssertEqual(restored.volume, 0.35)
        prefs[.agentError] = "missing-sound"
        XCTAssertEqual(prefs[.agentError], "")
    }

    func presets() throws {
        let expected: [(SoundPreset, [SoundEvent: String])] = [
            (.requestsOnly, [.permissionRequested: "Glass"]),
            (.attention, [.permissionRequested: "Glass", .questionAsked: "Glass", .planProposed: "Glass", .agentError: "Basso", .operationFailed: "Basso", .limitWarning: "Sosumi", .limitExhausted: "Basso"]),
            (.important, [.permissionRequested: "Glass", .questionAsked: "Glass", .planProposed: "Glass", .agentError: "Basso", .operationFailed: "Basso", .limitWarning: "Sosumi", .limitExhausted: "Basso", .agentFinished: "Hero", .limitRestored: "Ping"])
        ]
        for (preset, sounds) in expected {
            var prefs = SoundPrefs(legacyName: "Ping")
            prefs.volume = 0.35
            prefs[.cardOpened] = "Frog"
            prefs = preset.apply(to: prefs)
            for event in SoundEvent.allCases {
                XCTAssertEqual(prefs[event], sounds[event] ?? "", "wrong event in \(preset.rawValue): \(event.rawValue)")
            }
            XCTAssertEqual(prefs.volume, 0.35)
            XCTAssertEqual(SoundPreset.matching(prefs), preset)
            let restored = try JSONDecoder().decode(SoundPrefs.self, from: JSONEncoder().encode(prefs))
            XCTAssertEqual(SoundPreset.matching(restored), preset)
        }
        var all = SoundPreset.allEvents.apply(to: SoundPrefs())
        XCTAssertTrue(SoundEvent.allCases.allSatisfy { SoundPrefs.names.contains(all[$0]) })
        XCTAssertEqual(all[.denied], "Basso")
        XCTAssertEqual(all[.listOpened], "Tink")
        XCTAssertEqual(all[.agentFinished], "Hero")
        XCTAssertEqual(SoundPreset.matching(all), .allEvents)
        all[.cardOpened] = ""
        XCTAssertNil(SoundPreset.matching(all))
        XCTAssertEqual(SoundPreset.matching(SoundPrefs()), .requestsOnly)
        XCTAssertNil(SoundPreset.matching(SoundPrefs(legacyName: "Ping")))
    }

    func transitions() {
        var watcher = SoundAgentWatcher()
        var a = Agent(id: "a", vendor: .claude, title: "a", state: .working, project: "p")
        XCTAssertEqual(watcher.update([a]), []) // Existing agents are silent on launch.
        XCTAssertEqual(watcher.update([a]), [])
        a.state = .waiting
        XCTAssertEqual(watcher.update([a]), [.permissionRequested])
        XCTAssertEqual(watcher.update([a]), [])
        a.state = .working
        XCTAssertEqual(watcher.update([a]), [.agentResumed])
        a.state = .error
        XCTAssertEqual(watcher.update([a]), [.agentError])
        a.state = .done
        XCTAssertEqual(watcher.update([a]), [.agentFinished])
        XCTAssertEqual(watcher.update([a]), [])
        a.state = .working
        XCTAssertEqual(watcher.update([a]), [.agentStarted])
        let b = Agent(id: "b", vendor: .codex, title: "b", state: .working, project: "p")
        XCTAssertEqual(watcher.update([a, b]), [.agentAppeared])
    }

    func requests() {
        var watcher = SoundAgentWatcher()
        var a = Agent(id: "a", vendor: .claude, title: "a", state: .working, project: "p")
        _ = watcher.update([a])
        let permission = HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: "a", tool: "Bash", detail: "pwd")
        XCTAssertEqual(watcher.request(permission), .permissionRequested)
        var answeredBeforePoll = SoundAgentWatcher()
        _ = answeredBeforePoll.update([Agent(id: "a", vendor: .claude, title: "a", state: .working, project: "p")])
        _ = answeredBeforePoll.request(permission)
        answeredBeforePoll.resolve("a")
        let staleWaiting = Agent(id: "a", vendor: .claude, title: "a", state: .waiting, project: "p")
        XCTAssertEqual(answeredBeforePoll.update([staleWaiting]), []) // A stale log cannot reannounce an answered request.
        var native = SoundAgentWatcher()
        _ = native.update([a])
        _ = native.request(permission)
        native.resolve("a")
        _ = native.update([a])
        XCTAssertEqual(native.request(permission), .permissionRequested) // A new request passed to the native UI must re-arm it.
        let notice = HookEvent(vendor: .claude, name: "Notification", sessionId: "a", notificationType: "permission_prompt")
        XCTAssertNil(watcher.request(notice))
        a.state = .waiting
        XCTAssertEqual(watcher.update([a]), []) // Hook + polling must produce only one sound.
        watcher.resolve("a")
        XCTAssertEqual(watcher.request(permission), .permissionRequested)
        let question = HookEvent(vendor: .claude, name: "PreToolUse", sessionId: "q", tool: "AskUserQuestion",
                                 questions: [Question(question: "Which?", header: "Pick", options: [], multiSelect: false)], toolInput: "{}")
        XCTAssertEqual(watcher.request(question), .questionAsked)
        let plan = HookEvent(vendor: .claude, name: "PreToolUse", sessionId: "p", tool: "ExitPlanMode", plan: "A plan", toolInput: "{}")
        XCTAssertEqual(watcher.request(plan), .planProposed)
        var pollFirst = SoundAgentWatcher()
        var logAgent = Agent(id: "q", vendor: .claude, title: "q", state: .working, project: "p")
        _ = pollFirst.update([logAgent])
        logAgent.state = .waiting
        logAgent.ask = Loc.t("question", "вопрос")
        XCTAssertEqual(pollFirst.update([logAgent]), [.questionAsked])
        XCTAssertNil(pollFirst.request(question))
        logAgent.state = .working
        _ = pollFirst.update([logAgent])
        logAgent.state = .waiting
        logAgent.ask = Loc.t("approve plan", "согласовать план")
        XCTAssertEqual(pollFirst.update([logAgent]), [.planProposed])
    }

    func limits() {
        var watcher = SoundLimitWatcher()
        let now = Date(timeIntervalSince1970: 1_000)
        func sample(_ percent: Double) -> [VendorLimits] {
            [VendorLimits(vendor: .codex, windows: [LimitWindow(label: "5 ч", usedPercent: percent)], updatedAt: now)]
        }
        XCTAssertEqual(watcher.update(sample(60), threshold: 80), [])
        XCTAssertEqual(watcher.update(sample(80), threshold: 80), [.limitWarning])
        XCTAssertEqual(watcher.update(sample(82), threshold: 80), [])
        XCTAssertEqual(watcher.update(sample(100), threshold: 80), [.limitExhausted])
        XCTAssertEqual(watcher.update(sample(100), threshold: 80), [])
        XCTAssertEqual(watcher.update([], threshold: 80), []) // Missing samples aren't a reset.
        XCTAssertEqual(watcher.update(sample(0), threshold: 80), [.limitRestored])
        var startup = SoundLimitWatcher()
        XCTAssertEqual(startup.update(sample(100), threshold: 80), [])
    }

    func nativeRequests() {
        var watcher = SoundAgentWatcher()
        let a = Agent(id: "native", vendor: .claude, title: "native", state: .working, project: "p")
        _ = watcher.update([a])
        let first = HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: "native", tool: "Bash", detail: "pwd")
        let next = HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: "native", tool: "Bash", detail: "ls")
        XCTAssertEqual(watcher.request(first), .permissionRequested)
        _ = watcher.update([a]) // The first request was answered before a waiting poll.
        XCTAssertEqual(watcher.request(next), .permissionRequested)
        var numbered = SoundAgentWatcher()
        _ = numbered.update([a])
        XCTAssertEqual(numbered.request(first, ticket: 101), .permissionRequested)
        XCTAssertNil(numbered.request(first, ticket: 101))
        XCTAssertEqual(numbered.request(first, ticket: 102), .permissionRequested) // Same command, distinct requests.
        var pollCycle = SoundAgentWatcher()
        _ = pollCycle.update([a])
        _ = pollCycle.request(first, ticket: 201)
        var waiting = a
        waiting.state = .waiting
        _ = pollCycle.update([waiting])
        _ = pollCycle.update([a])
        XCTAssertEqual(pollCycle.update([waiting]), [.permissionRequested])
        XCTAssertNil(pollCycle.request(next, ticket: 202)) // The previous cycle's ticket cannot replay a poll-first request.
        var completed = SoundAgentWatcher()
        _ = completed.update([a])
        _ = completed.request(first)
        let unrelated = HookEvent(vendor: .claude, name: "PostToolUse", sessionId: "native", tool: "Read", detail: "file.txt")
        completed.finishedTool(unrelated)
        XCTAssertNil(completed.request(first))
        let matched = HookEvent(vendor: .claude, name: "PostToolUse", sessionId: "native", tool: "Bash", detail: "pwd")
        completed.finishedTool(matched)
        _ = completed.update([a])
        XCTAssertEqual(completed.request(first), .permissionRequested)
        let input = HookEvent(vendor: .claude, name: "Notification", sessionId: "native", notificationType: "agent_needs_input")
        var turns = SoundAgentWatcher()
        _ = turns.update([a])
        XCTAssertEqual(turns.request(input), .questionAsked)
        turns.resolve("native")
        XCTAssertNil(turns.request(input))
        turns.resume("native") // UserPromptSubmit is authoritative even before a waiting poll.
        XCTAssertEqual(turns.request(input), .questionAsked)
    }
}
