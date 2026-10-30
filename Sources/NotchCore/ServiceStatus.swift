import Darwin
import Foundation

/// The status file a running service keeps (`status` in the manifest). Besides `pid`, `startedAt`, `updatedAt` and
/// `lastError`, every top-level object becomes one row, recognised by its shape rather than its name (docs/services.md).
public struct ServiceStatus: Equatable, Sendable {
    public struct Server: Equatable, Sendable {
        public let name: String
        /// nil until the service has checked.
        public let answers: Bool?
    }

    public enum Value: Equatable, Sendable {
        /// `{ "online": true, "servers": [{ "name": … }] }`
        case online(Bool, servers: [Server])
        /// `{ "enabled": true, "in": { "channelName": …, "guildName": … } | null }`
        case place(enabled: Bool, at: String?)
        /// `{ "provider": "claude", "alive": true }`
        case provider(String, alive: Bool?)
        /// `{ "ok": true | false | null, "url": … }`
        case check(ok: Bool?, url: String?)
    }

    public struct Row: Equatable, Sendable {
        public let key: String
        public let value: Value
    }

    public let pid: Int32?
    public let startedAt: Date?
    public let updatedAt: Date?
    public let lastError: String?
    public let rows: [Row]

    /// Known keys first, in this order, then the rest by name.
    static let order = ["discord", "voice", "brain", "tts", "stt"]
    static let maxBytes = 256 * 1024

    public static func read(_ path: String) -> ServiceStatus? {
        (try? ServiceFiles.contents(path, max: maxBytes)).flatMap(parse)
    }

    public static func parse(_ data: Data) -> ServiceStatus? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var rows: [Row] = []
        for (key, value) in object where ServiceManifest.matches(key, #"^[A-Za-z0-9_-]{1,32}$"#) {
            guard let block = value as? [String: Any], let parsed = row(block) else { continue }
            rows.append(Row(key: key, value: parsed))
        }
        func rank(_ key: String) -> Int { order.firstIndex(of: key) ?? order.count }
        rows.sort { rank($0.key) < rank($1.key) || rank($0.key) == rank($1.key) && $0.key < $1.key }
        let pid = (object["pid"] as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : Int32(exactly: $0.doubleValue) }
            .flatMap { $0 > 0 ? $0 : nil }
        return ServiceStatus(pid: pid, startedAt: date(object["startedAt"]), updatedAt: date(object["updatedAt"]),
                             lastError: text(object["lastError"], max: 2000), rows: Array(rows.prefix(16)))
    }

    private static func row(_ block: [String: Any]) -> Value? {
        if let online = bool(block["online"]) {
            let servers = (block["servers"] as? [Any] ?? []).prefix(50).compactMap { item -> Server? in
                guard let server = item as? [String: Any], let name = text(server["name"]) else { return nil }
                return Server(name: name, answers: bool(server["answers"]))
            }
            return .online(online, servers: servers)
        }
        if let enabled = bool(block["enabled"]), block.keys.contains("in") {
            let place = block["in"] as? [String: Any]
            let name = place.flatMap { text($0["channelName"]) ?? text($0["name"]) ?? text($0["channelId"]) }
            let at = name.map { name in place.flatMap { text($0["guildName"]) }.map { "\(name) · \($0)" } ?? name }
            return .place(enabled: enabled, at: place == nil ? nil : at ?? "?")
        }
        if let provider = text(block["provider"]) { return .provider(provider, alive: bool(block["alive"])) }
        if block.keys.contains("ok") { return .check(ok: bool(block["ok"]), url: text(block["url"])) }
        return nil
    }

    /// The same status with every text it shows masked: names and addresses come from the service.
    public func masked(secrets: [String]) -> ServiceStatus {
        func m(_ text: String) -> String { ServiceLogs.mask(text, secrets: secrets) }
        let rows = rows.map { row -> Row in
            let value: Value = switch row.value {
            case let .online(online, servers): .online(online, servers: servers.map { Server(name: m($0.name), answers: $0.answers) })
            case let .place(enabled, at): .place(enabled: enabled, at: at.map(m))
            case let .provider(provider, alive): .provider(m(provider), alive: alive)
            case let .check(ok, url): .check(ok: ok, url: url.map(m))
            }
            return Row(key: row.key, value: value)
        }
        return ServiceStatus(pid: pid, startedAt: startedAt, updatedAt: updatedAt, lastError: lastError.map(m), rows: rows)
    }

    /// Running only if the pid is alive, belongs to this user and is the process that wrote the file: a pid the system handed to
    /// a newer process after the service died started after `startedAt`.
    public func isRunning() -> Bool {
        guard let pid, let startedAt else { return false }
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_uid == getuid() else { return false }
        let began = Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1e6)
        return began <= startedAt.addingTimeInterval(5)
    }

    private static func bool(_ any: Any?) -> Bool? {
        guard let number = any as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func text(_ any: Any?, max: Int = 200) -> String? {
        guard let text = any as? String, !text.isEmpty else { return nil }
        let line = String(text.prefix(max)).replacingOccurrences(of: "\n", with: " ")
        return ServiceManifest.plain(line) ? line : String(line.unicodeScalars.filter {
            $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
        }.map(Character.init))
    }

    private static func date(_ any: Any?) -> Date? {
        guard let text = any as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: text) { return date }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}

