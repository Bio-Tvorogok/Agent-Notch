import Darwin
import Foundation

/// Runs manifest commands with posix_spawn: Foundation.Process cannot hand a pipe to the child as descriptor 3.
/// The child gets /dev/null for stdin, pipes for stdout and stderr, the settings pipe if the command asks for it,
/// and nothing else: every other descriptor of the app is closed (POSIX_SPAWN_CLOEXEC_DEFAULT).
public enum ServiceRunner {
    public struct Result: Equatable, Sendable {
        /// Exit code, or 128 + signal.
        public let status: Int32
        public let stdout: Data
        public let stderr: Data
        public let timedOut: Bool
        public var ok: Bool { status == 0 && !timedOut }
    }

    public enum Failure: LocalizedError, Equatable {
        case notApproved, moved, settingsTooLarge, system(String, Int32)
        public var errorDescription: String? {
            switch self {
            case .notApproved: Loc.t("The manifest changed. Review and approve it again.", "Манифест изменился. Просмотрите и подтвердите его снова.")
            case .moved: Loc.t("The program is no longer inside the service folder.", "Программа больше не лежит в папке сервиса.")
            case .settingsTooLarge: Loc.t("The settings are too large to send.", "Настройки слишком большие для передачи.")
            case let .system(call, code): "\(call): \(String(cString: strerror(code)))"
            }
        }
    }

    static let outputLimit = 256 * 1024
    /// Well under the 16 KB a macOS pipe holds, so the whole object is written before the child starts.
    static let settingsLimit = 8 * 1024

    /// Reloads the manifest and refuses to go on if it is not the text the user approved.
    public static func approved(_ entry: ServiceEntry, home: String = NSHomeDirectory()) throws -> ServiceManifest {
        let manifest = try ServiceManifest.load(folder: entry.folder, home: home)
        guard manifest.id == entry.id, manifest.root == entry.folder, manifest.fingerprint == entry.approved else { throw Failure.notApproved }
        return manifest
    }

    /// Runs a command of an approved manifest from its folder. `settings` is required for `config: true` commands and ignored otherwise.
    public static func run(_ command: ServiceManifest.Command, of manifest: ServiceManifest, settings: Data?,
                           environment: [String: String]) throws -> Result {
        // The file may have been swapped for a link since the manifest was read.
        guard ServiceManifest.canonical(manifest.cwd + "/" + command.run[0]) == command.executable,
              ServiceManifest.inside(command.executable, manifest.root), ServiceManifest.safe(command.executable) else { throw Failure.moved }
        var channel: (fd: Int32, data: Data)?
        if command.config, let fd = manifest.configFD { channel = (fd, settings ?? Data("{}".utf8)) }
        return try spawn(command.executable, Array(command.run.dropFirst()), cwd: manifest.cwd, environment: environment,
                         settings: channel, timeout: command.timeout)
    }

