import Foundation
import NotchCore

// Raw values are stable storage identifiers; labels live in SettingsText.
enum WingContent: String, Codable, CaseIterable { case marks, counts, projects }
enum DisplayGrouping: String, Codable, CaseIterable { case project, vendor }
enum TitleSource: String, Codable, CaseIterable { case session, firstPrompt, branch }
typealias RowSort = SessionSort
typealias SubagentTree = SessionTreeMode
typealias LimitWindow = LimitPeriod
enum ShortcutAction: String, CaseIterable { case allow, deny, list }

/// Defaults are the «Подробно» preset; marks default to app logos with a status dot.
struct AppearancePrefs: Codable, Equatable {
    var markStyle: MarkStyle = .logos
    var markSize: MarkSize = .medium
    var showModel = true
    var showActivity = true
    var showContext = true
    var limitChips: LimitChipMode = DisplayPreset.detailed.limitChips
    var finishedMinutes = DisplayPreset.detailed.finishedMinutes
}

struct WingPrefs: Codable, Equatable {
    var content: WingContent = .marks
    var maxMarks = 6
    var grouping: DisplayGrouping = .project
    var separateSubagents = true
}

struct RowPrefs: Codable, Equatable {
    var parts = RowPart.allCases.map { DisplayPart($0, enabled: DisplayPreset.detailed.rowParts.contains($0)) }
    var titleSource: TitleSource = .session
    var sort: RowSort = .attention
    var groupByProject = true
    var showFinished = true
    var subagentTree: SubagentTree = DisplayPreset.detailed.subagentTree
}

struct CardPrefs: Codable, Equatable {
    var blocks = CardBlock.allCases.map { DisplayPart($0, enabled: DisplayPreset.detailed.cardBlocks.contains($0)) }
}

struct LimitsPrefs: Codable, Equatable {
    var claude = true
    var codex = true
    var windows: [LimitWindow] = DisplayPreset.detailed.limitWindows
    var warningPercent = 80
}

struct BehaviorPrefs: Codable, Equatable {
    var openOnRequest = true
    var soundName = "Glass"
    var hiddenProjects: [String] = []
    var claude = true
    var codex = true
}

struct ShortcutPrefs: Codable, Equatable {
    var allow: NotchCore.KeyboardShortcut = .allow
    var deny: NotchCore.KeyboardShortcut = .deny
    var list: NotchCore.KeyboardShortcut = .list

    subscript(_ action: ShortcutAction) -> NotchCore.KeyboardShortcut {
        get { switch action { case .allow: allow; case .deny: deny; case .list: list } }
        set { switch action { case .allow: allow = newValue; case .deny: deny = newValue; case .list: list = newValue } }
    }
    var isValid: Bool {
        let values = ShortcutAction.allCases.map { self[$0] }
        return values.allSatisfy(\.isValid) && values[0] != values[1] && values[0] != values[2] && values[1] != values[2]
    }
}

struct GeneralPrefs: Codable, Equatable {
    var openAtLogin = false
}
