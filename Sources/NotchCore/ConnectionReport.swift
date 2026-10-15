import Foundation

public struct ConnectionReceipt {
    let installer: HookInstaller
    public init(installer: HookInstaller) { self.installer = installer }
    public func file(_ vendor: Vendor) -> URL {
        installer.helper.deletingLastPathComponent().appendingPathComponent("first-hook-\(vendor.rawValue).json")
    }
    public func timestamp(_ vendor: Vendor) -> Double? {
        guard let data = try? Data(contentsOf: file(vendor)),
              let value = try? JSONDecoder().decode(Double.self, from: data), value.isFinite, value > 0 else { return nil }
        return value
    }
    public func record(_ vendor: Vendor, at time: Double = Date().timeIntervalSince1970) throws {
        guard installer.isInstalled(vendor), timestamp(vendor) == nil else { return }
        try FileManager.default.createDirectory(at: file(vendor).deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(time).write(to: file(vendor), options: .atomic)
    }
    public func reset(_ vendor: Vendor) throws {
        try FileManager.default.createDirectory(at: file(vendor).deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: file(vendor).path) { try FileManager.default.removeItem(at: file(vendor)) }
    }
}

public struct ConnectionReport: Sendable {
    public enum Step: Sendable { case config, helper, firstHook, trust }
    public let vendor: Vendor
    public let configWritten: Bool
    public let helperAlive: Bool
    public let firstHookAt: Double?
    public let waitsForTrust: Bool
    public var missing: Step? {
        if !configWritten { return .config }
        if !helperAlive { return .helper }
        if waitsForTrust { return .trust }
        return firstHookAt == nil ? .firstHook : nil
    }

    public static func socketPath(_ installer: HookInstaller) -> String {
        installer.helper.deletingLastPathComponent().appendingPathComponent("notch.sock").path
    }

    public static func read(_ vendor: Vendor, installer: HookInstaller = HookInstaller(), listening: (() -> Bool)? = nil) -> Self {
        let config = installer.isInstalled(vendor)
        let binary = FileManager.default.isExecutableFile(atPath: installer.helper.path)
            && (try? installer.helper.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        let alive = binary && (listening?() ?? HookClient.probe(path: socketPath(installer), pathCheck: {
            HookClient.isTrusted($0, pinned: HookClient.pinnedApp(helper: installer.helper.path))
        }))
        let first = ConnectionReceipt(installer: installer).timestamp(vendor)
        let trust = vendor == .codex ? CodexHookTrust.read(installer: installer) : nil
        return Self(vendor: vendor, configWritten: config, helperAlive: alive, firstHookAt: first,
                    waitsForTrust: vendor == .codex && config && (trust.map { !$0 } ?? (first == nil)))
    }

    public var status: String {
        switch missing {
        case .config: return Loc.t("Config not written", "Настройки не записаны")
        case .helper: return Loc.t("Helper not alive", "Помощник недоступен")
        case .firstHook: return Loc.t("First hook not received", "Первый хук не получен")
        case .trust: return Loc.t("Codex waits for trust", "Codex ждёт доверия")
        case nil: return Loc.t("Connected", "Подключено")
        }
    }
    public var hint: String {
        switch missing {
        case .config: return Loc.t("Connect to write the full hook set.", "Подключите, чтобы записать все хуки.")
        case .helper: return Loc.t("Reconnect, then keep Agent Notch running.", "Переподключите и оставьте Agent Notch открытым.")
        case .firstHook: return Loc.t("Send a prompt in a new agent session.", "Отправьте запрос в новой сессии агента.")
        case .trust: return Loc.t("Open /hooks in Codex and trust notch-hook.", "Откройте /hooks в Codex и доверьтесь notch-hook.")
        case nil: return Loc.t("A hook from this vendor has reached the app.", "Хук этого агента дошёл до приложения.")
        }
    }
    public var steps: [(String, Bool)] {
        var result = [(Loc.t("Config written", "Настройки записаны"), configWritten),
                      (Loc.t("Helper alive", "Помощник доступен"), helperAlive),
                      (Loc.t("First hook received", "Первый хук получен"), firstHookAt != nil)]
        if vendor == .codex { result.append((Loc.t("Codex waits for trust", "Codex ждёт доверия"), waitsForTrust)) }
        return result
    }
    public static func doctor(installer: HookInstaller = HookInstaller()) -> String {
        [Vendor.claude, .codex].map { vendor in
            let report = read(vendor, installer: installer)
            func yes(_ value: Bool) -> String { value ? "yes" : "no" }
            return "\(vendor.rawValue): config written: \(yes(report.configWritten)); helper alive: \(yes(report.helperAlive)); first hook received: \(yes(report.firstHookAt != nil)); Codex waits for trust: \(yes(report.waitsForTrust))\n  \(report.status). \(report.hint)" + (report.waitsForTrust && report.missing != .trust ? " " + Loc.t("Open /hooks in Codex and trust notch-hook.", "Откройте /hooks в Codex и доверьтесь notch-hook.") : "")
        }.joined(separator: "\n")
    }

    /// Executes the installed helper; its diagnostic protocol cannot create an approval ticket.
    public static func testRequest(_ vendor: Vendor, installer: HookInstaller = HookInstaller()) -> Bool {
        let process = Process(), output = Pipe()
        process.executableURL = installer.helper
        process.arguments = ["--test-request", vendor.rawValue, "--home", installer.home.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return false }
        guard finished.wait(timeout: .now() + 2) == .success else {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0 && output.fileHandleForReading.readDataToEndOfFile() == Data("PASS\n".utf8)
    }
}
