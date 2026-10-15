import Darwin
import Foundation

/// The hook's side of the socket.
public enum HookClient {
    /// Sends one hook event. With `wait` > 0 blocks up to that long for the human's decision.
    /// Nil when the app is not running or did not answer: the agent then carries on as if there were no hook.
    public static func send(vendor: Vendor, payload: Data, wait: Double, path: String = HookServer.defaultPath,
                            pathCheck: (String) -> Bool = HookClient.isPlacingApp,
                            deliver: (HookDecision) -> Bool = { _ in false }) -> HookDecision? {
        guard let p = try? JSONSerialization.jsonObject(with: payload) as? Rec,
              (HookEvent.toolIdentity(vendor: vendor, payload: p)?.utf8.count ?? 0) <= HookServer.maxToolIdentityBytes,
              let line = try? JSONSerialization.data(withJSONObject: ["vendor": vendor.rawValue, "wait": wait > 0, "payload": p])
        else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard var addr = try? HookServer.address(path) else { return nil }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0, trustedPeer(fd, pathCheck: pathCheck) else { return nil }
        Socket.configure(fd, readTimeout: max(wait, 0.3))
        guard Socket.write(fd, line + [0x0A]) else { return nil }
        guard wait > 0, let reply = Socket.readLine(fd, limit: HookServer.maxLine),
              let r = try? JSONSerialization.jsonObject(with: reply) as? Rec else { return nil }
        let toolUseID = HookEvent.toolIdentity(vendor: vendor, payload: p)
        guard let ticket = r["ticket"] as? Int, ticket > 0,
              HookReceipt.matchesTool(r, toolUseID: toolUseID),
              let decision = HookDecision(wire: r) else { return nil }
        // Keep the socket until stdout has accepted and flushed the decision.
        guard deliver(decision) else { return decision }
        // One nonblocking receipt write: acknowledgement must never extend the agent's wait.
        let receipt = HookReceipt.ack(ticket: ticket, toolUseID: toolUseID) + [10]
        _ = receipt.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, MSG_DONTWAIT) }
        return decision
    }

    /// A full or closed agent pipe cannot extend the hook wait or earn a receipt.
    public static func writeStdout(_ output: String) -> Bool {
        let flags = fcntl(STDOUT_FILENO, F_GETFL)
        guard flags >= 0, fcntl(STDOUT_FILENO, F_SETFL, flags | O_NONBLOCK) == 0 else { return false }
        defer { _ = fcntl(STDOUT_FILENO, F_SETFL, flags) }
        let data = Data((output + "\n").utf8)
        // Direct writes leave no buffered bytes for exit() to retry on a full pipe.
        let deadline = ProcessInfo.processInfo.systemUptime + 0.1
        let written = data.withUnsafeBytes { bytes -> Bool in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.write(STDOUT_FILENO, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if n > 0 { offset += n; continue }
                guard n < 0, errno == EAGAIN || errno == EINTR else { return false }
                let left = deadline - ProcessInfo.processInfo.systemUptime
                guard left > 0 else { return false }
                var ready = pollfd(fd: STDOUT_FILENO, events: Int16(POLLOUT), revents: 0)
                guard poll(&ready, 1, Int32(ceil(left * 1000))) > 0 else { return false }
            }
            return true
        }
        let flushed = fflush(stdout)
        return written && flushed == 0 && ferror(stdout) == 0
    }

    /// Require the app bundle layout before trusting a socket decision.
    public static func isAppExecutable(_ path: String) -> Bool {
        let parts = URL(fileURLWithPath: path).standardized.pathComponents
        guard parts.count >= 5, Array(parts.suffix(3)) == ["Contents", "MacOS", "AgentsNotch"] else { return false }
        let bundle = parts[parts.count - 4]
        return bundle.hasSuffix(".app") && bundle.count > 4
    }

    /// The peer is the very app that placed this helper, recorded next to it, and has the app layout.
    public static func isTrusted(_ peer: String, pinned: String?) -> Bool {
        guard let pinned, isAppExecutable(peer) else { return false }
        return resolved(peer) == resolved(pinned)
    }

    /// The app path the installer wrote next to the helper; nil when missing or not a private regular file.
    public static func pinnedApp(helper: String) -> String? {
        let pin = URL(fileURLWithPath: helper).deletingLastPathComponent().appendingPathComponent(HookInstaller.appPinName).path
        var info = stat()
        guard lstat(pin, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              let text = try? String(contentsOfFile: pin, encoding: .utf8) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public static func isPlacingApp(_ peer: String) -> Bool {
        let me = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
        return isTrusted(peer, pinned: pinnedApp(helper: me))
    }

    private static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func trustedPeer(_ fd: Int32, pathCheck: (String) -> Bool) -> Bool {
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { return false }
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0,
              size == MemoryLayout<pid_t>.size, pid > 0 else { return false }
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        return pathCheck(String(cString: buffer))
    }
}
