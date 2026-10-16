import Foundation

struct SettingsChecks {
    func ordering() {
        let parts = [DisplayPart(RowPart.project, enabled: false), DisplayPart(.title), DisplayPart(.project)]
        let normalized = DisplayOrder.normalize(parts)
        XCTAssertEqual(normalized.prefix(2).map(\.part), [.project, .title])
        XCTAssertEqual(normalized.count, RowPart.allCases.count)
        XCTAssertFalse(normalized[0].enabled)
        XCTAssertFalse(DisplayOrder.visible(normalized).contains(.project))
        XCTAssertEqual(DisplayOrder.move(normalized, from: 0, to: 2)[2].part, .project)
        XCTAssertEqual(DisplayOrder.move(normalized, from: -1, to: 2), normalized)
    }

    func roundTrip() throws {
        let parts = [DisplayPart(CardBlock.log, enabled: false), DisplayPart(.files)]
        let data = try JSONEncoder().encode(parts)
        XCTAssertEqual(try JSONDecoder().decode([DisplayPart<CardBlock>].self, from: data), parts)
    }

    func limits() {
        XCTAssertTrue(LimitChipMode.always.isVisible(usedPercent: nil, threshold: 80))
        XCTAssertFalse(LimitChipMode.nearLimit.isVisible(usedPercent: nil, threshold: 80))
        XCTAssertFalse(LimitChipMode.nearLimit.isVisible(usedPercent: 79, threshold: 80))
        XCTAssertTrue(LimitChipMode.nearLimit.isVisible(usedPercent: 80, threshold: 80))
        XCTAssertFalse(LimitChipMode.never.isVisible(usedPercent: 100, threshold: 80))
    }

    func storage() throws {
        let scratch = try XCTUnwrap(ScratchDefaults("settings-checks"))
        let defaults = scratch.defaults
        defer { scratch.remove() }
        defaults.set(false, forKey: "answerFromNotch")
        XCTAssertFalse(SettingsStorage.read(Bool.self, key: "answerFromNotch", default: true, in: defaults))
        XCTAssertTrue(SettingsStorage.read(Bool.self, key: "sounds", default: true, in: defaults))
        defaults.set(Data("broken".utf8), forKey: "parts")
        let initial = [DisplayPart(RowPart.title)]
        XCTAssertEqual(SettingsStorage.read([DisplayPart<RowPart>].self, key: "parts", default: initial, in: defaults), initial)
        SettingsStorage.write(initial, key: "parts", in: defaults)
        XCTAssertEqual(SettingsStorage.read([DisplayPart<RowPart>].self, key: "parts", default: [], in: defaults), initial)
    }

