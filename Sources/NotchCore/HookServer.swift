import Darwin
import Foundation

/// The unix socket `notch-hook` talks to. One JSON line comes in: `{"vendor":…,"wait":bool,"payload":{hook stdin}}`.
/// A permission request (or a PreToolUse of a tool that asks a human) that waits keeps its connection open until `answer`, and gets back `{"decision":"allow|deny|pass"}`, plus `updatedInput` (an allow that answers a question) or `message` (a deny with a reason).
/// Socket 0600 in a 0700 folder, peers of the same user only.
public final class HookServer: @unchecked Sendable {
    public let path: String
    /// Runs on the server queue: the event and, for a request that waits for a human, its ticket.
    public var onEvent: @Sendable (HookEvent, Int?) -> Void = { _, _ in }
    /// The waiting hook hung up: the agent was interrupted, or its own timeout ran out.
    public var onGone: @Sendable (Int) -> Void = { _ in }

    /// Sent is provisional. Only a matching receipt reports delivered.
    public var onDelivery: @Sendable (Int, AnswerDelivery) -> Void = { _, _ in }

    private struct Request {
        let watch: DispatchSourceRead
        let fd: Int32
        let toolUseID: String?
        var sent = false
        var receipt = Data()
    }

    private let queue = DispatchQueue(label: "agents-notch.hooks")
    private var listener: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var waiting: [Int: Request] = [:]
    private var nextTicket = 1

    public static var defaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AgentsNotch/notch.sock").path
    }

    private let writeDecision: @Sendable (Int32, Data) -> Bool

    public convenience init(path: String = HookServer.defaultPath) {
        self.init(path: path, writeDecision: { Socket.write($0, $1) })
    }

    init(path: String, writeDecision: @escaping @Sendable (Int32, Data) -> Bool) {
        self.path = path
        self.writeDecision = writeDecision
    }

    public func start() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(dir, 0o700)
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var addr = try Self.address(path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 32) == 0 else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listener = fd
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptAll() }
        src.setCancelHandler { close(fd) }
        src.resume()
        acceptSource = src
    }

    public func stop() {
        queue.sync {
            for id in Array(waiting.keys) { finish(id, status: .notDelivered) }
            acceptSource?.cancel()
            acceptSource = nil
            listener = -1
            unlink(path)
        }
    }

    /// A ticket and tool identity must both match. A duplicate cannot replace an answer in flight.
    public func answer(_ ticket: Int, _ decision: HookDecision, toolUseID: String? = nil) {
        queue.async {
            guard var request = self.waiting[ticket] else {
                self.onDelivery(ticket, .notDelivered)
                return
            }
            guard request.toolUseID == toolUseID, !request.sent else { return }
            request.sent = true
            self.waiting[ticket] = request
            self.onDelivery(ticket, .sent)
            let wire = HookReceipt.decision(decision, ticket: ticket, toolUseID: toolUseID)
            guard self.writeDecision(request.fd, wire + [10]) else {
                NSLog("agents-notch: decision write failed for ticket %d: %s", ticket, strerror(errno))
                self.finish(ticket, status: .notDelivered)
                return
            }
            // The helper never waits for this timer: it sends one receipt and returns to the agent.
            self.queue.asyncAfter(deadline: .now() + 1) {
                self.finish(ticket, status: .notDelivered)
            }
        }
    }

    /// No approval: release an obsolete or hidden request back to the agent's own prompt.
    public func handBack(_ ticket: Int) {
        queue.async {
            guard let request = self.waiting[ticket] else { return }
            self.answer(ticket, .pass, toolUseID: request.toolUseID)
        }
    }

    // MARK: connections

    /// Requests held open at once; more get an immediate pass.
    static let maxWaiting = 64
    public static let maxLine = 4 << 20

    private func acceptAll() {
        while true {
            let fd = accept(listener, nil, nil)
            if fd < 0 {
                // Out of descriptors: the listener stays readable, so pause instead of spinning.
                if errno == EMFILE || errno == ENFILE, let src = acceptSource {
                    src.suspend()
                    queue.asyncAfter(deadline: .now() + 1) { src.resume() }
                }
                return
            }
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { close(fd); continue }
            // An accepted socket inherits O_NONBLOCK from the listener; reads here must block (with a timeout).
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
            Socket.configure(fd, readTimeout: 2)
            DispatchQueue.global(qos: .userInitiated).async {
                let line = Socket.readLine(fd, limit: Self.maxLine)
                self.queue.async { self.handle(fd, line) }
            }
        }
    }

    private func handle(_ fd: Int32, _ line: Data?) {
        guard let line, let r = try? JSONSerialization.jsonObject(with: line) as? Rec,
              let vendor = Vendor(rawValue: r["vendor"] as? String ?? ""), let payload = r["payload"] as? Rec,
              let event = HookEvent(vendor: vendor, payload: payload) else { close(fd); return }
        // Older helpers may still send these while the newly built app is running.
        guard !event.isAutomaticReview else { close(fd); return }
        guard event.waitsForAnswer, r["wait"] as? Bool == true, waiting.count < Self.maxWaiting else {
            close(fd)
            onEvent(event, nil)
            return
        }
        let ticket = nextTicket
        nextTicket += 1
        let watch = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        watch.setEventHandler { [weak self] in self?.readReceipt(ticket) }
        watch.setCancelHandler { close(fd) }
        waiting[ticket] = Request(watch: watch, fd: fd, toolUseID: event.toolUseID)
        watch.resume()
        queue.asyncAfter(deadline: .now() + Double(HookInstaller.wait)) {
            self.finish(ticket, status: .notDelivered)
        }
        onEvent(event, ticket)
    }

    private func readReceipt(_ ticket: Int) {
        guard var request = waiting[ticket] else { return }
        var bytes = [UInt8](repeating: 0, count: 4096)
        let n = recv(request.fd, &bytes, bytes.count, MSG_DONTWAIT)
        if n < 0 && (errno == EAGAIN || errno == EINTR) { return }
        guard n > 0, request.sent else { finish(ticket, status: .notDelivered); return }
        request.receipt.append(contentsOf: bytes[..<n])
        if let nl = request.receipt.firstIndex(of: 10) {
            let accepted = HookReceipt.matches(Data(request.receipt[..<nl]), ticket: ticket, toolUseID: request.toolUseID)
            finish(ticket, status: accepted ? .delivered : .notDelivered)
        } else if request.receipt.count >= 4096 {
            finish(ticket, status: .notDelivered)
        } else {
            waiting[ticket] = request
        }
    }

    private func finish(_ ticket: Int, status: AnswerDelivery) {
        guard let request = waiting.removeValue(forKey: ticket) else { return }
        request.watch.cancel()
        onDelivery(ticket, status)
        if status == .notDelivered { onGone(ticket) }
    }

    static func address(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in bytes.enumerated() { buf[i] = b }
        }
        return addr
    }
}


enum Socket {
    static func configure(_ fd: Int32, readTimeout: Double) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: Int(readTimeout), tv_usec: Int32((readTimeout - floor(readTimeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var send = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &send, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Bytes up to the first newline. Nil on timeout, hang-up or a line over `limit`.
    static func readLine(_ fd: Int32, limit: Int) -> Data? {
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 64 << 10)
        while out.count <= limit {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { return nil }
            if let nl = buf[..<n].firstIndex(of: 0x0A) { return out + buf[..<nl] }
            out.append(contentsOf: buf[..<n])
        }
        return nil
    }

    @discardableResult
    static func write(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { return false }
                off += n
            }
            return true
        }
    }
}