    static func spawn(_ executable: String, _ arguments: [String], cwd: String, environment: [String: String],
                      settings: (fd: Int32, data: Data)?, timeout: TimeInterval) throws -> Result {
        if let settings, settings.data.count > settingsLimit { throw Failure.settingsTooLarge }
        var opened: [Int32] = []
        defer { opened.forEach { close($0) } }
        func pipePair() throws -> (read: Int32, write: Int32) {
            var fds: [Int32] = [0, 0]
            guard pipe(&fds) == 0 else { throw Failure.system("pipe", errno) }
            // Above the descriptor numbers a child is given, and closed in any process the app starts some other way.
            let pair = try fds.map { fd -> Int32 in
                let moved = fcntl(fd, F_DUPFD_CLOEXEC, 10)
                let code = errno
                close(fd)
                guard moved >= 0 else { throw Failure.system("fcntl", code) }
                opened.append(moved)
                return moved
            }
            return (pair[0], pair[1])
        }
        func release(_ fd: Int32) { close(fd); opened.removeAll { $0 == fd } }

        let out = try pipePair(), err = try pipePair()
        var config: (read: Int32, write: Int32)?
        if let settings {
            let pair = try pipePair()
            config = pair
            // Written whole before the child starts; a child that never reads it costs no SIGPIPE.
            _ = fcntl(pair.write, F_SETNOSIGPIPE, 1)
            _ = fcntl(pair.write, F_SETFL, O_NONBLOCK)
            let written = settings.data.withUnsafeBytes { write(pair.write, $0.baseAddress, $0.count) }
            guard written == settings.data.count else { throw Failure.settingsTooLarge }
            release(pair.write)
        }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, out.write, 1)
        posix_spawn_file_actions_adddup2(&actions, err.write, 2)
        if let config, let settings { posix_spawn_file_actions_adddup2(&actions, config.read, settings.fd) }
        if #available(macOS 26, *) { posix_spawn_file_actions_addchdir(&actions, cwd) }
        else { posix_spawn_file_actions_addchdir_np(&actions, cwd) }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Its own process group, so a timeout stops the command and whatever it started in the foreground.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        posix_spawnattr_setpgroup(&attributes, 0)
        var signals = sigset_t()
        sigfillset(&signals)
        posix_spawnattr_setsigdefault(&attributes, &signals)
        sigemptyset(&signals)
        posix_spawnattr_setsigmask(&attributes, &signals)

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        guard spawned == 0 else { throw Failure.system("posix_spawn", spawned) }
        release(out.write)
        release(err.write)
        if let config { release(config.read) }
        return collect(pid, out: out.read, err: err.read, timeout: timeout)
    }

    /// Reads both pipes until the child exits and they close. A daemon the command left holding them gets a second, then is ignored.
    private static func collect(_ pid: pid_t, out: Int32, err: Int32, timeout: TimeInterval) -> Result {
        var buffers = [Data(), Data()]
        var open = [true, true]
        let fds = [out, err]
        let start = Date()
        var exitedAt: Date?
        var status: Int32 = 0
        var timedOut = false
        var termSent: Date?
        var killSent = false
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            var polled = fds.enumerated().filter { open[$0.offset] }.map { pollfd(fd: $0.element, events: Int16(POLLIN), revents: 0) }
            if !polled.isEmpty { _ = poll(&polled, nfds_t(polled.count), 100) } else { usleep(50_000) }
            for p in polled where p.revents != 0 {
                let i = fds.firstIndex(of: p.fd)!
                let n = read(p.fd, &chunk, chunk.count)
                if n > 0 {
                    if buffers[i].count < outputLimit { buffers[i].append(contentsOf: chunk[0..<min(n, outputLimit - buffers[i].count)]) }
                } else if n == 0 || errno != EINTR && errno != EAGAIN {
                    open[i] = false
                }
            }
            if exitedAt == nil {
                var raw: Int32 = 0
                let reaped = waitpid(pid, &raw, WNOHANG)
                if reaped == pid {
                    exitedAt = Date()
                    status = raw & 0x7f == 0 ? (raw >> 8) & 0xff : 128 + (raw & 0x7f)
                } else if reaped < 0 && errno != EINTR {
                    // Someone else reaped it: the exit code is lost.
                    exitedAt = Date()
                    status = 127
                }
            }
            // The whole group: a member that ignores SIGTERM is killed even after the command itself has gone.
            if Date().timeIntervalSince(start) > timeout {
                if termSent == nil { termSent = Date(); timedOut = true; kill(-pid, SIGTERM) }
                else if !killSent, Date().timeIntervalSince(termSent!) > 3 { killSent = true; kill(-pid, SIGKILL) }
            }
            if let exitedAt, !open.contains(true) || Date().timeIntervalSince(exitedAt) > 1 { break }
        }
        if timedOut && !killSent { kill(-pid, SIGKILL) }
        return Result(status: status, stdout: buffers[0], stderr: buffers[1], timedOut: timedOut)
    }
}

/// What a service command's environment holds: a few of the app's own variables and the PATH a login shell has.
/// Nothing else from the app reaches the service, including whatever the app itself was started with.
public enum ServiceEnvironment {
    static let passed = ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "__CF_USER_TEXT_ENCODING"]
    /// What `loginPath` falls back to: an app started from the Dock has only /usr/bin:/bin:/usr/sbin:/sbin.
    public static func fallbackPath(home: String) -> String {
        [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
    }

    public static func make(path: String, from environment: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var result = environment.filter { passed.contains($0.key) }
        result["PATH"] = path
        return result
    }

    /// The PATH the user's login shell sets up, where tools like node usually come from. nil if the shell fails or stalls.
    public static func loginPath(home: String = NSHomeDirectory(),
                                 environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let shell = loginShell()
        let marker = "__AGENT_NOTCH_PATH__"
        let base = make(path: fallbackPath(home: home), from: environment)
        guard let result = try? ServiceRunner.spawn(shell, ["-l", "-c", "printf '\(marker)%s\(marker)' \"$PATH\""], cwd: home,
                                                    environment: base, settings: nil, timeout: 5), result.ok else { return nil }
        let text = String(decoding: result.stdout, as: UTF8.self)
        let parts = text.components(separatedBy: marker)
        guard parts.count >= 3, !parts[parts.count - 2].isEmpty, ServiceManifest.plain(parts[parts.count - 2]) else { return nil }
        return parts[parts.count - 2]
    }

    /// The account's shell if /etc/shells lists it, otherwise zsh.
    static func loginShell() -> String {
        let listed = (try? String(contentsOfFile: "/etc/shells", encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell.map({ String(cString: $0) }),
           shell.hasPrefix("/"), listed.contains(shell) { return shell }
        return "/bin/zsh"
    }
}
