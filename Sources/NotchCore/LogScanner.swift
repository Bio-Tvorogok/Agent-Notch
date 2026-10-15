import Foundation

/// Finds recently written Claude Code and Codex session logs under a home folder and tails them.
/// Read-only. Not thread-safe: call `poll` from one serial queue.
public final class LogScanner: @unchecked Sendable {
    private struct Tracked {
        var log: SessionLog
        let initial: SessionLog
        var offset: UInt64
        var isSubagent: Bool
        /// A `codex exec --json` event stream rather than a session file.
        var isExec = false
        var device: dev_t?
        var inode: ino_t?

        init(log: SessionLog, offset: UInt64, isSubagent: Bool, isExec: Bool = false, initial: SessionLog? = nil) {
            self.log = log
            self.initial = initial ?? log
            self.offset = offset
            self.isSubagent = isSubagent
            self.isExec = isExec
        }
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
    private let rolloutParents: () -> [String: [String]]
    /// Keep ancestry after the process exits and across log resets.
    private var threadParents: [String: [String]] = [:]
    /// Exec logs whose process was running at the last discovery.
    private var execAlive: Set<String> = []

    /// A file not written for this long is neither picked up nor kept.
    public static let window: Double = SessionLog.keepDone
    /// First read of a long log starts this far from its end.
    static let tailBytes: UInt64 = 2 << 20

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, execRuns: @escaping () -> [ExecRun] = ExecRun.running,
                rolloutParents: (() -> [String: [String]])? = nil) {
        self.execRuns = execRuns
        claudeRoot = home.appendingPathComponent(".claude/projects")
        claudeSessions = home.appendingPathComponent(".claude/sessions")
        codexRoot = home.appendingPathComponent(".codex/sessions")
        let root = codexRoot
        self.rolloutParents = rolloutParents ?? { Proc.rolloutParents(in: root) }
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
            if let f = files[path], f.log.vendor == .codex, !f.isExec {
                files[path]?.log.parentCandidates = threadParents[f.log.id] ?? []
            }
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
        let threads = Set(files.values.filter { $0.log.vendor == .codex }.map { $0.log.id })
        threadParents = threadParents.filter { threads.contains($0.key) }
        // A retained exec thread has both a rollout and a stdout stream. Keep the rollout for
        // prompts, approvals and resuming; the stream still supplies its process ancestry.
        let logs = Dictionary(grouping: files.values, by: { "\($0.log.vendor.rawValue):\($0.log.id)" }).values.map { sources in
            let ordered = sources.sorted { a, b in
                if a.isExec != b.isExec { return !a.isExec }
                if a.log.live?.alive != b.log.live?.alive { return a.log.live?.alive == true }
                if a.log.lastAt != b.log.lastAt { return a.log.lastAt > b.log.lastAt }
                return (a.log.path ?? "") < (b.log.path ?? "")
            }
            var log = ordered[0].log
            if !ordered[0].isExec, let exec = ordered.first(where: { $0.isExec }) {
                let busy = exec.log.live?.alive == true && !exec.log.turnEnded
                let laterTurn = log.turnStartedAt.map { $0 > mtime(exec.log.path ?? "") } ?? false
                if busy || !laterTurn {
                    log.live = exec.log.live
                    log.lastAt = max(log.lastAt, exec.log.lastAt)
                    if log.ask != nil, busy { log.live?.status = "waiting" }
                }
            }
            for source in ordered {
                log.model = log.model ?? source.log.model
                log.effort = log.effort ?? source.log.effort
                for parent in source.log.parentCandidates where !log.parentCandidates.contains(parent) {
                    log.parentCandidates.append(parent)
                }
            }
            return log
        }
        var agents = logs.compactMap { $0.agent(now: t, finishedRetention: finishedRetention, project: names.name(for:)) }
        let candidates = Dictionary(logs.filter { !$0.parentCandidates.isEmpty }.map { ($0.id, $0.parentCandidates) },
                                    uniquingKeysWith: { a, _ in a })
        let picked = Lineage.resolve(candidates, known: Set(agents.map(\.id)))
        for i in agents.indices where agents[i].parentId == nil { agents[i].parentId = picked[agents[i].id] }
        return agents
    }

