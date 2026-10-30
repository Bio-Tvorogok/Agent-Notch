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
                filledSecrets[entry.id] = Set(manifest.fields.filter { $0.kind == .secret && secrets.contains(entry.id, $0.key) }.map(\.key))
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
            pending = Pending(manifest: manifest, changed: entries.contains { $0.id == manifest.id })
        } catch {
            problem = error.localizedDescription
        }
    }

    func review(_ id: String) {
        if case let .changed(manifest) = manifests[id] { pending = Pending(manifest: manifest, changed: true) }
    }

    func approve(_ manifest: ServiceManifest) {
        pending = nil
        if entries.contains(where: { $0.id == manifest.id }) {
            update(manifest.id) { $0.approved = manifest.fingerprint }
        } else {
            entries.append(ServiceEntry(manifest: manifest))
            save()
        }
        selected = manifest.id
        reloadManifests()
        refresh()
    }

    /// Forgets the service and deletes its secrets from the Keychain. The service's own files stay.
    func remove(_ id: String) {
        let keys = shown(id)?.fields.filter { $0.kind == .secret }.map(\.key) ?? []
        secrets.removeAll(id, keys: keys)
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
        update(id) { $0.set(value.trimmingCharacters(in: .whitespacesAndNewlines), for: field.key, in: manifest) }
    }

    func choose(_ id: String, _ field: ServiceManifest.Field, _ option: ServiceOption) {
        guard let manifest = shown(id) else { return }
        update(id) { $0.choose(option, for: field, in: manifest) }
    }

    func setSecret(_ id: String, _ key: String, _ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try secrets.write(trimmed, id, key)
            secretCache[id] = nil
            if trimmed?.isEmpty == false { filledSecrets[id, default: []].insert(key) } else { filledSecrets[id]?.remove(key) }
        } catch {
            problem = error.localizedDescription
        }
    }

    func setLaunchWithApp(_ id: String, _ on: Bool) { update(id) { $0.launchWithApp = on } }

    private func secretValues(_ manifest: ServiceManifest) -> [String: String] {
        if let cached = secretCache[manifest.id] { return cached }
        let values = secrets.all(manifest)
        secretCache[manifest.id] = values
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
            let outcome = await Task.detached { () -> Result<(ServiceManifest, ServiceRunner.Result, [String]), Error> in
                Result {
                    let manifest = try ServiceRunner.approved(entry, home: home)
                    guard let command = manifest.command(name) else { throw ServiceRunner.Failure.notApproved }
                    let values = secrets.all(manifest)
                    if Self.needsComplete(command), !ServiceValues.problems(manifest, entry: entry, secrets: values).isEmpty {
                        throw ServiceText.Incomplete()
                    }
                    let path = cached ?? ServiceEnvironment.loginPath(home: home) ?? ServiceEnvironment.fallbackPath(home: home)
                    let payload = command.config ? ServiceValues.payload(manifest, entry: entry, secrets: values) : nil
                    let result = try ServiceRunner.run(command, of: manifest, settings: payload, environment: ServiceEnvironment.make(path: path))
                    return (manifest, result, Array(values.values) + [path])
                }
            }.value
            busy[id] = nil
            switch outcome {
            case let .success((manifest, result, known)):
                loginPath = known.last
                finish(id, name, manifest: manifest, result: result, secrets: Array(known.dropLast()))
            case let .failure(error):
                if name == "check-pc" { checks[id] = ServiceCheck(ok: false, error: error.localizedDescription) }
                outputs[id] = Output(command: name, ok: false, text: error.localizedDescription)
                if case ServiceRunner.Failure.notApproved = error { reloadManifests() }
            }
            refresh()
        }
    }

    private func finish(_ id: String, _ name: String, manifest: ServiceManifest, result: ServiceRunner.Result, secrets: [String]) {
        if name == "check-pc" {
            checks[id] = ServiceCheck.parse(result, secrets: secrets)
            return
        }
        let text = String(decoding: result.stdout + result.stderr, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false).suffix(60).joined(separator: "\n")
        var shown = ServiceLogs.mask(text, secrets: secrets).trimmingCharacters(in: .whitespacesAndNewlines)
        if result.timedOut { shown += (shown.isEmpty ? "" : "\n") + ServiceText.timedOut }
        // `status` exits 3 when the service is down; that is an answer, not a failure.
        outputs[id] = Output(command: name, ok: result.ok || name == "status", text: shown.isEmpty ? ServiceText.exitCode(result.status) : shown)
    }

    func loadChoices(_ id: String, _ field: ServiceManifest.Field) {
        guard let options = field.options, let source = options.command, choices[id]?[field.key] != .loading,
              let entry = entry(id) else { return }
        choices[id, default: [:]][field.key] = .loading
        let home = self.home, cached = loginPath
        Task {
            let outcome = await Task.detached { () -> Result<[ServiceOption], Error> in
                Result {
                    let manifest = try ServiceRunner.approved(entry, home: home)
                    guard let command = manifest.command(source) else { throw ServiceRunner.Failure.notApproved }
                    let path = cached ?? ServiceEnvironment.loginPath(home: home) ?? ServiceEnvironment.fallbackPath(home: home)
                    let result = try ServiceRunner.run(command, of: manifest, settings: nil, environment: ServiceEnvironment.make(path: path))
                    guard let parsed = ServiceOption.parse(result.stdout, options: options) else {
                        throw ServiceText.Unreadable(status: result.status)
                    }
                    return parsed
                }
            }.value
            switch outcome {
            case let .success(options):
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

    func refresh() {
        for entry in entries {
            guard let manifest = shown(entry.id) else { continue }
            let state = manifest.status.flatMap(ServiceStatus.read)
            status[entry.id] = state
            running[entry.id] = state?.isRunning() ?? false
            lastError[entry.id] = state?.lastError.map { ServiceLogs.mask($0, secrets: Array(secretValues(manifest).values)) }
        }
        refreshLogs()
    }

    @Published var logName: [String: String] = [:]

    func refreshLogs() {
        guard let id = selected, let manifest = shown(id) else { return }
        let name = logName[id] ?? manifest.logs.first?.name
        guard let log = manifest.logs.first(where: { $0.name == name }) else { logs[id] = []; return }
        let known = Array(secretValues(manifest).values)
        logs[id] = ServiceLogs.tail(log.path, lines: 80).map { ServiceLogs.mask($0, secrets: known) }
    }

    func revealLog(_ id: String) {
        guard let manifest = shown(id), let log = manifest.logs.first(where: { $0.name == (logName[id] ?? manifest.logs.first?.name) }) else { return }
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
