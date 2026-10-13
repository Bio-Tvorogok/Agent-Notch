import Foundation

public enum LimitPeriod: String, Codable, CaseIterable, Sendable { case short, weekly }

/// The settings a preset owns. Marks and their size are left alone.
public struct PresetValues: Equatable {
    public var rowParts: [DisplayPart<RowPart>]
    public var showModel = true
    public var showActivity = true
    public var showContext = true
    public var subagentTree: SessionTreeMode
    public var showFinished: Bool
    public var finishedMinutes: Int
    public var limitChips: LimitChipMode
    public var limitWindows: [LimitPeriod]
    public var cardBlocks: [DisplayPart<CardBlock>]

    public init(rowParts: [DisplayPart<RowPart>], showModel: Bool = true, showActivity: Bool = true, showContext: Bool = true,
                subagentTree: SessionTreeMode, showFinished: Bool, finishedMinutes: Int, limitChips: LimitChipMode,
                limitWindows: [LimitPeriod], cardBlocks: [DisplayPart<CardBlock>]) {
        self.rowParts = rowParts
        self.showModel = showModel
        self.showActivity = showActivity
        self.showContext = showContext
        self.subagentTree = subagentTree
        self.showFinished = showFinished
        self.finishedMinutes = finishedMinutes
        self.limitChips = limitChips
        self.limitWindows = limitWindows
        self.cardBlocks = cardBlocks
    }
}

public enum DisplayPreset: String, CaseIterable, Sendable {
    case brief, detailed, everything

    public static let finishedChoices = [5, 10, 15, 30, 60]

    public var rowParts: Set<RowPart> {
        switch self {
        case .brief: [.statusMark, .title]
        case .detailed: [.statusMark, .title, .model, .activity, .runningTime, .context]
        case .everything: Set(RowPart.allCases)
        }
    }
    public var subagentTree: SessionTreeMode {
        switch self { case .brief: .collapsed; case .detailed: .auto; case .everything: .expanded }
    }
    public var finishedMinutes: Int {
        switch self { case .brief: 10; case .detailed: 30; case .everything: 60 }
    }
    public var limitChips: LimitChipMode { self == .brief ? .nearLimit : .always }
    public var limitWindows: [LimitPeriod] { self == .everything ? [.short, .weekly] : [.short] }
    /// "All tabs" includes commands and errors: without them the log tab is empty.
    public var cardBlocks: Set<CardBlock> {
        switch self {
        case .brief: [.done, .remaining]
        case .detailed: [.done, .remaining, .files, .log, .prompts, .commands, .errors]
        case .everything: Set(CardBlock.allCases)
        }
    }

    /// Switches parts on and off in place; the user's order stays.
    public func apply(to values: PresetValues) -> PresetValues {
        var next = values
        next.rowParts = DisplayOrder.normalize(values.rowParts).map { DisplayPart($0.part, enabled: rowParts.contains($0.part)) }
        next.showModel = true
        next.showActivity = true
        next.showContext = true
        next.subagentTree = subagentTree
        next.showFinished = true
        next.finishedMinutes = finishedMinutes
        next.limitChips = limitChips
        next.limitWindows = limitWindows
        next.cardBlocks = DisplayOrder.normalize(values.cardBlocks).map { DisplayPart($0.part, enabled: cardBlocks.contains($0.part)) }
        return next
    }

    /// nil means the user's own mix ("Своё").
    public static func matching(_ v: PresetValues) -> DisplayPreset? {
        let row = Set(RowDisplay.parts(v.rowParts, showModel: v.showModel, showActivity: v.showActivity, showContext: v.showContext))
        let card = Set(DisplayOrder.visible(v.cardBlocks))
        return allCases.first { preset in
            let rows = preset.rowParts == row && preset.cardBlocks == card
            let list = preset.subagentTree == v.subagentTree && v.showFinished && preset.finishedMinutes == v.finishedMinutes
            let limits = preset.limitChips == v.limitChips && Set(preset.limitWindows) == Set(v.limitWindows)
            return rows && list && limits
        }
    }
}
