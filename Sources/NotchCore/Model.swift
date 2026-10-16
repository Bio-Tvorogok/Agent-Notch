import Foundation

public enum Vendor: String, Sendable { case claude, codex }

/// Ordered by urgency: a project or session shows its most urgent state.
public enum AgentState: Int, Comparable, Sendable {
    case error, waiting, working, done
    public static func < (a: AgentState, b: AgentState) -> Bool { a.rawValue < b.rawValue }
    public var needsAttention: Bool { self == .error || self == .waiting }
    public var isLive: Bool { self != .done }
}

public enum Effort: Int, Sendable {
    case low = 1, medium, high, xhigh

    public init?(_ raw: String?) {
        switch raw?.lowercased() {
        case "low", "minimal": self = .low
        case "medium": self = .medium
        case "high": self = .high
        case "xhigh", "max": self = .xhigh
        default: return nil
        }
    }
}

public struct Agent: Identifiable, Equatable, Sendable {
    public var id: String
    public var vendor: Vendor
    public var title: String
    public var model: String?
    public var effort: Effort?
    public var state: AgentState
    public var project: String
    public var parentId: String?
    public var ask: String?
    public var startedAt: Double
    /// Working directory, for resuming the chat in a terminal.
    public var cwd: String?
    /// The session whose chat opens for this agent: a subagent has none of its own, so its parent's.
    public var chatId: String?
    /// What it is doing right now: "Bash · pnpm test".
    public var activity: String?
    /// The session log this row comes from: details, usage and the "open" target are read from it.
    public var logPath: String?
    public var branch: String?
    public var worktree: String?
    public var lastAt: Double = 0
    var turnActivityAt: Double?
    var promptAt: Double?
    public var turnEnded = false
    public var interrupted = false
    /// Process exit is weaker evidence than an explicit abort or a successful Stop.
    var interruptionInferred = false
    /// Later hook or descendant activity extends retention without changing this log's time.
    var retentionAt: Double = 0
    var retainedAt: Double { max(lastAt, retentionAt) }
    /// A real question or approval, rather than the process waiting for its next prompt.
    public var hasPendingAsk = false
    public var helperCount = 0

    /// haiku, luna and *-mini models draw as rings, the rest as solid marks.
    public var isLight: Bool {
        guard let m = model?.lowercased() else { return false }
        return m.contains("haiku") || m.contains("luna") || m.contains("mini")
    }

    /// "claude-opus-4-7" → "opus 4.7", "gpt-6.1-sol" → "sol 6.1".
    public var shortModel: String? {
        guard let m = model?.lowercased(), !m.isEmpty else { return nil }
        for family in ["opus", "sonnet", "haiku", "fable", "sol", "luna", "astra"] where m.contains(family) {
            return family
        }
        return m.replacingOccurrences(of: "claude-", with: "").replacingOccurrences(of: "gpt-", with: "")
    }

    public init(id: String, vendor: Vendor, title: String, model: String? = nil, effort: Effort? = nil,
                state: AgentState, project: String, parentId: String? = nil, ask: String? = nil, startedAt: Double = 0,
                cwd: String? = nil, chatId: String? = nil, activity: String? = nil, logPath: String? = nil,
                branch: String? = nil, worktree: String? = nil) {
        self.id = id; self.vendor = vendor; self.title = title; self.model = model; self.effort = effort
        self.state = state; self.project = project; self.parentId = parentId; self.ask = ask; self.startedAt = startedAt
        self.branch = branch; self.worktree = worktree
        self.hasPendingAsk = ask != nil
        self.cwd = cwd; self.chatId = chatId; self.activity = activity; self.logPath = logPath
    }
}
