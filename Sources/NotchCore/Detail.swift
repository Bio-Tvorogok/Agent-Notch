import Foundation

public enum PlanStatus: String, Equatable, Sendable {
    case done, active, todo
    init(logValue: String?) {
        switch logValue {
        case "completed", "done": self = .done
        case "in_progress", "active": self = .active
        default: self = .todo
        }
    }
}

public struct PlanItem: Equatable, Sendable {
    public var text: String
    public var status: PlanStatus
    public init(text: String, status: PlanStatus) { self.text = text; self.status = status }
}

public struct FileChange: Equatable, Sendable {
    public var path: String
    public var added: Int
    public var removed: Int
    /// When the file was last changed; lets the finish toast count only this run's files.
    public var at: Double?
    public init(path: String, added: Int, removed: Int, at: Double? = nil) {
        self.path = path; self.added = added; self.removed = removed; self.at = at
    }
}

public struct CommandRun: Equatable, Sendable {
    public var command: String
    /// Hash printed by this command, never inferred from repository HEAD.
    public var commit: String?
    public var ok: Bool?
    public var at: Double?
    public var isTest: Bool {
        command.range(of: #"\b(test|vitest|jest|pytest)\b|scripts/test"#, options: .regularExpression) != nil
    }
    public init(command: String, ok: Bool? = nil, at: Double? = nil, commit: String? = nil) {
        self.command = command; self.ok = ok; self.at = at; self.commit = commit
    }
}

public struct DetailError: Equatable, Sendable {
    public var text: String
    public var count: Int
    public init(text: String, count: Int) { self.text = text; self.count = count }
}

/// Something the owner typed to the agent, not a harness insert or a tool result.
public struct UserPrompt: Equatable, Sendable {
    public var text: String
    public var at: Double?
    public init(text: String, at: Double? = nil) { self.text = text; self.at = at }
}

public struct DetailMeta: Equatable, Sendable {
    public var model: String?
    public var effort: Effort?
    public var startedAt: Double?
    public var lastAt: Double?
    public var cwd: String?
    public var branch: String?
    public var worktree: String?
    public init(model: String? = nil, effort: Effort? = nil, startedAt: Double? = nil,
                lastAt: Double? = nil, cwd: String? = nil, branch: String? = nil, worktree: String? = nil) {
        self.model = model; self.effort = effort; self.startedAt = startedAt; self.lastAt = lastAt
        self.cwd = cwd; self.branch = branch; self.worktree = worktree
    }
}

public struct AgentDetail: Equatable, Sendable {
    public var plan: [PlanItem]
    public var files: [FileChange]
    public var commands: [CommandRun]
    public var lastMessage: String?
    public var errors: [DetailError]
    public var meta: DetailMeta
    /// Log order, newest last; capped, so the first one may be gone in a long session.
    public var prompts: [UserPrompt]
    /// What the session began with, kept even when the log is read from its tail.
    public var startPrompt: UserPrompt?
    public init(plan: [PlanItem] = [], files: [FileChange] = [], commands: [CommandRun] = [],
                lastMessage: String? = nil, errors: [DetailError] = [], meta: DetailMeta = DetailMeta(),
                prompts: [UserPrompt] = [], startPrompt: UserPrompt? = nil) {
        self.plan = plan; self.files = files; self.commands = commands
        self.lastMessage = lastMessage; self.errors = errors; self.meta = meta
        self.prompts = prompts; self.startPrompt = startPrompt
    }
}
