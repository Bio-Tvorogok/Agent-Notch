import Darwin
import Foundation

/// A running `codex exec --json`. Scripted runs (codex-job and the like) are often `--ephemeral`:
/// no session file under ~/.codex/sessions, only the JSON event stream on stdout, redirected to a file.
/// The process tells where that file is, which folder it works in and with which model.
public struct ExecRun: Equatable, Sendable {
    public var pid: Int32
    public var log: String
    public var cwd: String?
    public var model: String?
    public var effort: Effort?
    /// Ids of the agents that started it, from its environment (see `Lineage`).
    public var parents: [String]

    public init(pid: Int32, log: String, cwd: String?, model: String?, effort: Effort?, parents: [String] = []) {
        self.pid = pid; self.log = log; self.cwd = cwd; self.model = model; self.effort = effort
        self.parents = parents
    }

    /// Nil unless the arguments are `codex exec … --json` and stdout goes to a regular file.
    static func parse(pid: Int32, args: [String], stdout: String?, env: [String] = []) -> ExecRun? {
        guard let stdout, stdout.hasPrefix("/"), !stdout.hasPrefix("/dev/"),
              let at = args.prefix(2).firstIndex(where: { ($0 as NSString).lastPathComponent == "codex" }),
              args.dropFirst(at + 1).first == "exec", args.contains("--json") else { return nil }
        var run = ExecRun(pid: pid, log: stdout, cwd: nil, model: nil, effort: nil, parents: Lineage.parents(env: env))
        var i = at + 2
        func value(_ a: String, _ names: [String]) -> String? {
            for n in names {
                if a == n, i + 1 < args.count { i += 1; return args[i] }
                if a.hasPrefix(n + "=") { return String(a.dropFirst(n.count + 1)) }
            }
            return nil
        }
        while i < args.count {
            let a = args[i]
            if let v = value(a, ["-C", "--cd"]) { run.cwd = v }
            else if let v = value(a, ["-m", "--model"]) { run.model = v }
            else if let v = value(a, ["-c", "--config"]), v.hasPrefix("model_reasoning_effort=") {
                run.effort = Effort(String(v.dropFirst("model_reasoning_effort=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
            }
            i += 1
        }
        // Resume omits -C, and relative paths belong to the running process, not this app.
        if run.cwd == nil || run.cwd?.hasPrefix("/") == false {
            run.cwd = Proc.cwd(pid).map { base in
                URL(fileURLWithPath: base).appendingPathComponent(run.cwd ?? ".").standardizedFileURL.path
            }
        }
        return run
    }

    /// Every running exec run, one per log file (the node wrapper and the native binary share stdout).
    public static func running() -> [ExecRun] {
        var out: [String: ExecRun] = [:]
        for pid in Proc.all() where ["codex", "node"].contains(Proc.name(pid)) {
            let (args, env) = Proc.argsAndEnv(pid)
            guard args.contains("exec"), let run = parse(pid: pid, args: args, stdout: Proc.stdoutPath(pid), env: env) else { continue }
            if out[run.log] == nil { out[run.log] = run }
        }
        return Array(out.values)
    }
}

/// Open rollout files identify interactive/resumed sessions; redirected stdout identifies exec runs.
public struct CodexProcess: Equatable {
    public let pid: Int32
    public let paths: [String]
    public let hasTTY: Bool

    public init(pid: Int32, paths: [String], hasTTY: Bool = false) {
        self.pid = pid
        self.hasTTY = hasTTY
        self.paths = paths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path }
    }

    static func isCLI(args: [String]) -> Bool {
        guard let at = args.prefix(2).firstIndex(where: { ($0 as NSString).lastPathComponent == "codex" }) else { return false }
        let valueOptions: Set<String> = [
            "-c", "--config", "-m", "--model", "-p", "--profile", "-s", "--sandbox",
            "-a", "--ask-for-approval", "-C", "--cd", "--add-dir", "--enable", "--disable",
            "-i", "--image", "--local-provider"
        ]
        var i = at + 1
        while i < args.count {
            let arg = args[i]
            i += 1
            if arg == "--" { return true }
            if valueOptions.contains(arg) { i += 1; continue }
            // Only the subcommand identifies the server; a prompt or option value may also say app-server.
            if !arg.hasPrefix("-") { return arg != "app-server" }
        }
        return true
    }

    public static func running() -> [CodexProcess] {
        Proc.all().sorted().compactMap { pid in
            guard ["codex", "node"].contains(Proc.name(pid)) else { return nil }
            let args = Proc.argsAndEnv(pid).0
            guard isCLI(args: args) else { return nil }
            return CodexProcess(pid: pid, paths: Proc.openPaths(pid), hasTTY: Proc.hasTTYInAncestry(pid))
        }
    }
}

/// One line of the `codex exec --json` stream. The stream has no timestamps: lines count as read now.
enum ExecLine {
    static func apply(_ r: Rec, to s: inout SessionLog, at: Double) {
        s.touch(at)
        let item = r["item"] as? Rec ?? [:]
        let id = item["id"] as? String
        switch r["type"] as? String {
        // The thread id is what this run's own children carry as CODEX_THREAD_ID.
        case "thread.started": if let t = r["thread_id"] as? String, !t.isEmpty { s.id = t }
        case "turn.started": s.turnEnded = false
        case "turn.completed", "turn.failed":
            s.turnEnded = true
            s.activity = nil
        case "item.started":
            if let id { s.pendingTools[id] = item["type"] as? String ?? "tool" }
            if let what = describe(item) { s.activity = what }
        case "item.completed":
            guard let id, s.pendingTools[id] != nil else { return }
            let code = (item["exit_code"] as? NSNumber)?.intValue
            s.toolResult(id: id, isError: (code ?? 0) != 0 || item["status"] as? String == "failed")
        default: break
        }
    }

    static func describe(_ item: Rec) -> String? {
        switch item["type"] as? String {
        case "command_execution":
            return ToolText.join("shell", (item["command"] as? String).flatMap { ToolText.command(unwrapShell($0)) })
        case "file_change":
            let paths = (item["changes"] as? [Rec] ?? []).compactMap { ($0["path"] as? String).map { ($0 as NSString).lastPathComponent } }
            return ToolText.join("patch", paths.joined(separator: ", ").nilIfEmpty)
        case "mcp_tool_call": return item["tool"] as? String
        case "web_search": return ToolText.join("search", LogText.clip(item["query"] as? String, 80))
        default: return nil
        }
    }

    /// `/bin/zsh -lc 'cat README.md'` → `cat README.md`.
    static func unwrapShell(_ cmd: String) -> String {
        cmd.firstMatch(#"(?s)^\S*sh\s+-l?c\s+'(.*)'\s*$"#) ?? cmd.firstMatch(#"(?s)^\S*sh\s+-l?c\s+"(.*)"\s*$"#)
            ?? cmd.firstMatch(#"(?s)^\S*sh\s+-l?c\s+([^'"\s].*)$"#) ?? cmd
    }
}

/// Reading other processes of the same user: pid list, name, argv and open files.
enum Proc {
    /// Rollout thread → inherited parent ids, including detached exec runs and interactive sessions.
    static func rolloutParents(in root: URL) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for pid in all() where name(pid) == "codex" {
            let parents = Lineage.parents(env: argsAndEnv(pid).1)
            guard !parents.isEmpty else { continue }
            for path in openPaths(pid) {
                guard let id = rolloutThread(path, in: root) else { continue }
                for parent in parents where !out[id, default: []].contains(parent) {
                    out[id, default: []].append(parent)
                }
            }
        }
        return out
    }

    static func rolloutThread(_ path: String, in root: URL) -> String? {
        let file = URL(fileURLWithPath: path).standardizedFileURL
        let base = file.deletingPathExtension().lastPathComponent
        guard file.path.hasPrefix(root.standardizedFileURL.path + "/"), file.pathExtension == "jsonl",
              base.hasPrefix("rollout-"), base.count > 36,
              base[base.index(base.endIndex, offsetBy: -37)] == "-" else { return nil }
        let id = String(base.suffix(36))
        return UUID(uuidString: id) == nil ? nil : id
    }

    static func openPaths(_ pid: Int32) -> [String] {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / stride + 32)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * stride))
        guard got > 0 else { return [] }
        return fds.prefix(Int(got) / stride).compactMap { fd in
            guard fd.proc_fdtype == PROX_FDTYPE_VNODE else { return nil }
            return vnodePath(pid, fd: fd.proc_fd)
        }
    }

