import Foundation

struct PresetChecks {
    private var start: PresetValues {
        PresetValues(rowParts: RowPart.allCases.map { DisplayPart($0) }.reversed(), subagentTree: .hidden, showFinished: false,
                     finishedMinutes: 5, limitChips: .never, limitWindows: [], cardBlocks: CardBlock.allCases.map { DisplayPart($0, enabled: false) })
    }

    private func visibleRow(_ v: PresetValues) -> Set<RowPart> {
        Set(RowDisplay.parts(v.rowParts, showModel: v.showModel, showActivity: v.showActivity, showContext: v.showContext))
    }

    func brief() {
        let v = DisplayPreset.brief.apply(to: start)
        XCTAssertEqual(visibleRow(v), [.statusMark, .title])
        XCTAssertEqual(v.subagentTree, .collapsed)
        XCTAssertTrue(v.showFinished)
        XCTAssertEqual(v.finishedMinutes, 10)
        XCTAssertEqual(v.limitChips, .nearLimit)
        XCTAssertEqual(v.limitWindows, [.short])
        XCTAssertEqual(Set(DisplayOrder.visible(v.cardBlocks)), [.done, .remaining])
        XCTAssertEqual(DisplayPreset.matching(v), .brief)
    }

    func detailed() {
        let v = DisplayPreset.detailed.apply(to: start)
        XCTAssertEqual(visibleRow(v), [.statusMark, .title, .model, .activity, .runningTime, .context])
        XCTAssertEqual(v.subagentTree, .auto)
        XCTAssertEqual(v.finishedMinutes, 30)
        XCTAssertEqual(v.limitChips, .always)
        XCTAssertEqual(v.limitWindows, [.short])
        // All five tabs; the log tab needs commands and errors to show anything.
        XCTAssertEqual(CardContent.tabs(blocks: DisplayOrder.visible(v.cardBlocks)).count, 5)
        XCTAssertEqual(Set(DisplayOrder.visible(v.cardBlocks)), [.done, .remaining, .files, .log, .prompts, .commands, .errors])
        XCTAssertEqual(DisplayPreset.matching(v), .detailed)
    }

    func everything() {
        let v = DisplayPreset.everything.apply(to: start)
        XCTAssertEqual(visibleRow(v), Set(RowPart.allCases))
        XCTAssertEqual(v.subagentTree, .expanded)
        XCTAssertEqual(v.finishedMinutes, 60)
        XCTAssertEqual(v.limitChips, .always)
        XCTAssertEqual(Set(v.limitWindows), [.short, .weekly])
        XCTAssertEqual(Set(DisplayOrder.visible(v.cardBlocks)), Set(CardBlock.allCases))
        XCTAssertEqual(DisplayPreset.matching(v), .everything)
    }

    func ownAndBack() {
        let preset = DisplayPreset.detailed.apply(to: start)
        // Order is kept, so a preset never shuffles what the user arranged.
        XCTAssertEqual(preset.rowParts.map(\.part), start.rowParts.map(\.part))
        var changed = preset
        changed.finishedMinutes = 15
        XCTAssertNil(DisplayPreset.matching(changed))
        changed = preset
        changed.showModel = false
        XCTAssertNil(DisplayPreset.matching(changed))
        changed = preset
        changed.rowParts[changed.rowParts.firstIndex { $0.part == .cost }!].enabled = true
        XCTAssertNil(DisplayPreset.matching(changed))
        changed = preset
        changed.cardBlocks[changed.cardBlocks.firstIndex { $0.part == .lastMessage }!].enabled = true
        XCTAssertNil(DisplayPreset.matching(changed))
        changed = preset
        changed.limitWindows = [.short, .weekly]
        XCTAssertNil(DisplayPreset.matching(changed))
        XCTAssertEqual(DisplayPreset.matching(DisplayPreset.detailed.apply(to: changed)), .detailed)
        // Reordering is not a change of value.
        changed = preset
        changed.rowParts = DisplayOrder.move(changed.rowParts, from: 0, to: 3)
        XCTAssertEqual(DisplayPreset.matching(changed), .detailed)
        XCTAssertTrue(DisplayPreset.finishedChoices.contains(10))
    }

    // MARK: icons

    private func tempApps() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notch-icons-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func iconAppPresent() throws {
        let root = try tempApps()
        defer { try? FileManager.default.removeItem(at: root) }
        let claude = root.appendingPathComponent("Claude.app")
        let chatgpt = root.appendingPathComponent("ChatGPT.app")
        let resources = chatgpt.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data([1]).write(to: resources.appendingPathComponent("icon-codex-light.png"))
        try Data([1]).write(to: resources.appendingPathComponent("icon-codex-dark-color.png"))
        let apps = ["com.anthropic.claudefordesktop": claude, "com.openai.codex": chatgpt]
        let locate: (String) -> URL? = { apps[$0] }
        XCTAssertEqual(AppIcon.source(for: .claude, dark: false, locate: locate), .bundle(claude))
        XCTAssertEqual(AppIcon.source(for: .claude, dark: true, locate: locate), .bundle(claude))
        XCTAssertEqual(AppIcon.source(for: .codex, dark: false, locate: locate), .file(resources.appendingPathComponent("icon-codex-light.png")))
        XCTAssertEqual(AppIcon.source(for: .codex, dark: true, locate: locate), .file(resources.appendingPathComponent("icon-codex-dark-color.png")))
    }

    func iconAppMissing() {
        XCTAssertNil(AppIcon.source(for: .claude, dark: false, locate: { _ in nil }))
        XCTAssertNil(AppIcon.source(for: .codex, dark: true, locate: { _ in nil }))
        // A registered app that was deleted since is the same as no app.
        let gone = URL(fileURLWithPath: "/nonexistent-" + UUID().uuidString + "/Claude.app")
        XCTAssertNil(AppIcon.source(for: .claude, dark: false, locate: { _ in gone }))
    }

    func iconFileMissing() throws {
        let root = try tempApps()
        defer { try? FileManager.default.removeItem(at: root) }
        let chatgpt = root.appendingPathComponent("ChatGPT.app")
        let resources = chatgpt.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        XCTAssertNil(AppIcon.source(for: .codex, dark: false, locate: { _ in chatgpt }))
        try Data([1]).write(to: resources.appendingPathComponent("icon-codex-light.png"))
        XCTAssertNotNil(AppIcon.source(for: .codex, dark: false, locate: { _ in chatgpt }))
        // The dark file is missing: no silent swap to a light icon on a dark background.
        XCTAssertNil(AppIcon.source(for: .codex, dark: true, locate: { _ in chatgpt }))
    }

    // MARK: copy

    /// Shown strings only: dictionary keys are storage identifiers, not copy.
    func noJargon() throws {
        let source = try String(contentsOfFile: "Sources/AgentsNotch/SettingsText.swift", encoding: .utf8)
        let literal = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)"(\s*:)?"#)
        let range = NSRange(source.startIndex..., in: source)
        let shown = literal.matches(in: source, range: range).filter { $0.range(at: 2).location == NSNotFound }
            .compactMap { Range($0.range(at: 1), in: source).map { String(source[$0]) } }
        XCTAssertTrue(shown.count > 50, "found \(shown.count) strings")
        for word in ["хук", "accessibility", "эффорт", "worktree", "чип", "метк"] {
            for text in shown where text.lowercased().contains(word) { XCTFail("jargon «\(word)» in «\(text)»") }
        }
    }
}

func XCTAssertNotNil<T>(_ a: T?, file: StaticString = #fileID, line: UInt = #line) {
    if a == nil { report("unexpected nil", file, line) }
}