    // MARK: discovery

    private func discover(now: Double, window: Double) {
        let fresh = now - window
        for (id, parents) in rolloutParents() {
            for parent in parents where !threadParents[id, default: []].contains(parent) {
                threadParents[id, default: []].append(parent)
            }
        }
        let runs = execRuns()
        execAlive = Set(runs.map(\.log))
        for run in runs where files[run.log] == nil { track(exec: run) }
        for project in children(claudeRoot) {
            let items = children(project)
            let dates = Dictionary(uniqueKeysWithValues: items.filter { $0.pathExtension == "jsonl" }.map {
                ($0.lastPathComponent, mtime($0))
            })
            for item in items {
                if item.pathExtension == "jsonl" {
                    if files[item.path] == nil, (dates[item.lastPathComponent] ?? 0) > fresh { track(claude: item, parent: nil) }
                } else if (dates[item.lastPathComponent + ".jsonl"] ?? 0) > now - 86_400 {
                    for sub in subagentLogs(in: item) where files[sub.path] == nil && mtime(sub) > fresh {
                        track(claude: sub, parent: item.lastPathComponent)
                    }
                }
            }
        }
        for day in [now, now - 86_400] {
            let c = Calendar.current.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: day))
            let dir = codexRoot.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
            for f in children(dir) where f.pathExtension == "jsonl" && files[f.path] == nil && mtime(f) > fresh {
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
        log.path = file.path
        let initial = log
        // The thread's identity and parent live in the first line, which a tail read would skip.
        if let first = firstLine(file.path), let r = try? JSONSerialization.jsonObject(with: first) as? Rec {
            CodexLine.apply(r, to: &log)
        }
        files[file.path] = Tracked(log: log, offset: startOffset(file.path), isSubagent: false, initial: initial)
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
        // A bounded tail can skip thread.started; identity must survive long exec streams.
        if let first = firstLine(run.log), let r = try? JSONSerialization.jsonObject(with: first) as? Rec,
           r["type"] as? String == "thread.started", let id = r["thread_id"] as? String, !id.isEmpty {
            log.id = id
        }
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
        var info = stat()
        guard fstat(h.fileDescriptor, &info) == 0 else { return }
        let size = UInt64(max(0, info.st_size))
        if size < f.offset || (f.inode != nil && (f.inode != info.st_ino || f.device != info.st_dev)) {
            f.log = f.initial
            f.offset = size > Self.tailBytes ? size - Self.tailBytes : 0
            if f.log.vendor == .codex, let first = firstLine(path),
               let r = try? JSONSerialization.jsonObject(with: first) as? Rec {
                if f.isExec { ExecLine.apply(r, to: &f.log, at: now) }
                else { CodexLine.apply(r, to: &f.log) }
            }
        }
        f.inode = info.st_ino
        f.device = info.st_dev
        files[path] = f
        guard (try? h.seek(toOffset: f.offset)) != nil, let data = try? h.readToEnd(), !data.isEmpty else { return }
        // A tail read may start mid-line: that fragment fails to parse and is skipped like any bad line.
        var consumed = 0
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            while consumed < raw.count, let newline = memchr(base.advanced(by: consumed), 0x0A, raw.count - consumed) {
                let end = base.distance(to: UnsafeRawPointer(newline))
                let line = data[(data.startIndex + consumed)..<(data.startIndex + end)]
                if let r = try? JSONSerialization.jsonObject(with: line) as? Rec {
                    switch f.log.vendor {
                    case .claude: ClaudeLine.apply(r, to: &f.log, isSubagent: f.isSubagent)
                    case .codex where f.isExec: ExecLine.apply(r, to: &f.log, at: now)
                    case .codex: CodexLine.apply(r, to: &f.log)
                    }
                }
                consumed = end + 1
            }
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
        (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
    }

    private func mtime(_ path: String) -> Double {
        mtime(URL(fileURLWithPath: path))
    }

    private func mtime(_ url: URL) -> Double {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
    }
}