    static func all() -> [Int32] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(n) + 64)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        return Array(pids.prefix(Int(max(got, 0)))).filter { $0 > 0 }
    }

    static func name(_ pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buf, UInt32(buf.count))
        return String(cString: buf)
    }

    /// argv and the environment from KERN_PROCARGS2: argc, the exec path, padding, argc strings, then the environment.
    static func argsAndEnv(_ pid: Int32) -> ([String], [String]) {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return ([], []) }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > 4 else { return ([], []) }
        let argc = buf.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        var i = 4
        while i < size && buf[i] != 0 { i += 1 }
        while i < size && buf[i] == 0 { i += 1 }
        var args: [String] = [], env: [String] = []
        while i < size {
            let start = i
            while i < size && buf[i] != 0 { i += 1 }
            if start == i { break }
            let s = String(decoding: buf[start..<i], as: UTF8.self)
            if args.count < argc { args.append(s) } else { env.append(s) }
            i += 1
        }
        return (args, env)
    }

    static func hasTTYInAncestry(_ pid: Int32) -> Bool {
        var current = pid
        var seen: Set<Int32> = []
        while current > 1, seen.count < 128, seen.insert(current).inserted {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
            if info.e_tdev != UInt32.max { return true }
            current = Int32(info.pbi_ppid)
        }
        return false
    }

    static func stdoutPath(_ pid: Int32) -> String? {
        vnodePath(pid, fd: 1)
    }

    private static func vnodePath(_ pid: Int32, fd: Int32) -> String? {
        var info = vnode_fdinfowithpath()
        let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
        guard proc_pidfdinfo(pid, fd, PROC_PIDFDVNODEPATHINFO, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvip.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return path.isEmpty ? nil : path
    }

    static func cwd(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return path.isEmpty ? nil : path
    }
}
