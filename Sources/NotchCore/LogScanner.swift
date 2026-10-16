import Foundation

/// Finds recently written Claude Code and Codex session logs under a home folder and tails them.
/// Read-only. Overlapping polls share one pending scan; only its owner returns a snapshot.
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
        var modified: Double = 0
        let physicalPath: String

        init(log: SessionLog, offset: UInt64, isSubagent: Bool, isExec: Bool = false, initial: SessionLog? = nil) {
            self.log = log
            physicalPath = log.path.map { ConfigRoots.physical(URL(fileURLWithPath: $0)).path } ?? ""
            self.initial = initial ?? log
            self.offset = offset
            self.isSubagent = isSubagent
            self.isExec = isExec
        }
    }

    // Observers report actual I/O without replacing filesystem operations.
    var didRead: ((Int) -> Void)?
    var didStat: ((String) -> Void)?
    var didList: ((String) -> Void)?

    private var claudeRoot: URL
    private var claudeSessions: URL
    private var codexRoot: URL
    private let config: ConfigRoots
    private let names = ProjectNames()
    private let fm = FileManager.default
    private var files: [String: Tracked] = [:]
    private let scanLock = NSLock()
    private var scanning = false
    private var pending: (Date, Double, FileChanges?)?
    private var liveFiles: [String: (String, ClaudeLive)] = [:]
    private var runs: [ExecRun] = []
    private struct DirectoryStamp: Equatable {
        let modified: Date
        let inode: UInt64
        let device: UInt64
    }
    private var codexDirectories: [String: (DirectoryStamp, [URL])] = [:]
    private var codexDays: [String: (newest: Double, checked: Double)] = [:]
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
        config = ConfigRoots(home: home)
        claudeRoot = ConfigRoots.physical(ConfigRoots(home: home).logs(.claude))
        claudeSessions = ConfigRoots.physical(ConfigRoots(home: home).root(.claude).appendingPathComponent("sessions"))
        codexRoot = ConfigRoots.physical(ConfigRoots(home: home).logs(.codex))
        let root = ConfigRoots(home: home).logs(.codex)
        self.rolloutParents = rolloutParents ?? { Proc.rolloutParents(in: ConfigRoots.physical(root)) }
    }

    /// Roots include configured locations even when they do not exist yet.
    public var watchPaths: [String] {
        // Keep logical config entries as well as independently symlinked log/status directories.
        ([config.root(.claude).path, config.root(.codex).path,
          claudeRoot.path, claudeSessions.path, codexRoot.path] +
            Set(runs.map { URL(fileURLWithPath: $0.log).deletingLastPathComponent().path }).sorted()).sorted()
    }

    public func poll(now: Date = Date(), finishedRetention: Double = SessionLog.keepDone,
                     changes: FileChanges? = nil) -> [Agent]? {
        scanLock.lock()
        if scanning {
            let merged: FileChanges?
            if let old = pending { merged = (old.2 ?? .full).merging(changes ?? .full) }
            else { merged = changes }
            pending = (now, finishedRetention, merged)
            scanLock.unlock()
            return nil
        }
        scanning = true
        scanLock.unlock()
        var request = (now, finishedRetention, changes)
        while true {
            let result = scan(now: request.0, finishedRetention: request.1, changes: request.2)
            scanLock.lock()
            if let next = pending {
                pending = nil
                scanLock.unlock()
                request = next
            } else {
                scanning = false
                scanLock.unlock()
                return result
            }
        }
    }

    private func scan(now: Date, finishedRetention: Double, changes: FileChanges?) -> [Agent] {
        let t = now.timeIntervalSince1970
        let window = max(finishedRetention, SessionLog.longTool, 3_600)
        var changed = changes?.changedPaths.map { Set($0.map { ConfigRoots.physical(URL(fileURLWithPath: $0)).path }) }
        var full = changes == .full
        if full || changed?.isEmpty == false {
            let claude = ConfigRoots.physical(config.logs(.claude))
            let codex = ConfigRoots.physical(config.logs(.codex))
            let sessions = ConfigRoots.physical(config.root(.claude).appendingPathComponent("sessions"))
            if claude.path != claudeRoot.path || codex.path != codexRoot.path || sessions.path != claudeSessions.path {
                claudeRoot = claude
                codexRoot = codex
                claudeSessions = sessions
                files = files.filter { $0.value.isExec }
                full = true
            }
        }
        if full { changed = nil }
        if full {
            // A safety/drop scan must not trust directory stamps or cold-day caches.
            codexDirectories.removeAll()
            codexDays.removeAll()
        }
        if full || (changes == nil && (t - lastDiscovery >= 5 || lastRetention != finishedRetention)) {
            lastDiscovery = t
            lastRetention = finishedRetention
            discover(now: t, window: window)
        } else if let changed {
            discoverChanged(changed, now: t, window: window)
        }
        if changes?.refreshProcesses == true, !full {
            let previous = Set(runs.map(\.log))
            discoverProcesses()
            // Process exit may beat the delayed FSEvents delivery. Drain stdout before unwatching it.
            changed?.formUnion(previous.union(runs.map(\.log)).map { ConfigRoots.physical(URL(fileURLWithPath: $0)).path })
        }
        if changed == nil || changed?.contains(where: { contains($0, claudeSessions.path) }) == true {
            liveFiles.removeAll()
            for file in children(claudeSessions) where file.pathExtension == "json" { refreshLive(file) }
        } else if let changed {
            for path in changed where contains(claudeSessions.path, path) {
                let url = URL(fileURLWithPath: path)
                if url.pathExtension == "json" { refreshLive(url) }
                else {
                    liveFiles = liveFiles.filter { !contains(path, $0.key) }
                    for file in children(url) where file.pathExtension == "json" { refreshLive(file) }
                }
            }
        }
        // No directory listing or JSON parsing on liveness-only ticks.
        for path in Array(liveFiles.keys) {
            if let pid = liveFiles[path]?.1.pid { liveFiles[path]?.1.alive = pid > 0 && ClaudeLive.isRunning(pid) }
        }
        let live = Dictionary(liveFiles.values.map { ($0.0, $0.1) }, uniquingKeysWith: { a, b in a.alive ? a : b })
        execAlive = Set(runs.filter { ClaudeLive.isRunning($0.pid) }.map(\.log))
        for path in Array(files.keys) {
            if changed == nil || changed!.contains(where: { contains($0, path) || contains($0, files[path]?.physicalPath ?? path) }) || files[path]?.inode == nil {
                read(path, now: t)
            }
            if let f = files[path], f.log.vendor == .codex, !f.isExec {
                files[path]?.log.parentCandidates = threadParents[f.log.id] ?? []
            }
            if let f = files[path], f.log.vendor == .claude {
                let l = live[f.log.parentId ?? f.log.id]
                files[path]?.log.live = l
                if f.log.parentId == nil, let pid = l?.pid, pid > 0, l?.alive == true { files[path]?.log.parentCandidates = parents(of: pid) }
            }
            if let f = files[path], f.isExec {
                // Legacy callers inject process snapshots; event callers check the cached pids.
                let alive = changes == nil ? runs.contains { $0.log == path } : execAlive.contains(path)
                files[path]?.log.live = ClaudeLive(status: f.log.turnEnded ? "idle" : "busy", waitingFor: nil, name: nil, alive: alive)
            }
        }
        files = files.filter { _, f in
            f.log.state(now: t, finishedRetention: finishedRetention) != nil || f.modified > t - window
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
                let laterTurn = log.turnStartedAt.map { $0 > exec.modified } ?? false
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
        discoverProcesses()
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
        var visited: Set<String> = []
        func directories(_ dir: URL, digits: Int) -> [URL] {
            visited.insert(dir.path)
            return codexChildren(dir, now: now).filter {
                $0.lastPathComponent.count == digits && $0.lastPathComponent.allSatisfy(\.isNumber)
            }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        for year in directories(codexRoot, digits: 4) {
            for month in directories(year, digits: 2) {
                for day in directories(month, digits: 2) {
                    visited.insert(day.path)
                    let previous = codexDirectories[day.path]
                    let items = codexChildren(day, now: now)
                    let changed = previous?.0 != codexDirectories[day.path]?.0 || previous?.1 != items
                    let date = day.lastPathComponent
                    let monthPath = day.deletingLastPathComponent()
                    let key = monthPath.deletingLastPathComponent().lastPathComponent + "/" + monthPath.lastPathComponent + "/" + date
                    let calendar = Calendar.current
                    let current = Date(timeIntervalSince1970: now)
                    let recentDays = [current, calendar.date(byAdding: .day, value: -1, to: current)!].map {
                        let c = calendar.dateComponents([.year, .month, .day], from: $0)
                        return String(format: "%04d/%02d/%02d", c.year!, c.month!, c.day!)
                    }
                    // Appends leave directory mtimes unchanged. Revisit cold folders within 60s.
                    if let cached = codexDays[day.path], !changed, !recentDays.contains(key),
                       cached.newest <= fresh, now - cached.checked < 55 { continue }
                    var newest: Double = 0
                    for file in items where file.pathExtension == "jsonl" {
                        let modified = mtime(file.path)
                        newest = max(newest, modified)
                        if modified > fresh, files[file.path] == nil { track(codex: file) }
                    }
                    codexDays[day.path] = (newest, now)
                }
            }
        }
        codexDirectories = codexDirectories.filter { visited.contains($0.key) }
        codexDays = codexDays.filter { visited.contains($0.key) }
    }

    private func discoverProcesses() {
        for (id, parents) in rolloutParents() {
            for parent in parents where !threadParents[id, default: []].contains(parent) {
                threadParents[id, default: []].append(parent)
            }
        }
        runs = execRuns()
        execAlive = Set(runs.map(\.log))
        for run in runs where files[run.log] == nil { track(exec: run) }
    }

    private func contains(_ root: String, _ path: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    private func refreshLive(_ file: URL) {
        liveFiles[file.path] = ClaudeLive.readFile(file)
    }

    /// An event for a directory visits only that subtree; a file event never lists its siblings.
    private func discoverChanged(_ paths: Set<String>, now: Double, window: Double) {
        func visit(_ url: URL) {
            let path = url.path
            guard contains(claudeRoot.path, path) || contains(codexRoot.path, path) else { return }
            if url.pathExtension == "jsonl" {
                guard files[path] == nil, mtime(path) > now - window else { return }
                if contains(codexRoot.path, path) { track(codex: url) }
                else {
                    let parts = Array(url.pathComponents.dropFirst(claudeRoot.pathComponents.count))
                    if parts.count == 2 { track(claude: url, parent: nil) }
                    else if parts.count >= 4, parts[2] == "subagents", url.lastPathComponent.hasPrefix("agent-") {
                        track(claude: url, parent: parts[1])
                    }
                }
            } else {
                var directory: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &directory), directory.boolValue {
                    for child in children(url) { visit(child) }
                }
            }
        }
        for path in paths {
            if contains(path, claudeRoot.path) { visit(claudeRoot) }
            else if contains(path, codexRoot.path) { visit(codexRoot) }
            else { visit(URL(fileURLWithPath: path)) }
        }
    }

    private func codexChildren(_ dir: URL, now: Double) -> [URL] {
        didStat?(dir.path)
        guard let attributes = try? fm.attributesOfItem(atPath: dir.path),
              let modified = attributes[.modificationDate] as? Date,
              let inode = attributes[.systemFileNumber] as? UInt64,
              let device = attributes[.systemNumber] as? UInt64 else {
            codexDirectories.removeValue(forKey: dir.path)
            return []
        }
        let stamp = DirectoryStamp(modified: modified, inode: inode, device: device)
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: now))
        let today = String(format: "/%04d/%02d/%02d", c.year!, c.month!, c.day!)
        if !dir.path.hasSuffix(today), modified.timeIntervalSince1970 < now - 2,
           let cached = codexDirectories[dir.path], cached.0 == stamp { return cached.1 }
        didList?(dir.path)
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            codexDirectories.removeValue(forKey: dir.path)
            return []
        }
        codexDirectories[dir.path] = (stamp, items)
        return items
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
        didStat?(path)
        guard fstat(h.fileDescriptor, &info) == 0 else { return }
        let size = UInt64(max(0, info.st_size))
        if size < f.offset || (f.inode != nil && (f.inode != info.st_ino || f.device != info.st_dev)) {
            f.log = f.initial
            if f.log.vendor == .codex, let first = firstLine(h, chunkBytes: 1),
               let r = try? JSONSerialization.jsonObject(with: first) as? Rec {
                if f.isExec { ExecLine.apply(r, to: &f.log, at: now) }
                else { CodexLine.apply(r, to: &f.log) }
            }
            f.offset = size > Self.tailBytes ? size - Self.tailBytes : 0
        }
        f.modified = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
        f.inode = info.st_ino
        f.device = info.st_dev
        files[path] = f
        guard (try? h.seek(toOffset: f.offset)) != nil, let data = try? h.read(upToCount: Int(size - f.offset)), !data.isEmpty else { return }
        didRead?(data.count)
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
        didStat?(path)
        let size = (try? fm.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
        return size > Self.tailBytes ? size - Self.tailBytes : 0
    }

    private func firstLine(_ path: String) -> Data? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        return firstLine(h, chunkBytes: 64 << 10)
    }

    private func firstLine(_ h: FileHandle, chunkBytes: Int) -> Data? {
        guard (try? h.seek(toOffset: 0)) != nil else { return nil }
        var buf = Data()
        // Resets read exactly through the newline; discovery keeps its chunked reads.
        while buf.count < 1 << 20, let chunk = try? h.read(upToCount: chunkBytes), !chunk.isEmpty {
            didRead?(chunk.count)
            if let nl = chunk.firstIndex(of: 0x0A) { return buf + chunk[..<nl] }
            buf += chunk
        }
        return buf.isEmpty ? nil : buf
    }

    private func children(_ dir: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
    }

    private func mtime(_ path: String) -> Double {
        didStat?(path)
        var info = stat()
        guard stat(path, &info) == 0 else { return 0 }
        return Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
    }

    private func mtime(_ url: URL) -> Double {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
    }
}
