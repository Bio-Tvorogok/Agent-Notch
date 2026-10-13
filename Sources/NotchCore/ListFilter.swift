import Foundation

public enum SessionSort: String, Codable, CaseIterable, Sendable {
    case attention, recent, name

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "newest": self = .recent
        case "project": self = .name
        case "vendor": self = .attention
        default:
            guard let order = Self(rawValue: value) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown session sort"))
            }
            self = order
        }
    }
}

public enum SessionTreeMode: String, Codable, CaseIterable, Sendable {
    /// Auto opens a family of up to two, or one where a subagent needs attention; bigger calm families stay folded.
    case auto, expanded, collapsed, hidden
    public func showsChildren(override: Bool?, kids: [Agent] = []) -> Bool {
        guard self != .hidden else { return false }
        if let override { return override }
        switch self {
        case .auto: return kids.count <= 2 || kids.contains { $0.state.needsAttention }
        case .expanded: return true
        case .collapsed, .hidden: return false
        }
    }
}

/// One visibility policy keeps hidden agents out of both surfaces and request routing.
public struct ListFilter: Sendable {
    public var claude: Bool
    public var codex: Bool
    public var hiddenProjects: [String]

    public init(claude: Bool = true, codex: Bool = true, hiddenProjects: [String] = []) {
        self.claude = claude
        self.codex = codex
        self.hiddenProjects = hiddenProjects
    }

    public func includes(vendor: Vendor, project: String, cwd: String?) -> Bool {
        guard vendor == .claude ? claude : codex else { return false }
        return !hiddenProjects.contains { hidden in
            let hidden = hidden.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hidden.isEmpty else { return false }
            guard hidden.hasPrefix("/") || hidden.hasPrefix("~") else { return hidden == project }
            guard let cwd, !cwd.isEmpty else { return false }
            let path = PathCache.path(hidden)
            let current = PathCache.path(cwd)
            if current == path || current.hasPrefix(path == "/" ? path : path + "/") { return true }
            // A hidden repository root also hides its worktrees elsewhere; a hidden subfolder hides only itself.
            return PathCache.repository(path) == path && PathCache.repository(current) == path
        }
    }
    /// Agents in `keeping` (those with a held request) stay listed even when hidden, so the request has a row.
    public func apply(_ agents: [Agent], keeping: Set<String> = []) -> [Agent] {
        agents.filter { keeping.contains($0.id) || includes(vendor: $0.vendor, project: $0.project, cwd: $0.cwd) }
    }
    /// Hiding follows the agent the event belongs to, when it is known; the event's own cwd otherwise.
    public func shouldPass(_ event: HookEvent, project: String, answerFromNotch: Bool, owner: Agent? = nil) -> Bool {
        guard answerFromNotch, !event.answeredElsewhere else { return true }
        if let owner { return !includes(vendor: owner.vendor, project: owner.project, cwd: owner.cwd) }
        return !includes(vendor: event.vendor, project: project, cwd: event.cwd)
    }
    public static func sorted(_ sessions: [SessionNode], by order: SessionSort) -> [SessionNode] {
        sessions.sorted { a, b in
            switch order {
            case .attention:
                if a.worst != b.worst { return a.worst < b.worst }
                if a.agent.startedAt != b.agent.startedAt { return a.agent.startedAt > b.agent.startedAt }
            case .recent:
                if a.agent.startedAt != b.agent.startedAt { return a.agent.startedAt > b.agent.startedAt }
            case .name:
                let left = a.agent.title.lowercased(), right = b.agent.title.lowercased()
                if left != right { return left < right }
            }
            return a.id < b.id
        }
    }
    public static func sections(_ projects: [ProjectNode], grouped: Bool, order: SessionSort) -> [ProjectNode] {
        guard grouped else {
            let sessions = sorted(projects.flatMap(\.sessions), by: order)
            return sessions.isEmpty ? [] : [ProjectNode(name: "", sessions: sessions)]
        }
        return projects.map { ProjectNode(name: $0.name, sessions: sorted($0.sessions, by: order)) }
    }
}