/// The result of a JSON check command such as `check-pc`: `{ ok, url, healthMs, latencyMs, error }`.
public struct ServiceCheck: Equatable, Sendable {
    public let ok: Bool
    public let url: String?
    public let healthMs: Int?
    public let latencyMs: Int?
    public let error: String?

    public init(ok: Bool, url: String? = nil, healthMs: Int? = nil, latencyMs: Int? = nil, error: String? = nil) {
        self.ok = ok; self.url = url; self.healthMs = healthMs; self.latencyMs = latencyMs; self.error = error
    }

    /// The command prints its JSON whatever its exit code; without it the check failed with whatever it wrote.
    public static func parse(_ result: ServiceRunner.Result, secrets: [String] = []) -> ServiceCheck {
        let object = (try? JSONSerialization.jsonObject(with: result.stdout)) as? [String: Any]
        func ms(_ key: String) -> Int? { (object?[key] as? NSNumber).flatMap { Int(exactly: $0.doubleValue.rounded()) } }
        func text(_ key: String) -> String? {
            (object?[key] as? String).flatMap { $0.isEmpty ? nil : ServiceLogs.mask(String($0.prefix(500)), secrets: secrets) }
        }
        guard let object, let ok = object["ok"] as? NSNumber, CFGetTypeID(ok) == CFBooleanGetTypeID() else {
            let said = String(decoding: result.stderr.isEmpty ? result.stdout : result.stderr, as: UTF8.self)
                .split(separator: "\n").last.map(String.init)
            let reason = result.timedOut ? Loc.t("timed out", "не дождались ответа") : said ?? Loc.t("exit code \(result.status)", "код выхода \(result.status)")
            return ServiceCheck(ok: false, error: ServiceLogs.mask(String(reason.prefix(500)), secrets: secrets))
        }
        return ServiceCheck(ok: ok.boolValue && result.ok, url: text("url"), healthMs: ms("healthMs"), latencyMs: ms("latencyMs"),
                            error: text("error") ?? (ok.boolValue && !result.ok ? Loc.t("exit code \(result.status)", "код выхода \(result.status)") : nil))
    }
}

/// Log tails and the masking every service text goes through before it is shown.
public enum ServiceLogs {
    static let tailBytes = 64 * 1024

    /// The last `lines` lines of a file. A first line cut by the read window is dropped.
    public static func tail(_ path: String, lines: Int = 200) -> [String] {
        guard let (data, cut) = try? ServiceFiles.tail(path, bytes: tailBytes) else { return [] }
        var all = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        if cut, !all.isEmpty { all.removeFirst() }
        if all.last == "" { all.removeLast() }
        return Array(all.suffix(lines))
    }

    /// Hides the stored secrets wherever they appear, and anything shaped like a token or key even if it is not one of them.
    public static func mask(_ text: String, secrets: [String]) -> String {
        var masked = text
        for secret in secrets.filter({ $0.count >= 4 }).sorted(by: { $0.count > $1.count }) {
            masked = masked.replacingOccurrences(of: secret, with: "***")
        }
        for (pattern, template) in patterns {
            masked = pattern.stringByReplacingMatches(in: masked, range: NSRange(masked.startIndex..., in: masked), withTemplate: template)
        }
        return masked
    }

    /// Every repetition before the masked value is bounded: a log line is not trusted to be small or friendly,
    /// and an unbounded `[A-Za-z_]*` after «token» goes quadratic on a long «tokentoken…».
    private static let patterns: [(NSRegularExpression, String)] = [
        // Discord bot token: three dot-separated base64url parts.
        (#"[A-Za-z0-9_-]{23,28}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,}"#, "***"),
        (#"sk-ant-[A-Za-z0-9_-]+"#, "sk-ant-***"),
        (#"\bsk-[A-Za-z0-9_-]{20,}"#, "sk-***"),
        (#"\b(gh[pousr]_)[A-Za-z0-9]{20,}"#, "$1***"),
        (#"(?i)\b(bearer|basic)\s{1,8}[A-Za-z0-9._~+/=-]{8,}"#, "$1 ***"),
        (#"(?i)((?:token|secret|password|passwd|api[_-]?key)[A-Za-z_]{0,32}["']?\s{0,8}[=:]\s{0,8}["']?)[^\s"',;)}\]]+"#, "$1***"),
        // Credentials in a URL: scheme://user:password@host
        (#"(?i)\b([a-z][a-z0-9+.-]{0,31}://[^/\s:@]{1,256}:)[^/\s@]{1,256}@"#, "$1***@"),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }
}
