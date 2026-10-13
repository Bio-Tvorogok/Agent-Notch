import Foundation

/// Shared metrics keep mark sizing and the menu collision estimate in sync.
public struct WingDisplayPrefs: Equatable, Sendable {
    public var markSize: MarkSize = .small
    public var maxMarks = Wing.detailLimit
    public var countsOnly = false
    public var showProjectNames = false
    public var groupByVendor = false
    public var separateSubagents = true
    public init() {}
    public func labelWidth(_ text: String) -> Double { max(8, Double(min(12, text.count)) * 6) }
    public var childSize: Double { markSize.points * 2 / 3 }
    public var sessionGap: Double { markSize.points * 2 / 3 }
    public var childGap: Double { markSize.points / 4 }
}

extension Wing {
    public static func configuredLayout(_ projects: [ProjectNode], cramped: Bool, prefs: WingDisplayPrefs,
                                        maxWidth: Double = 130) -> WingLayout {
        var live = projects.filter { !$0.live.isEmpty }
        if prefs.groupByVendor {
            live = [Vendor.claude, .codex].flatMap { vendor in
                let agents = live.flatMap(\.all).filter { $0.vendor == vendor }.map { a in
                    var next = a
                    next.project = vendor == .claude ? "Claude" : "Codex"
                    return next
                }
                return Tree.build(agents)
            }
        }
        if cramped { return WingLayout(groups: summary(live), collapsed: true) }
        let multi = live.count > 1
        let groups = live.map { project -> WingGroup in
            let label = prefs.showProjectNames ? project.name : (multi ? project.letter : nil)
            if prefs.countsOnly || project.live.count > max(1, prefs.maxMarks) {
                return counters(project.all, letter: label)
            }
            let sessions: [[Mark]]
            if prefs.separateSubagents {
                sessions = project.sessions.filter(\.isLive).map { session in
                    [Mark(session.agent)] + session.liveKids.map(Mark.init)
                }
            } else { sessions = project.live.map { [Mark($0)] } }
            return .detailed(letter: label, sessions: sessions)
        }
        if configuredWidth(groups, prefs: prefs) > maxWidth {
            return WingLayout(groups: summary(live), collapsed: true)
        }
        return WingLayout(groups: groups, collapsed: false)
    }

    public static func configuredWidth(_ groups: [WingGroup], prefs: WingDisplayPrefs) -> Double {
        let size = prefs.markSize.points
        let body = groups.map { group -> Double in
            let label: String?
            let width: Double
            switch group {
            case let .detailed(letter, sessions):
                label = letter
                width = sessions.reduce(0) { total, marks in
                    total + size + Double(max(0, marks.count - 1)) * (prefs.childSize + prefs.childGap)
                } + Double(max(0, sessions.count - 1)) * prefs.sessionGap
            case let .counters(letter, claude, codex, exceptions):
                label = letter
                let counts = [claude, codex].filter { $0 > 0 }
                let counterWidths = counts.reduce(0.0) { $0 + size + 2 + Double(String($1).count) * 6 }
                let elements = counts.count + exceptions.count
                width = counterWidths + Double(exceptions.count) * size + Double(max(0, elements - 1)) * prefs.sessionGap
            }
            return width + (label.map { prefs.labelWidth($0) + prefs.sessionGap } ?? 0)
        }
        return body.reduce(0, +) + Double(max(0, groups.count - 1)) * 15
    }
}
