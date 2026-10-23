import Foundation

/// One line of the desktop widget's list.
public enum WidgetLine: Equatable, Sendable {
    case project(String)
    /// A session row; `folded` subagents are drawn as a counter instead of their own rows.
    case session(Agent, folded: Int)
    case kid(Agent, last: Bool)
    /// Finished subagents of one session, folded into one line.
    case doneKids([Agent])
    /// An agent that needs the user: its request and answer buttons are drawn under it. Never dropped.
    case attention(Agent, parent: String?)
    /// "и ещё N": sessions that did not fit.
    case more(Int)
}

/// What fits in the widget. It makes room in steps: finished agents go first, then subagents fold into a counter,
/// then the last calm sessions give way to "и ещё N". Waiting and failed agents always stay.
public enum WidgetPlan {
    /// An attention line with its request and buttons is about this many ordinary rows tall.
    public static let attentionCost = 2

    public static func lines(_ sections: [ProjectNode], tree: SessionTreeMode, pinned: Set<String> = [], capacity: Int) -> [WidgetLine] {
        let sections = sections.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for step in 0..<3 {
            let lines = build(sections, tree: tree, pinned: pinned, dropFinished: step >= 1, fold: step >= 2, capacity: nil)
            if cost(lines) <= capacity { return lines }
        }
        return build(sections, tree: tree, pinned: pinned, dropFinished: true, fold: true, capacity: capacity)
    }

    public static func cost(_ lines: [WidgetLine]) -> Int {
        lines.reduce(0) { sum, line in
            if case .attention = line { return sum + attentionCost }
            return sum + 1
        }
    }

    private static func needsYou(_ a: Agent, _ pinned: Set<String>) -> Bool {
        a.state.needsAttention || pinned.contains(a.id)
    }

    private static func build(_ sections: [ProjectNode], tree: SessionTreeMode, pinned: Set<String>,
                              dropFinished: Bool, fold: Bool, capacity: Int?) -> [WidgetLine] {
        let headers = sections.count > 1 && sections.contains { !$0.name.isEmpty }
        // With a capacity, calm sessions are taken in order while they fit; the urgent ones are paid for first.
        var budget = capacity.map { cap -> Int in
            let urgent = sections.flatMap(\.sessions).flatMap(\.all).filter { needsYou($0, pinned) }.count
            return cap - urgent * attentionCost - 1
        }
        var lines: [WidgetLine] = []
        var hidden = 0
        for section in sections {
            var block: [WidgetLine] = []
            for s in section.sessions {
                let urgentKids = s.kids.filter { needsYou($0, pinned) }
                let urgent = needsYou(s.agent, pinned) || !urgentKids.isEmpty
                if dropFinished && !s.isLive && !urgent { hidden += 1; continue }
                var own: [WidgetLine] = []
                let open = !fold && tree.showsChildren(override: nil, kids: s.kids)
                let calmKids = s.kids.filter { !needsYou($0, pinned) }
                let folded = open ? 0 : calmKids.count
                own.append(needsYou(s.agent, pinned) ? .attention(s.agent, parent: nil) : .session(s.agent, folded: folded))
                var kids: [WidgetLine] = []
                for k in s.kids where needsYou(k, pinned) { kids.append(.attention(k, parent: s.agent.title)) }
                if open {
                    for k in s.liveKids where !needsYou(k, pinned) { kids.append(.kid(k, last: false)) }
                    let done = s.doneKids.filter { !needsYou($0, pinned) }
                    if !done.isEmpty && !dropFinished { kids.append(.doneKids(done)) }
                }
                if let i = kids.lastIndex(where: { if case .kid = $0 { return true }; return false }),
                   case .kid(let k, _) = kids[i], i == kids.count - 1 { kids[i] = .kid(k, last: true) }
                own += kids
                if let left = budget {
                    let calm = own.filter { if case .attention = $0 { return false }; return true }.count
                    let header = headers && block.isEmpty ? 1 : 0
                    if !urgent && calm + header > left { hidden += 1; continue }
                    budget = left - calm - header
                }
                block += own
            }
            if block.isEmpty { continue }
            if headers { lines.append(.project(section.name)) }
            lines += block
        }
        if hidden > 0 { lines.append(.more(hidden)) }
        return lines
    }
}

public enum WidgetText {
    /// "5 агентов работают": the number is drawn apart, so this is the words after it.
    public static func working(_ n: Int) -> String {
        guard Loc.isRussian else { return n == 1 ? "agent working" : "agents working" }
        let last = n % 10, tens = n % 100
        if last == 1 && tens != 11 { return "агент работает" }
        if (2...4).contains(last) && !(12...14).contains(tens) { return "агента работают" }
        return "агентов работают"
    }
    public static func waiting(_ n: Int) -> String { Loc.t("\(n) waiting", "\(n) ждёт ответа") }
    public static func errors(_ n: Int) -> String { Loc.t(n == 1 ? "1 error" : "\(n) errors", n == 1 ? "1 ошибка" : "\(n) с ошибкой") }
    public static func more(_ n: Int) -> String { Loc.t("and \(n) more", "и ещё \(n)") }
    public static var idle: String { Loc.t("No agents running", "Агенты не запущены") }
}
