import AppKit
import NotchCore

/// Opens an existing owner; failed lookups fall through without starting another agent.
enum Opener {
    private static let queue = DispatchQueue(label: "agents-notch.jump", qos: .userInitiated)

    static func open(agent: Agent, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        queue.async { open(JumpResolver.resolve(agent: agent, home: home)) }
    }

    static func open(_ targets: [JumpTarget]) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { open(targets) }
            return
        }
        attempt(ArraySlice(targets))
    }

    private static func attempt(_ targets: ArraySlice<JumpTarget>) {
        guard let target = targets.first else {
            MainActor.assumeIsolated { SoundPlayer.shared.play(.operationFailed) }
            return
        }
        let rest = targets.dropFirst()
        switch target {
        case .claudeApp(let url), .codexApp(let url):
            if !NSWorkspace.shared.open(url) { attempt(rest) }
        case .terminal(let pid, _):
            // ps and AppleScript block for a while: do them off the main thread, then come back for the activation.
            queue.async {
                let plan = ownerPlan(pid)
                DispatchQueue.main.async {
                    if let plan, plan.app.activate(options: []) {
                        if let tty = plan.tty, let bundle = plan.app.bundleIdentifier { queue.async { selectTab(bundle: bundle, tty: tty) } }
                    } else { attempt(rest) }
                }
            }
        case .editor(let bundleId, let cwd):
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
                attempt(rest); return
            }
            let folders = cwd.map { [URL(fileURLWithPath: $0, isDirectory: true)] } ?? []
            NSWorkspace.shared.open(folders, withApplicationAt: app, configuration: .init()) { _, error in
                if error != nil { DispatchQueue.main.async { attempt(rest) } }
            }
        case .folder(let path):
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            if !NSWorkspace.shared.open(folder) {
                if !rest.isEmpty { attempt(rest) }
                else { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser) }
            }
        }
    }

    private struct ProcessInfo {
        var parent: Int32
        var tty: String
    }

    private static let owners: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed"
    ]

    /// The app that owns the terminal process and the tty to select in it. Reads `ps`, so never on main.
    private static func ownerPlan(_ pid: Int32?) -> (app: NSRunningApplication, tty: String?)? {
        guard let pid, pid > 1 else { return nil }
        let processes = processTable()
        let apps = DispatchQueue.main.sync {
            NSWorkspace.shared.runningApplications.filter { owners.contains($0.bundleIdentifier ?? "") }
        }
        var current = pid
        var visited: Set<Int32> = []
        var tty: String?
        while current > 1, visited.count < 128, visited.insert(current).inserted {
            if let info = processes[current], info.tty != "??", info.tty != "?" { tty = tty ?? info.tty }
            if let app = apps.first(where: { $0.processIdentifier == current }) { return (app, tty) }
            guard let info = processes[current], info.parent != current else { break }
            current = info.parent
        }
        return nil
    }

    private static func processTable() -> [Int32: ProcessInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,tty="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [:] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return [:] }
        var table: [Int32: ProcessInfo] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count == 3, let pid = Int32(fields[0]), let parent = Int32(fields[1]) else { continue }
            table[pid] = ProcessInfo(parent: parent, tty: String(fields[2]))
        }
        return table
    }

    private static func selectTab(bundle: String, tty: String) {
        // Only ps's device name enters AppleScript; reject anything that could be source text.
        guard tty.range(of: "^[A-Za-z0-9/]+$", options: .regularExpression) != nil else { return }
        let device = tty.hasPrefix("/dev/") ? tty : "/dev/" + tty
        let source: String
        switch bundle {
        case "com.apple.Terminal":
            source = """
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(device)" then
                            set selected tab of w to t
                            set index of w to 1
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        case "com.googlecode.iterm2":
            source = """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(device)" then
                                select t
                                select s
                                set index of w to 1
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        default: return
        }
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
