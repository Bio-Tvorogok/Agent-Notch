import AppKit
import Combine
import Foundation
import NotchCore

/// Settings → Services: the added services, their approved manifests and what they are doing.
/// Secrets stay in `secrets` (the Keychain in the app); this model only knows which ones are filled.
@MainActor
final class ServicesModel: ObservableObject {
    static let shared = ServicesModel()

    enum Manifest {
        case ok(ServiceManifest)
        /// The file differs from what the user approved; nothing runs until they approve it again.
        case changed(ServiceManifest)
        case failed(String)
    }

    enum Choices: Equatable {
        case loading
        case loaded([ServiceOption])
        case failed(String)
    }

    struct Output: Equatable {
        let command: String
        let ok: Bool
        let text: String
    }

    struct Pending: Identifiable {
        let manifest: ServiceManifest
        /// Re-approval of a service already added.
        let changed: Bool
        /// What the previous approval ran, by command, to mark what changed.
        var previous: [String: String]?
        var id: String { manifest.fingerprint }
    }

    @Published private(set) var entries: [ServiceEntry]
    @Published private(set) var manifests: [String: Manifest] = [:]
    @Published var selected: String?
    @Published var pending: Pending?
    @Published var problem: String?
    @Published private(set) var status: [String: ServiceStatus] = [:]
    /// The status file's `lastError`, masked.
    @Published private(set) var lastError: [String: String] = [:]
    @Published private(set) var running: [String: Bool] = [:]
    @Published private(set) var busy: [String: String] = [:]
    @Published private(set) var outputs: [String: Output] = [:]
    @Published private(set) var checks: [String: ServiceCheck] = [:]
    @Published private(set) var choices: [String: [String: Choices]] = [:]
    @Published private(set) var logs: [String: [String]] = [:]
    /// Which secret fields have a value, by service; never the values.
    @Published private(set) var filledSecrets: [String: Set<String>] = [:]

    private let defaults: UserDefaults
    let secrets: ServiceSecretStore
    private let home: String
    /// Masking needs the values; read once per service and dropped when one changes.
    private var secretCache: [String: [String: String]] = [:]
    private var loginPath: String?
    private var timer: Timer?
    private var watchers = 0
    private static let key = "services"

    init(defaults: UserDefaults = .standard, secrets: ServiceSecretStore = KeychainSecretStore(), home: String = NSHomeDirectory()) {
        self.defaults = defaults
        self.secrets = secrets
        self.home = home
        entries = SettingsStorage.read([ServiceEntry].self, key: Self.key, default: [], in: defaults)
        selected = entries.first?.id
        reloadManifests()
    }

    func entry(_ id: String) -> ServiceEntry? { entries.first { $0.id == id } }

    /// The manifest the user approved, if the file still says exactly that.
    func approved(_ id: String) -> ServiceManifest? {
        if case let .ok(manifest) = manifests[id] { return manifest }
        return nil
    }

    func shown(_ id: String) -> ServiceManifest? {
        switch manifests[id] {
        case let .ok(manifest), let .changed(manifest): manifest
        default: nil
        }
    }

    private func save() { SettingsStorage.write(entries, key: Self.key, in: defaults) }