    func scratchDefaults() throws {
        let preferences = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: preferences.path)) ?? [])
        let scratch = try XCTUnwrap(ScratchDefaults("scratch-checks"))
        scratch.defaults.set("value", forKey: "key")
        XCTAssertEqual(scratch.defaults.string(forKey: "key"), "value")
        XCTAssertNil(UserDefaults.standard.string(forKey: "key"))
        let other = try XCTUnwrap(ScratchDefaults("scratch-checks"))
        XCTAssertNil(other.defaults.string(forKey: "key"))
        other.remove()
        _ = scratch.defaults.synchronize()
        scratch.remove()
        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: preferences.path)) ?? [])
        XCTAssertEqual(after.subtracting(before).filter { $0.contains("scratch-checks") }, [])
    }

    func shortcuts() throws {
        XCTAssertEqual(KeyboardShortcut.allow.display, "⌃⌥Y")
        XCTAssertEqual(KeyboardShortcut.deny.display, "⌃⌥N")
        XCTAssertEqual(KeyboardShortcut.list.display, "⌃⌥A")
        XCTAssertFalse(KeyboardShortcut(keyCode: 43, modifiers: [.command]).isValid)
        XCTAssertFalse(KeyboardShortcut(keyCode: 16, modifiers: []).isValid)
        XCTAssertFalse(KeyboardShortcut(keyCode: 999, modifiers: [.control]).isValid)
        XCTAssertTrue(KeyboardShortcut(keyCode: 16, modifiers: [.command, .shift]).isValid)
        XCTAssertFalse(KeyboardShortcut(keyCode: 16, modifiers: [.shift]).isValid)
        XCTAssertEqual(try JSONDecoder().decode(KeyboardShortcut.self, from: JSONEncoder().encode(KeyboardShortcut.allow)), .allow)
    }

    func finishedRetention() {
        var log = SessionLog(id: "finished", vendor: .claude)
        log.lastAt = 1_000
        log.turnEnded = true
        XCTAssertNil(log.state(now: 1_301, finishedRetention: 300))
        XCTAssertEqual(log.state(now: 3_001, finishedRetention: 3_600), .done)
        log.live = ClaudeLive(status: "busy", waitingFor: nil, name: nil, alive: true)
        XCTAssertEqual(log.state(now: 3_001, finishedRetention: 300), .working)
        log.live = ClaudeLive(status: "idle", waitingFor: nil, name: nil, alive: true)
        XCTAssertNil(log.state(now: 3_001, finishedRetention: 300))
        let finished = Agent(id: "finished", vendor: .claude, title: "finished", state: .done, project: "p")
        let kept = Tree.build([finished], includeFinished: true)
        XCTAssertEqual(kept.flatMap(\.all), [finished])
        XCTAssertEqual(Wing.layout(kept, cramped: false).groups, [])
    }

    func scannerRetention() throws {
        let logs = LogTests()
        let home = try logs.home()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".claude/projects/p/finished.jsonl")
        try logs.write(file, [
            #"{"type":"assistant","timestamp":"\#(logs.stamp(2_000))","message":{"stop_reason":"end_turn","content":[]}}"#
        ])
        try FileManager.default.setAttributes([.modificationDate: logs.now.addingTimeInterval(-2_000)], ofItemAtPath: file.path)
        let scanner = LogScanner(home: home, execRuns: { [] })
        XCTAssertFalse(scanner.poll(now: logs.now, finishedRetention: 300)!.contains { $0.id == "finished" })
        XCTAssertTrue(scanner.poll(now: logs.now, finishedRetention: 3_600)!.contains { $0.id == "finished" })
        XCTAssertFalse(scanner.poll(now: logs.now.addingTimeInterval(1_601), finishedRetention: 3_600)!.contains { $0.id == "finished" })
    }

    func rowRenderingOrder() {
        let parts = [DisplayPart(RowPart.worktree), DisplayPart(.model), DisplayPart(.effort, enabled: false),
                     DisplayPart(.activity), DisplayPart(.branch), DisplayPart(.context), DisplayPart(.title)]
        XCTAssertEqual(RowDisplay.parts(parts), [.worktree, .model, .activity, .branch, .context, .title])
        XCTAssertEqual(RowDisplay.parts(parts, showModel: false, showActivity: false, showContext: false),
                       [.worktree, .branch, .title])
        let moved = DisplayOrder.move(parts, from: 4, to: 0)
        XCTAssertEqual(RowDisplay.parts(moved).first, .branch)
    }

    func wingSettings() {
        let agents = [Agent(id: "r", vendor: .claude, title: "root", state: .working, project: "repo"),
                      Agent(id: "k", vendor: .codex, title: "kid", state: .waiting, project: "repo", parentId: "r")]
        let projects = Tree.build(agents)
        var prefs = WingDisplayPrefs()
        prefs.markSize = .large
        prefs.showProjectNames = true
        let detailed = Wing.configuredLayout(projects, cramped: false, prefs: prefs, maxWidth: 400)
        guard case let .detailed(label, sessions) = detailed.groups.first else { return XCTFail("expected marks") }
        XCTAssertEqual(label, "repo")
        XCTAssertEqual(sessions.map(\.count), [2])
        XCTAssertTrue(Wing.configuredWidth(detailed.groups, prefs: prefs) > Wing.width(detailed.groups))
        prefs.separateSubagents = false
        guard case let .detailed(_, flat) = Wing.configuredLayout(projects, cramped: false, prefs: prefs, maxWidth: 400).groups.first
        else { return XCTFail("expected flat marks") }
        XCTAssertEqual(flat.map(\.count), [1, 1])
        prefs.maxMarks = 1
        guard case let .counters(_, claude, codex, exceptions) = Wing.configuredLayout(projects, cramped: false, prefs: prefs).groups.first
        else { return XCTFail("expected counters") }
        XCTAssertEqual(claude, 1)
        XCTAssertEqual(codex, 0)
        XCTAssertEqual(exceptions.map(\.state), [.waiting])
        prefs.groupByVendor = true
        prefs.maxMarks = 6
        let vendors = Wing.configuredLayout(projects, cramped: false, prefs: prefs, maxWidth: 400)
        XCTAssertEqual(vendors.groups.count, 2)
        prefs.countsOnly = true
        guard case .counters = Wing.configuredLayout(projects, cramped: false, prefs: prefs, maxWidth: 400).groups.first
        else { return XCTFail("expected configured counters") }
        XCTAssertTrue(Wing.configuredLayout(projects, cramped: true, prefs: prefs).collapsed)
    }


}
