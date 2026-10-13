import Foundation

/// One mark in the wing: shape is the vendor, fill is the model weight, colour is the state.
public struct Mark: Equatable, Sendable {
    public var vendor: Vendor
    public var light: Bool
    public var state: AgentState
    public init(vendor: Vendor, light: Bool, state: AgentState) {
        self.vendor = vendor; self.light = light; self.state = state
    }
    public init(_ a: Agent) { self.init(vendor: a.vendor, light: a.isLight, state: a.state) }
}

public enum WingGroup: Equatable, Sendable {
    /// Every live agent drawn: each session mark followed by smaller marks of its live subagents.
    case detailed(letter: String?, sessions: [[Mark]])
    /// Working agents counted per vendor; waiting and failing ones still drawn one by one.
    case counters(letter: String?, claude: Int, codex: Int, exceptions: [Mark])
}

public struct WingLayout: Equatable, Sendable {
    public var groups: [WingGroup]
    public var collapsed: Bool
}

public enum Wing {
    /// More live agents than this in one project → that project switches to counters.
    public static let detailLimit = 6

    public static func layout(_ projects: [ProjectNode], cramped: Bool, maxWidth: Double = 130) -> WingLayout {
        let live = projects.filter { !$0.live.isEmpty }
        if cramped { return WingLayout(groups: summary(live), collapsed: true) }
        let multi = live.count > 1
        let groups = live.map { p -> WingGroup in
            let letter = multi ? p.letter : nil
            if p.live.count > detailLimit { return counters(p.all, letter: letter) }
            let sessions = p.sessions.filter(\.isLive).map { s in [Mark(s.agent)] + s.liveKids.map(Mark.init) }
            return .detailed(letter: letter, sessions: sessions)
        }
        if width(groups) > maxWidth { return WingLayout(groups: summary(live), collapsed: true) }
        return WingLayout(groups: groups, collapsed: false)
    }

    static func summary(_ projects: [ProjectNode]) -> [WingGroup] {
        let all = projects.flatMap(\.all)
        return all.contains(where: \.state.isLive) ? [counters(all, letter: nil)] : []
    }

    static func counters(_ agents: [Agent], letter: String?) -> WingGroup {
        let working = agents.filter { $0.state == .working }
        return .counters(letter: letter,
                         claude: working.filter { $0.vendor == .claude }.count,
                         codex: working.filter { $0.vendor == .codex }.count,
                         exceptions: agents.filter(\.state.needsAttention).sorted { $0.state < $1.state }.map(Mark.init))
    }

    /// Point width estimate, matching the SwiftUI wing: 6 pt marks, 4 pt kids, 10 pt per counter digit pair.
    public static func width(_ groups: [WingGroup]) -> Double {
        let body = groups.map { g -> Double in
            switch g {
            case let .detailed(letter, sessions):
                let marks = sessions.map { s in 6 + Double(s.count - 1) * 5.5 }.reduce(0, +)
                return marks + Double(max(sessions.count - 1, 0)) * 4 + (letter == nil ? 0 : 8)
            case let .counters(letter, claude, codex, exceptions):
                let counter = { (n: Int) in n == 0 ? 0.0 : 8 + Double(String(n).count) * 6 + 4 }
                return counter(claude) + counter(codex) + Double(exceptions.count) * 10 + (letter == nil ? 0 : 8)
            }
        }
        return body.reduce(0, +) + Double(max(groups.count - 1, 0)) * 15
    }
}
