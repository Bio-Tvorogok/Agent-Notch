import Foundation

/// A top-level session with every descendant flattened under it.
public struct SessionNode: Identifiable, Equatable, Sendable {
    public var agent: Agent
    public var kids: [Agent]
    public var id: String { agent.id }
    public var all: [Agent] { [agent] + kids }
    public var worst: AgentState { all.map(\.state).min() ?? .done }
    public var liveKids: [Agent] { kids.filter { $0.state.isLive } }
    public var doneKids: [Agent] { kids.filter { !$0.state.isLive } }
    public var isLive: Bool { all.contains { $0.state.isLive } }
}

public struct ProjectNode: Identifiable, Equatable, Sendable {
    public var name: String
    public var sessions: [SessionNode]
    public var id: String { name }
    public var all: [Agent] { sessions.flatMap(\.all) }
    public var live: [Agent] { all.filter { $0.state.isLive } }
    public var worst: AgentState { sessions.map(\.worst).min() ?? .done }
    public var letter: String { String(name.first.map { Character($0.lowercased()) } ?? "?") }
}

public enum Tree {
    /// Groups agents by project and nests each subagent under its top-level ancestor.
    /// A subagent whose parent is gone (asleep or removed) becomes top-level itself.
    public static func build(_ agents: [Agent], includeFinished: Bool = false) -> [ProjectNode] {
        let byId = Dictionary(agents.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func root(of a: Agent) -> Agent {
            var cur = a
            var seen: Set<String> = [a.id]
            while let p = cur.parentId, let parent = byId[p], seen.insert(p).inserted { cur = parent }
            return cur
        }
        var kids: [String: [Agent]] = [:]
        var roots: [Agent] = []
        for a in agents {
            let r = root(of: a)
            if r.id == a.id { roots.append(a) } else { kids[r.id, default: []].append(a) }
        }
        let sessions = roots.map { r in
            SessionNode(agent: r, kids: (kids[r.id] ?? []).sorted { ($0.state, $0.startedAt) < ($1.state, $1.startedAt) })
        }
        let projects = Dictionary(grouping: sessions, by: \.agent.project).map { name, list in
            ProjectNode(name: name, sessions: list.sorted { ($0.worst, $0.agent.startedAt) < ($1.worst, $1.agent.startedAt) })
        }
        return projects
            .filter { includeFinished || $0.sessions.contains(where: \.isLive) }
            .sorted { ($0.worst, $0.name) < ($1.worst, $1.name) }
    }
}
