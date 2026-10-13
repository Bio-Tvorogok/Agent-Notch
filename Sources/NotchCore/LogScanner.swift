import Foundation

/// Finds recently written Claude Code and Codex session logs under a home folder and tails them.
/// Read-only. Not thread-safe: call `poll` from one serial queue.
public final class LogScanner: @unchecked Sendable {
    private struct Tracked {
        var log: SessionLog
        var offset: UInt64
        var isSubagent: Bool
        /// A `codex exec --json` event stream rather than a session file.
        var isExec = false
    }

    private let claudeRoot: URL
    private let claudeSessions: URL
    private let codexRoot: URL
    private let names = ProjectNames()
    private let fm = FileManager.default
    private var files: [String: Tracked] = [:]
    private var lastDiscovery: Double = 0
    private var lastRetention: Double?
    private let execRuns: () -> [ExecRun]
    /// Exec logs whose process was running at the last discovery.
    private var execAlive: Set<String> = []

    /// A file not written for this long is neither picked up nor kept.
    public static let window: Double = SessionLog.keepDone
    /// First read of a long log starts this far from its end.
    static let tailBytes: UInt64 = 2 << 20

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, execRuns: @escaping () -> [ExecRun] = ExecRun.running) {
        self.execRuns = execRuns
        claudeRoot = home.appendingPathComponent(".claude/projects")
        claudeSessions = home.appendingPathComponent(".claude/sessions")
        codexRoot = home.appendingPathComponent(".codex/sessions")
    }

    public func poll(now: Date = Date(), finishedRetention: Double = SessionLog.keepDone) -> [Agent] {
        let t = now.timeIntervalSince1970
        // Retention affects finished rows, never the lifetime of a waiting request or a running tool.
        let window = max(finishedRetention, SessionLog.longTool, 3_600)
        if t - lastDiscovery >= 5 || lastRetention != finishedRetention {
            lastDiscovery = t
            lastRetention = finishedRetention
            discover(now: t, window: window)
        }
        let live = ClaudeLive.read(claudeSessions)
        for path in Array(files.keys) {
            read(path, now: t)
            if let f = files[path], f.log.vendor == .claude {
                let l = live[f.log.parentId ?? f.log.id]
                files[path]?.log.live = l
                if f.log.parentId == nil, let pid = l?.pid, pid > 0, l?.alive == true { files[path]?.log.parentCandidates = parents(of: pid) }
            }
            if let f = files[path], f.isExec {
                // The process is the only sign of life: no session status file, no timestamps in the stream.
                let alive = execAlive.contains(path)
                files[path]?.log.live = ClaudeLive(status: f.log.turnEnded ? "idle" : "busy", waitingFor: nil, name: nil, alive: alive)
            }
        }
        files = files.filter { path, f in
            f.log.state(now: t, finishedRetention: finishedRetention) != nil || mtime(path) > t - window
        }
        var agents = files.values.compactMap { $0.log.agent(now: t, finishedRetention: finishedRetention, project: names.name(for:)) }
        let candidates = Dictionary(files.values.filter { !$0.log.parentCandidates.isEmpty }.map { ($0.log.id, $0.log.parentCandidates) },
                                    uniquingKeysWith: { a, _ in a })
        let picked = Lineage.resolve(candidates, known: Set(agents.map(\.id)))
        for i in agents.indices where agents[i].parentId == nil { agents[i].parentId = picked[agents[i].id] }
        return agents
    }

    // MARK: discovery

    private func discover(now: Double, window: Double) {
        let fresh = now - window
        let runs = execRuns()
        execAlive = Set(runs.map(\.log))
        for run in runs where files[run.log] == nil { track(exec: run) }
        for project in children(claudeRoot) {
            for item in children(project) {
                if item.pathExtension == "jsonl" {
                    if files[item.path] == nil, mtime(item.path) > fresh { track(claude: item, parent: nil) }
                } else if mtime(project.appendingPathComponent(item.lastPathComponent + ".jsonl").path) > now - 86_400 {
                    for sub in subagentLogs(in: item) where files[sub.path] == nil && mtime(sub.path) > fresh {
                        track(claude: sub, parent: item.lastPathComponent)
                    }
                }
            }
        }
        for day in [now, now - 86_400] {
            let c = Calendar.current.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: day))
            let dir = codexRoot.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
            for f in children(dir) where f.pathExtension == "jsonl" && files[f.path] == nil && mtime(f.path) > fresh {
                track(codex: f)
            }
        }
    }

    private func subagentLogs(in session: URL) -> [URL] {
        let dir = session.appendingPathComponent("subagents")
        let direct = children(dir).filter { $0.lastPathComponent.hasPrefix("agent-") && $0.pathExtension == "jsonl" }
        let workflows = children(dir.appendingPathComponent("workflows")).flatMap { run in
            children(run).filter { $0.lastPathComponent.hasPrefix("agent-") && $0.pathExtension == "jsonl" }
        }
        return direct + workflows
    }

    private func track(claude file: URL, parent: String?) {
        let base = file.deletingPathExtension().lastPathComponent
        var log: SessionLog
        if let parent {
            let meta = try? Data(contentsOf: file.deletingPathExtension().appendingPathExtension("meta.json"))
            let agentId = String(base.dropFirst("agent-".count))
            log = SessionLog(id: "\(parent)/\(agentId)", vendor: .claude, parentId: parent,
                             subTitle: ClaudeLine.subagentTitle(meta: meta))
        } else {
            log = SessionLog(id: base, vendor: .claude)
        }
        log.path = file.path
        files[file.path] = Tracked(log: log, offset: startOffset(file.path), isSubagent: parent != nil)
    }

    private func track(codex file: URL) {
        var log = SessionLog(id: file.deletingPathExtension().lastPathComponent, vendor: .codex)
        // The thread's identity and parent live in the first line, which a tail read would skip.
        if let first = firstLine(file.path), let r = try? JSONSerialization.jsonObject(with: first) as? Rec {
            CodexLine.apply(r, to: &log)
        }
        log.path = file.path
        files[file.path] = Tracked(log: log, offset: startOffset(file.path), isSubagent: false)
    }

    private func track(exec run: ExecRun) {
        // Under a parent from another project the row says which project it works in.
        let folder = run.cwd.map { ($0 as NSString).lastPathComponent }
        let project = names.name(for: run.cwd)
        let title = folder == nil || folder == project ? project : "\(project) · \(folder ?? "")"
        var log = SessionLog(id: "exec:" + (run.log as NSString).lastPathComponent, vendor: .codex, subTitle: title)
        log.parentCandidates = run.parents
        log.resumable = false
        log.cwd = run.cwd
        log.model = run.model
        log.effort = run.effort
        log.path = run.log
        files[run.log] = Tracked(log: log, offset: startOffset(run.log), isSubagent: false, isExec: true)
    }

    /// A process's environment does not change: read it once per pid.
    private var envParents: [Int32: [String]] = [:]
    private func parents(of pid: Int32) -> [String] {
        if let known = envParents[pid] { return known }
        let found = Lineage.parents(env: Proc.argsAndEnv(pid).1)
        envParents[pid] = found
        return found
    }

    // MARK: reading

    private func read(_ path: String, now: Double) {
        guard var f = files[path], let h = FileHandle(forReadingAtPath: path) else { return }
        defer { try? h.close() }
        guard (try? h.seek(toOffset: f.offset)) != nil, let data = try? h.readToEnd(), !data.isEmpty else { return }
        // A tail read may start mid-line: that fragment fails to parse and is skipped like any bad line.
        var start = data.startIndex
        var consumed = 0
        while let nl = data[start...].firstIndex(of: 0x0A) {
            let line = data[start..<nl]
            if let r = try? JSONSerialization.jsonObject(with: line) as? Rec {
                switch f.log.vendor {
                case .claude: ClaudeLine.apply(r, to: &f.log, isSubagent: f.isSubagent)
                case .codex where f.isExec: ExecLine.apply(r, to: &f.log, at: now)
                case .codex: CodexLine.apply(r, to: &f.log)
                }
            }
            consumed += line.count + 1
            start = data.index(after: nl)
        }
        f.offset += UInt64(consumed)
        files[path] = f
    }

    private func startOffset(_ path: String) -> UInt64 {
        let size = (try? fm.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
        return size > Self.tailBytes ? size - Self.tailBytes : 0
    }

    private func firstLine(_ path: String) -> Data? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        var buf = Data()
        while buf.count < 1 << 20, let chunk = try? h.read(upToCount: 64 << 10), !chunk.isEmpty {
            if let nl = chunk.firstIndex(of: 0x0A) { return buf + chunk[..<nl] }
            buf += chunk
        }
        return buf.isEmpty ? nil : buf
    }

    private func children(_ dir: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }

    private func mtime(_ path: String) -> Double {
        ((try? fm.attributesOfItem(atPath: path)[.modificationDate]) as? Date)?.timeIntervalSince1970 ?? 0
    }
}
