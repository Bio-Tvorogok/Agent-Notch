import Combine
import Foundation
import NotchCore

/// Section values are Codable so the list and card can consume them without knowing UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults: UserDefaults
    private var ready = false
    private var resetting = false
    var visibilityObservers: [ObjectIdentifier: () -> Void] = [:]

    @Published var appearance: AppearancePrefs { didSet { save(appearance, "appearance") } }
    @Published var wing: WingPrefs { didSet { save(wing, "wing") } }
    @Published var rows: RowPrefs { didSet { save(rows, "rows") } }
    @Published var card: CardPrefs { didSet { save(card, "card") } }
    @Published var limits: LimitsPrefs { didSet { save(limits, "limits") } }
    @Published var behavior: BehaviorPrefs { didSet { save(behavior, "behavior"); visibilityObservers.values.forEach { $0() } } }
    @Published var shortcuts: ShortcutPrefs { didSet { save(shortcuts, "shortcuts") } }
    @Published var general: GeneralPrefs { didSet { save(general, "general") } }
    @Published var answerFromNotch: Bool { didSet { save(answerFromNotch, "answerFromNotch") } }
    @Published var sounds: Bool { didSet { if !sounds { SoundPlayer.shared.stop() }; save(sounds, "sounds") } }
    @Published var soundEvents: SoundPrefs { didSet { save(soundEvents, "soundEvents") } }
    /// A small toast under the notch when an agent finishes.
    @Published var finishToast: Bool { didSet { save(finishToast, "finishToast") } }
    @Published var isRecordingShortcut = false
    @Published var hotKeyError: String?

    var rowParts: [DisplayPart<RowPart>] {
        get { rows.parts }
        set { rows.parts = DisplayOrder.normalize(newValue) }
    }
    var cardBlocks: [DisplayPart<CardBlock>] {
        get { card.blocks }
        set { card.blocks = DisplayOrder.normalize(newValue) }
    }

    /// Tests and snapshots supply an isolated suite, never the user's real preferences.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func load<T: Codable>(_ key: String, _ fallback: T) -> T {
            SettingsStorage.read(T.self, key: key, default: fallback, in: defaults)
        }
        appearance = load("appearance", AppearancePrefs())
        wing = load("wing", WingPrefs())
        rows = load("rows", RowPrefs())
        card = load("card", CardPrefs())
        limits = load("limits", LimitsPrefs())
        let savedBehavior = load("behavior", BehaviorPrefs())
        behavior = savedBehavior
        soundEvents = load("soundEvents", SoundPrefs(legacyName: savedBehavior.soundName))
        shortcuts = load("shortcuts", ShortcutPrefs())
        general = load("general", GeneralPrefs())
        answerFromNotch = load("answerFromNotch", true)
        sounds = load("sounds", true)
        finishToast = load("finishToast", true)
        rows.parts = DisplayOrder.normalize(rows.parts)
        card.blocks = DisplayOrder.normalize(card.blocks)
        if !shortcuts.isValid { shortcuts = ShortcutPrefs() }
        appearance.finishedMinutes = DisplayPreset.finishedChoices.contains(appearance.finishedMinutes) ? appearance.finishedMinutes : 30
        wing.maxMarks = min(20, max(1, wing.maxMarks))
        limits.warningPercent = min(100, max(1, limits.warningPercent))
        // Rewrite the section without the retired language preference.
        save(general, "general")
        ready = true
    }

    func setShortcut(_ value: NotchCore.KeyboardShortcut, for action: ShortcutAction) -> Bool {
        guard value.isValid, !ShortcutAction.allCases.contains(where: { $0 != action && shortcuts[$0] == value }) else { return false }
        shortcuts[action] = value
        return true
    }

    /// Everything back to the first launch except what «Подключение» holds (hooks, hidden projects).
    /// Login is the caller's: it touches the system.
    func resetAll() {
        SoundPlayer.shared.play(.settingsReset, settings: self)
        resetting = true
        defer { resetting = false }
        let hidden = behavior.hiddenProjects
        appearance = AppearancePrefs()
        wing = WingPrefs()
        rows = RowPrefs()
        card = CardPrefs()
        limits = LimitsPrefs()
        var fresh = BehaviorPrefs()
        fresh.hiddenProjects = hidden
        behavior = fresh
        shortcuts = ShortcutPrefs()
        answerFromNotch = true
        sounds = true
        soundEvents = SoundPrefs()
        finishToast = true
    }

    /// What the presets own, read from and written back to the sections.
    var presetValues: PresetValues {
        get {
            PresetValues(rowParts: rows.parts, showModel: appearance.showModel, showActivity: appearance.showActivity,
                         showContext: appearance.showContext, subagentTree: rows.subagentTree, showFinished: rows.showFinished,
                         finishedMinutes: appearance.finishedMinutes, limitChips: appearance.limitChips,
                         limitWindows: limits.windows, cardBlocks: card.blocks)
        }
        set {
            var a = appearance, r = rows, l = limits, c = card
            a.showModel = newValue.showModel
            a.showActivity = newValue.showActivity
            a.showContext = newValue.showContext
            a.finishedMinutes = newValue.finishedMinutes
            a.limitChips = newValue.limitChips
            r.parts = DisplayOrder.normalize(newValue.rowParts)
            r.subagentTree = newValue.subagentTree
            r.showFinished = newValue.showFinished
            l.windows = newValue.limitWindows
            c.blocks = DisplayOrder.normalize(newValue.cardBlocks)
            if a != appearance { appearance = a }
            if r != rows { rows = r }
            if l != limits { limits = l }
            if c != card { card = c }
        }
    }

    /// nil is «Своё»: something was changed by hand after a preset.
    var preset: DisplayPreset? { DisplayPreset.matching(presetValues) }
    func apply(_ preset: DisplayPreset) { presetValues = preset.apply(to: presetValues) }

    /// A row part is on when both its switch in «Внешний вид» and its place in «Порядок…» are on.
    func rowPartShown(_ part: RowPart) -> Bool { visibleRowParts.contains(part) }
    func setRowPart(_ part: RowPart, shown: Bool) {
        if shown {
            switch part {
            case .model: appearance.showModel = true
            case .activity: appearance.showActivity = true
            case .context: appearance.showContext = true
            default: break
            }
        }
        if let i = rows.parts.firstIndex(where: { $0.part == part }) { rows.parts[i].enabled = shown }
    }
    func cardBlockShown(_ block: CardBlock) -> Bool { card.blocks.contains { $0.part == block && $0.enabled } }
    /// The log tab is made of commands and errors: switching it on brings them along, or it would stay empty.
    func setCardBlock(_ block: CardBlock, shown: Bool) {
        var blocks = card.blocks
        let parts: [CardBlock] = block == .log && shown ? [.log, .commands, .errors] : [block]
        for part in parts { if let i = blocks.firstIndex(where: { $0.part == part }) { blocks[i].enabled = shown } }
        card.blocks = blocks
    }

    private func save<T: Codable & Equatable>(_ value: T, _ key: String) {
        let unchanged = defaults.object(forKey: key) != nil && SettingsStorage.read(T.self, key: key, default: value, in: defaults) == value
        SettingsStorage.write(value, key: key, in: defaults)
        if ready, !resetting, !unchanged { SoundPlayer.shared.play(.settingsChanged, settings: self) }
    }
}
