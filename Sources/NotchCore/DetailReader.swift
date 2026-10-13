import Foundation

public enum DetailReader {
    /// A bounded tail keeps opening a card cheap even after a long session.
    public static func read(path: String, vendor: Vendor, agentId: String? = nil) -> AgentDetail? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        guard let size = try? h.seekToEnd() else { return nil }
        let budget: UInt64 = 8 << 20
        var state = DetailState(vendor: vendor)
        if size > budget {
            guard (try? h.seek(toOffset: 0)) != nil,
                  let header = try? h.read(upToCount: 64 << 10) else { return nil }
            for line in header.split(separator: 10).dropLast() {
                if let r = try? JSONSerialization.jsonObject(with: Data(line)) as? Rec {
                    state.metadata(r, subagent: agentId != nil)
                }
            }
        }
        let offset = size > budget ? size - (budget - (64 << 10)) : 0
        guard (try? h.seek(toOffset: offset)) != nil,
              let data = try? h.read(upToCount: Int(size - offset)) else { return nil }
        var lines = data.split(separator: 10, omittingEmptySubsequences: false)
        if offset > 0 { lines = Array(lines.dropFirst()) }
        var parsed = false
        for line in lines {
            guard let r = try? JSONSerialization.jsonObject(with: Data(line)) as? Rec else { continue }
            if vendor == .claude && agentId == nil && r["isSidechain"] as? Bool == true { continue }
            parsed = true
            state.metadata(r, subagent: agentId != nil)
            if vendor == .claude { state.claude(r) } else { state.codex(r) }
        }
        guard parsed else { return nil }
        return state.finish()
    }
}

/// Shared accumulation; vendor readers only interpret their own record shapes.
struct DetailState {
    var log: SessionLog
    var detail = AgentDetail()
    var commandIds: [String: Int] = [:]
    var failures: [String: Int] = [:]
    var rejected: Set<String> = []
    var failedCommands: Set<Int> = []
    var sessions: [String: Int] = [:]
    var fileCallId: String?
    /// Timestamp of the record being read, stamped on the files it changes.
    var fileAt: Double?
    var fileEvents: [(String?, FileChange)] = []
    var taskOrder: [String] = []
    var tasks: [String: PlanItem] = [:]
    var taskCreates: [String: PlanItem] = [:]
    var pendingTaskUpdates: [String: Rec] = [:]
    init(vendor: Vendor) { log = SessionLog(id: "", vendor: vendor) }

    mutating func metadata(_ r: Rec, subagent: Bool) {
        if log.vendor == .claude { ClaudeLine.apply(r, to: &log, isSubagent: subagent) }
        else { CodexLine.apply(r, to: &log) }
    }

    mutating func file(_ path: String?, added: Int, removed: Int) {
        guard let path, !path.isEmpty else { return }
        let full = path.hasPrefix("/") ? URL(fileURLWithPath: path).standardized.path
            : log.cwd.map { URL(fileURLWithPath: $0).appendingPathComponent(path).standardized.path } ?? path
        let entry = FileChange(path: full, added: added, removed: removed, at: fileAt)
        fileEvents.append((fileCallId, entry))
    }

    mutating func aggregate(_ change: FileChange) {
        var entry = change
        let full = change.path
        if let i = detail.files.firstIndex(where: { $0.path == full }) {
            let previous = detail.files.remove(at: i)
            entry.added += previous.added; entry.removed += previous.removed
            entry.at = [previous.at, entry.at].compactMap { $0 }.max()
        }
        detail.files.insert(entry, at: 0)
    }

    mutating func command(_ id: String?, _ text: String?, _ at: Any?) {
        guard let text, !text.isEmpty else { return }
        if let id { commandIds[id] = detail.commands.count }
        detail.commands.append(CommandRun(command: text, at: LogText.time(at)))
    }

    mutating func result(_ id: String?, ok: Bool?, text: String?) {
        if let id, let i = commandIds[id], detail.commands.indices.contains(i), let ok {
            detail.commands[i].ok = ok
        }
        if ok == false {
            if let id, !rejected.insert(id).inserted { return }
            if let id, let i = commandIds[id], !failedCommands.insert(i).inserted { return }
            if let text { error(text) }
        }
    }

    mutating func error(_ text: String) {
        let first = text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let normalized = first.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if !normalized.isEmpty { failures[normalized, default: 0] += 1 }
    }

    mutating func message(_ text: String) {
        if !text.isEmpty { detail.lastMessage = String(text.prefix(600)) }
    }

    mutating func finish() -> AgentDetail {
        for (id, entry) in fileEvents where id.map({ !rejected.contains($0) }) ?? true { aggregate(entry) }
        detail.commands = Array(detail.commands.suffix(30))
        detail.errors = failures.filter { $0.value > 1 }.map { DetailError(text: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.text < $1.text : $0.count > $1.count }
        detail.errors = Array(detail.errors.prefix(3))
        if let cwd = log.cwd {
            let base = URL(fileURLWithPath: cwd).standardized.path + "/"
            for i in detail.files.indices where detail.files[i].path.hasPrefix(base) {
                detail.files[i].path = String(detail.files[i].path.dropFirst(base.count))
            }
        }
        detail.meta = DetailMeta(model: log.model, effort: log.effort, startedAt: log.startedAt,
                                 lastAt: log.lastAt == 0 ? nil : log.lastAt, cwd: log.cwd,
                                 branch: log.branch, worktree: SessionLog.worktreeName(cwd: log.cwd))
        return detail
    }

    static func lines(_ value: Any?) -> Int {
        guard let s = value as? String, !s.isEmpty else { return 0 }
        return s.split(separator: "\n", omittingEmptySubsequences: false).count - (s.hasSuffix("\n") ? 1 : 0)
    }

    static func text(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        return (value as? [Rec])?.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    static func args(_ value: Any?) -> Rec {
        if let r = value as? Rec { return r }
        guard let s = value as? String, let data = s.data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? Rec) ?? [:]
    }
}
