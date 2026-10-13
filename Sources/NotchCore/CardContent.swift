import Foundation

public enum CardTab: String, CaseIterable, Sendable {
    case done, remaining, files, log, prompts
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
        case .files, .log, .prompts: []
        }
    }

    /// Readers return log order; reverse it even when timestamps are absent.
    public static func commands(_ detail: AgentDetail, limit: Int = 30) -> [CommandRun] {
        Array(detail.commands.reversed().prefix(max(0, limit)))
    }

    /// The start stays apart; later prompts come newest first, without the start repeated.
    public static func prompts(_ detail: AgentDetail) -> (start: UserPrompt?, later: [UserPrompt]) {
        var later = detail.prompts
        if let start = detail.startPrompt, later.first == start { later.removeFirst() }
        return (detail.startPrompt, later.reversed())
    }

    public static func result(_ command: CommandRun) -> String {
        switch command.ok { case true: "✓"; case false: "✗"; case nil: "…" }
    }
}
