import Foundation

/// What one session's log has said so far. Fed line by line; `agent(now:)` turns it into what the wing draws.
public struct SessionLog: Sendable {
    public var id: String
    public var vendor: Vendor
    public var parentId: String?
    public var cwd: String?
    public var branch: String?
    public var model: String?
    public var effort: Effort?
    public var startedAt: Double?
    public var lastAt: Double = 0
    /// The agent finished its turn and waits for the next prompt.
    public var turnEnded = false
    /// What it asks the human (a Codex approval, a Claude question or plan), until the next sign of life.
    public var ask: String?
    public var errorStreak = 0
    /// Not drawn at all (Codex guardian reviewers).
    public var hidden = false
    /// The last tool call of the current turn.
    public var activity: String?
    /// The Claude Code process's own status; for a subagent, its parent's.
    public var live: ClaudeLive?
    /// Where this log lives on disk.
    public var path: String?
    /// Ids of the agents that may have started this one, nearest unknown yet (see `Lineage`).
    var parentCandidates: [String] = []
    /// False for `codex exec --ephemeral` runs: they keep no session, so there is no chat to resume.
    var resumable = true

    var customTitle: String?
    var prompt: String?
    var subTitle: String?
    var pendingTools: [String: String] = [:]

    public init(id: String, vendor: Vendor, parentId: String? = nil, subTitle: String? = nil) {
        self.id = id
        self.vendor = vendor
        self.parentId = parentId
        self.subTitle = subTitle
    }

    /// Tuning: how long silence still means "working", and how long a finished agent stays on the list.
    public static let quietWorking: Double = 300
    public static let longTool: Double = 1800
    public static let keepDone: Double = 1800
    public static let stuckAfter = 3

    public func state(now: Double, finishedRetention: Double = Self.keepDone) -> AgentState? {
        if hidden { return nil }
        let age = now - lastAt
        if let live {
            // The process is gone, or (for a main session) it says outright what it is doing.
            if !live.alive { return age < finishedRetention ? .done : nil }
            if parentId == nil {
                switch live.status {
                case "waiting": return .waiting
                case "busy": return errorStreak >= Self.stuckAfter && age < Self.quietWorking ? .error : .working
                case "idle": return age < finishedRetention ? .done : nil
                default: break
                }
            }
        }
        if ask != nil && age < 3600 { return .waiting }
        if !turnEnded && errorStreak >= Self.stuckAfter && age < Self.quietWorking { return .error }
        if !turnEnded && (age < Self.quietWorking || (!pendingTools.isEmpty && age < Self.longTool)) { return .working }
        return age < finishedRetention ? .done : nil
    }

    public func agent(now: Double, finishedRetention: Double = Self.keepDone, project: (String?) -> String) -> Agent? {
        guard let state = state(now: now, finishedRetention: finishedRetention) else { return nil }
        let ask = state == .waiting && self.ask == nil ? live?.waitingText : self.ask
        return Agent(id: id, vendor: vendor, title: title, model: model, effort: effort, state: state,
                     project: project(cwd), parentId: parentId, ask: ask, startedAt: startedAt ?? lastAt,
                     cwd: cwd, chatId: resumable ? parentId ?? id : nil,
                     activity: state == .done ? nil : activity, logPath: path,
                     branch: branch, worktree: Self.worktreeName(cwd: cwd))
    }

    /// A linked checkout keeps its own folder name while sharing the project's repository.
    static func worktreeName(cwd: String?, now: Date = Date()) -> String? {
        guard let cwd else { return nil }
        return WorktreeCache.name(cwd: cwd, now: now) { findWorktreeName(cwd: cwd) }
    }

    private static func findWorktreeName(cwd: String) -> String? {
        var dir = URL(fileURLWithPath: cwd).standardized
        let fm = FileManager.default
        while dir.path != "/" {
            let git = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: git.path, isDirectory: &isDir) {
                guard !isDir.boolValue, let text = try? String(contentsOf: git, encoding: .utf8),
                      text.hasPrefix("gitdir:") else { return nil }
                let target = text.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
                let url = target.hasPrefix("/") ? URL(fileURLWithPath: target)
                    : dir.appendingPathComponent(target)
                let parts = url.standardized.pathComponents
                guard let i = parts.lastIndex(of: "worktrees"), i > 0,
                      parts[i - 1] == ".git", i + 2 == parts.count else { return nil }
                return dir.lastPathComponent
            }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    var title: String {
        if let subTitle, !subTitle.isEmpty { return subTitle }
        if let customTitle, !customTitle.isEmpty { return customTitle }
        if let name = live?.name, !name.isEmpty { return name }
        if let branch, !["dev", "main", "master", "HEAD", ""].contains(branch) { return branch }
        if let prompt { return prompt }
        return branch ?? String(id.prefix(8))
    }

    mutating func touch(_ at: Double?) {
        guard let at else { return }
        lastAt = max(lastAt, at)
        if startedAt == nil { startedAt = at }
    }

    /// Returns the finished tool's name.
    @discardableResult
    mutating func toolResult(id: String?, isError: Bool) -> String? {
        errorStreak = isError ? errorStreak + 1 : 0
        return id.flatMap { pendingTools.removeValue(forKey: $0) }
    }
}

enum LogText {
    /// First line of a prompt, without harness tags, cut to fit a list row.
    static func clip(_ text: String?, _ max: Int = 48) -> String? {
        guard var t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, !t.hasPrefix("<") else { return nil }
        t = t.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? t
        return t.count > max ? String(t.prefix(max - 1)) + "…" : t
    }

    private nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private nonisolated(unsafe) static let isoPlain = ISO8601DateFormatter()

    static func time(_ v: Any?) -> Double? {
        guard let s = v as? String else { return nil }
        return (iso.date(from: s) ?? isoPlain.date(from: s))?.timeIntervalSince1970
    }
}

public typealias Rec = [String: Any]
