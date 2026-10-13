import Foundation

public enum CardTab: String, CaseIterable, Sendable {
    case done, remaining, files, log
}

public enum CardContent {
    public static func tabs(blocks: [CardBlock]) -> [CardTab] {
        var seen = Set<CardTab>()
        return blocks.compactMap { CardTab(rawValue: $0.rawValue) }.filter { seen.insert($0).inserted }
    }

    public static func plan(_ detail: AgentDetail, tab: CardTab) -> [PlanItem] {
        switch tab {
        case .done: detail.plan.filter { $0.status == .done }
        case .remaining: detail.plan.filter { $0.status == .active } + detail.plan.filter { $0.status == .todo }
        case .files, .log: []
        }
    }

    /// Readers return log order; reverse it even when timestamps are absent.
    public static func commands(_ detail: AgentDetail, limit: Int = 30) -> [CommandRun] {
        Array(detail.commands.reversed().prefix(max(0, limit)))
    }

    public static func result(_ command: CommandRun) -> String {
        switch command.ok { case true: "✓"; case false: "✗"; case nil: "…" }
    }
}