    private func update(_ id: String, _ change: (inout ServiceEntry) -> Void) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[i])
        save()
    }

    func reloadManifests() {
        for entry in entries {
            do {
                let manifest = try ServiceManifest.load(folder: entry.folder, home: home)
                guard manifest.id == entry.id else { throw ServiceRunner.Failure.notApproved }
                manifests[entry.id] = manifest.fingerprint == entry.approved ? .ok(manifest) : .changed(manifest)
                filledSecrets[entry.id] = Set(manifest.fields.filter { $0.kind == .secret && secrets.contains(entry.secretScope, $0.key) }.map(\.key))
            } catch {
                manifests[entry.id] = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Adding and approving

    /// Reads the folder's manifest and asks the user to approve it.
    func add(folder: String) {
        do {
            let manifest = try ServiceManifest.load(folder: folder, home: home)
            if let other = entries.first(where: { $0.id == manifest.id }), other.folder != manifest.root {
                problem = ServiceText.duplicate(manifest.name, other.folder)
                return
            }
            let existing = entry(manifest.id)
            pending = Pending(manifest: manifest, changed: existing != nil, previous: existing?.approvedCommands)
        } catch {
            problem = error.localizedDescription
        }
    }

    func review(_ id: String) {
        if case let .changed(manifest) = manifests[id] {
            pending = Pending(manifest: manifest, changed: true, previous: entry(id)?.approvedCommands)
        }
    }

    func approve(_ manifest: ServiceManifest) {
        pending = nil
        if let existing = entry(manifest.id) {
            // Secrets of fields the new version no longer has are deleted, not left behind in the Keychain.
            let kept = Set(manifest.fields.filter { $0.kind == .secret }.map(\.key))
            for key in secrets.keys(existing.secretScope) where !kept.contains(key) { try? secrets.write(nil, existing.secretScope, key) }
            secretCache[manifest.id] = nil
            update(manifest.id) {
                $0.approved = manifest.fingerprint
                $0.approvedCommands = manifest.commandSummary
            }
        } else {
            entries.append(ServiceEntry(manifest: manifest))
            save()
        }
        selected = manifest.id
        reloadManifests()
        refresh()
    }

    /// Forgets the service and deletes every secret it had in the Keychain, whatever its manifest now says.
    /// The service's own files stay.
    func remove(_ id: String) {
        guard let entry = entry(id) else { return }
        do { try secrets.removeAll(entry.secretScope) }
        catch {
            problem = error.localizedDescription
            return
        }
        secretCache[id] = nil
        entries.removeAll { $0.id == id }
        save()
        manifests[id] = nil
        status[id] = nil
        lastError[id] = nil
        running[id] = nil
        outputs[id] = nil
        checks[id] = nil
        choices[id] = nil
        filledSecrets[id] = nil
        selected = entries.first?.id
    }

    // MARK: - Settings

    func value(_ id: String, _ field: ServiceManifest.Field) -> String {
        entry(id)?.values[field.key] ?? field.defaultValue ?? ""
    }

    func setValue(_ id: String, _ field: ServiceManifest.Field, _ value: String) {
        guard let manifest = shown(id) else { return }
        update(id) { $0.set(value, for: field.key, in: manifest) }
    }

    func choose(_ id: String, _ field: ServiceManifest.Field, _ option: ServiceOption) {
        guard let manifest = shown(id) else { return }
        update(id) { $0.choose(option, for: field, in: manifest) }
    }

    func setSecret(_ id: String, _ key: String, _ value: String?) {
        guard let scope = entry(id)?.secretScope else { return }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try secrets.write(trimmed, scope, key)
            secretCache[id] = nil
            if trimmed?.isEmpty == false { filledSecrets[id, default: []].insert(key) } else { filledSecrets[id]?.remove(key) }
        } catch {
            problem = error.localizedDescription
        }
    }

    func setLaunchWithApp(_ id: String, _ on: Bool) { update(id) { $0.launchWithApp = on } }

    /// Kept only when every filled secret was read: a refused or locked Keychain is asked again, not taken for «none».
    private func secretValues(_ manifest: ServiceManifest) -> [String: String] {
        if let cached = secretCache[manifest.id] { return cached }
        let values = secrets.all(manifest)
        if Set(values.keys) == filledSecrets[manifest.id] ?? [] { secretCache[manifest.id] = values }
        return values
    }

    func problems(_ id: String) -> [String: ServiceValues.Problem] {
        guard let manifest = shown(id), let entry = entry(id) else { return [:] }
        var loaded: [String: [ServiceOption]] = [:]
        for (key, state) in choices[id] ?? [:] { if case let .loaded(options) = state { loaded[key] = options } }
        // Filled-in secrets only matter for presence here; their values are checked when the command runs.
        let present = Dictionary(uniqueKeysWithValues: (filledSecrets[id] ?? []).map { ($0, "•") })
        return ServiceValues.problems(manifest, entry: entry, secrets: present, choices: loaded).filter { key, problem in
            !(manifest.field(key)?.kind == .secret && problem == .pattern)
        }
    }

    // MARK: - Commands

    /// Starting needs every required setting; a check gets whatever is filled in, so it works before the rest of the form.
    nonisolated static func needsComplete(_ command: ServiceManifest.Command) -> Bool {
        command.config && ["start", "restart"].contains(command.name)
    }

    /// Runs a manifest command off the main thread. Settings-taking commands get them on the manifest's descriptor.
    func run(_ id: String, _ name: String) {
        guard busy[id] == nil, let entry = entry(id) else { return }
        busy[id] = name
        if name == "check-pc" { checks[id] = nil }
        let secrets = self.secrets, home = self.home, cached = loginPath
        Task {
            let outcome = await Task.detached { () -> Result<(output: Output, check: ServiceCheck?, path: String?), Error> in
                Result {
                    let manifest = try ServiceRunner.approved(entry, home: home)
                    guard let command = manifest.command(name) else { throw ServiceRunner.Failure.notApproved }
                    let values = secrets.all(manifest)
                    if Self.needsComplete(command), !ServiceValues.problems(manifest, entry: entry, secrets: values).isEmpty {
                        throw ServiceText.Incomplete()
                    }
                    let path = Self.path(home: home, cached: cached)
                    let payload = command.config ? ServiceValues.payload(manifest, entry: entry, secrets: values) : nil
                    let result = try ServiceRunner.run(command, of: manifest, settings: payload, environment: ServiceEnvironment.make(path: path.path))
                    let known = Array(values.values)
                    return (Self.output(name, result, secrets: known), name == "check-pc" ? ServiceCheck.parse(result, secrets: known) : nil, path.login)
                }
            }.value
            busy[id] = nil
            switch outcome {
            case let .success(done):
                loginPath = loginPath ?? done.path
                if name == "check-pc" { checks[id] = done.check } else { outputs[id] = done.output }
            case let .failure(error):
                if name == "check-pc" { checks[id] = ServiceCheck(ok: false, error: error.localizedDescription) }
                outputs[id] = Output(command: name, ok: false, text: error.localizedDescription)
                if case ServiceRunner.Failure.notApproved = error { reloadManifests() }
            }
            refresh()
        }
    }

    /// The login shell's PATH, looked up once per app run; the fallback is not remembered, so a slow shell gets another try.
    nonisolated private static func path(home: String, cached: String?) -> (path: String, login: String?) {
        if let cached { return (cached, cached) }
        let login = ServiceEnvironment.loginPath(home: home)
        return (login ?? ServiceEnvironment.fallbackPath(home: home), login)
    }

    /// The last lines of what a command printed, masked, each cut to a readable length after masking.
    nonisolated private static func output(_ name: String, _ result: ServiceRunner.Result, secrets: [String]) -> Output {
        let lines = String(decoding: result.stdout + result.stderr, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false).suffix(60)
            .map { String(ServiceLogs.mask(String($0), secrets: secrets).prefix(2000)) }
        var shown = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if result.timedOut { shown += (shown.isEmpty ? "" : "\n") + ServiceText.timedOut }
        // `status` exits 3 when the service is down; that is an answer, not a failure.
        return Output(command: name, ok: result.ok || name == "status", text: shown.isEmpty ? ServiceText.exitCode(result.status) : shown)
    }

    func loadChoices(_ id: String, _ field: ServiceManifest.Field) {
        guard let options = field.options, let source = options.command, choices[id]?[field.key] != .loading,
              let entry = entry(id) else { return }
        choices[id, default: [:]][field.key] = .loading
        let home = self.home, cached = loginPath
        Task {
            let outcome = await Task.detached { () -> Result<(options: [ServiceOption], path: String?), Error> in
                Result {
                    let manifest = try ServiceRunner.approved(entry, home: home)
                    guard let command = manifest.command(source) else { throw ServiceRunner.Failure.notApproved }
                    let path = Self.path(home: home, cached: cached)
                    let result = try ServiceRunner.run(command, of: manifest, settings: nil, environment: ServiceEnvironment.make(path: path.path))
                    guard let parsed = ServiceOption.parse(result.stdout, options: options) else {
                        throw ServiceText.Unreadable(status: result.status)
                    }
                    return (parsed, path.login)
                }
            }.value
            switch outcome {
            case let .success((found, path)):
                loginPath = loginPath ?? path
                // What a choice shows comes from the service: masked like everything else it prints.
                let known = approved(id).map { Array(secretValues($0).values) } ?? []
                func m(_ text: String?) -> String? { text.map { ServiceLogs.mask($0, secrets: known) } }
                let options = found.map {
                    ServiceOption(value: $0.value, label: m($0.label) ?? $0.value, enabled: $0.enabled, detail: m($0.detail),
                                  version: m($0.version), login: m($0.login), sets: $0.sets)
                }
                choices[id, default: [:]][field.key] = .loaded(options)
                // A CLI that moved since it was picked: keep what the choice fills in current.
                if let current = options.first(where: { $0.value == self.value(id, field) && $0.enabled }) { choose(id, field, current) }
            case let .failure(error):
                choices[id, default: [:]][field.key] = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Status and logs

    /// While Settings shows the section: status and logs every two seconds.
    func watch() {
        watchers += 1
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func unwatch() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    /// Only approved manifests: the paths of a changed one are not read before the user approves them.
    func refresh() {
        for entry in entries {
            guard let manifest = approved(entry.id) else { status[entry.id] = nil; running[entry.id] = false; lastError[entry.id] = nil; continue }
            let state = manifest.status.flatMap(ServiceStatus.read)?.masked(secrets: Array(secretValues(manifest).values))
            status[entry.id] = state
            running[entry.id] = state?.isRunning() ?? false
            lastError[entry.id] = state?.lastError
        }
        refreshLogs()
    }

    @Published var logName: [String: String] = [:]

    private var readingLogs = false

    /// Reads and masks off the main thread: a log line can be long.
    func refreshLogs() {
        guard !readingLogs, let id = selected, let manifest = approved(id) else { return }
        let name = logName[id] ?? manifest.logs.first?.name
        guard let log = manifest.logs.first(where: { $0.name == name }) else { logs[id] = []; return }
        let known = Array(secretValues(manifest).values)
        readingLogs = true
        Task {
            let lines = await Task.detached {
                ServiceLogs.tail(log.path, lines: 80).map { String(ServiceLogs.mask($0, secrets: known).prefix(2000)) }
            }.value
            readingLogs = false
            logs[id] = lines
        }
    }

    func revealLog(_ id: String) {
        guard let manifest = approved(id), let log = manifest.logs.first(where: { $0.name == (logName[id] ?? manifest.logs.first?.name) }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: log.path)])
    }

    /// Snapshots: what commands would have printed, without running them.
    func seed(_ id: String, choices: [String: [ServiceOption]] = [:], check: ServiceCheck? = nil, output: Output? = nil) {
        for (key, options) in choices { self.choices[id, default: [:]][key] = .loaded(options) }
        if let check { checks[id] = check }
        if let output { outputs[id] = output }
    }

    /// Services with «Start with Agent Notch» on, if their manifest is still the approved one and their settings are complete.
    func startOnLaunch() {
        for entry in entries where entry.launchWithApp {
            guard let manifest = approved(entry.id), manifest.command("start") != nil, problems(entry.id).isEmpty else { continue }
            if let state = manifest.status.flatMap(ServiceStatus.read), state.isRunning() { continue }
            run(entry.id, "start")
        }
    }
}
