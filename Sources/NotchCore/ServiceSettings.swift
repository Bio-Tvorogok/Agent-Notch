import Foundation

/// A service the user added: where it lives, what they approved, and the settings that are not secret.
/// Secrets never land here; they live in the Keychain (`ServiceSecretStore`).
public struct ServiceEntry: Codable, Equatable, Sendable {
    public let id: String
    public let folder: String
    /// The manifest fingerprint the user approved. A changed manifest runs nothing until approved again.
    public var approved: String
    /// Field values and what a choice fills in (`sets`).
    public private(set) var values: [String: String]
    public var launchWithApp: Bool
    /// What the approved manifest runs, by command: a later approval shows what changed.
    public var approvedCommands: [String: String]?

    public init(manifest: ServiceManifest) {
        id = manifest.id
        folder = manifest.root
        approved = manifest.fingerprint
        values = [:]
        launchWithApp = false
        approvedCommands = manifest.commandSummary
    }

    /// The Keychain scope of its secrets.
    public var secretScope: String { ServiceManifest.secretScope(id: id, folder: folder) }

    /// Stores a plain value; nil or empty clears it. Secret fields are refused, so a slip cannot write a token to preferences.
    @discardableResult
    public mutating func set(_ value: String?, for key: String, in manifest: ServiceManifest) -> Bool {
        guard ServiceValues.plainKeys(manifest).contains(key) else { return false }
        if let value, !value.isEmpty { values[key] = value } else { values[key] = nil }
        return true
    }

    /// Picks a choice of a select and copies what it fills in.
    public mutating func choose(_ option: ServiceOption, for field: ServiceManifest.Field, in manifest: ServiceManifest) {
        set(option.value, for: field.key, in: manifest)
        for (target, value) in option.sets { set(value, for: target, in: manifest) }
    }
}

/// The form's values and the settings object a `config: true` command reads.
public enum ServiceValues {
    public enum Problem: Equatable, Sendable { case required, pattern, choice }

    /// Search semantics, like JavaScript's `RegExp.test`: patterns anchor themselves with ^ and $.
    public static func matches(_ value: String, _ pattern: String) -> Bool {
        let regex: NSRegularExpression
        if let cached = compiled.object(forKey: pattern as NSString) { regex = cached }
        else {
            guard let fresh = try? NSRegularExpression(pattern: pattern) else { return false }
            compiled.setObject(fresh, forKey: pattern as NSString)
            regex = fresh
        }
        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    /// The form checks on every redraw; compile each pattern once.
    private static let compiled = NSCache<NSString, NSRegularExpression>()

    /// Keys a `ServiceEntry` may hold: every non-secret field and every setting a choice fills in.
    public static func plainKeys(_ manifest: ServiceManifest) -> Set<String> {
        var keys = Set(manifest.fields.filter { $0.kind != .secret }.map(\.key))
        for field in manifest.fields { for targets in (field.options?.sets ?? [:]).values { keys.formUnion(targets.keys) } }
        return keys
    }

    /// The stored value without surrounding whitespace or, failing that, the default.
    public static func value(_ field: ServiceManifest.Field, entry: ServiceEntry, secrets: [String: String]) -> String? {
        let value = (field.kind == .secret ? secrets[field.key] : entry.values[field.key])?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty { return value }
        return field.kind == .secret ? nil : field.defaultValue
    }

    /// Whether the form shows a field: every field its `when` names is shown and has one of the listed values.
    public static func visible(_ field: ServiceManifest.Field, in manifest: ServiceManifest, entry: ServiceEntry) -> Bool {
        visibleKeys(manifest, entry: entry).contains(field.key)
    }

    /// Every shown field at once, each worked out once: conditions can share fields, and walking every path through them
    /// on each redraw would grow exponentially with a manifest built that way.
    public static func visibleKeys(_ manifest: ServiceManifest, entry: ServiceEntry) -> Set<String> {
        var known: [String: Bool] = [:]
        func shown(_ field: ServiceManifest.Field) -> Bool {
            if let answer = known[field.key] { return answer }
            known[field.key] = false
            let answer = field.when.allSatisfy { key, allowed in
                guard let other = manifest.field(key) else { return false }
                return shown(other) && value(other, entry: entry, secrets: [:]).map(allowed.contains) == true
            }
            known[field.key] = answer
            return answer
        }
        return Set(manifest.fields.filter(shown).map(\.key))
    }

    /// What stops the settings from being sent, by field key: only shown fields, and with a command's `needs` only those.
    /// `choices` are the loaded options of command-backed selects.
    public static func problems(_ manifest: ServiceManifest, entry: ServiceEntry, secrets: [String: String],
                                choices: [String: [ServiceOption]] = [:], for command: ServiceManifest.Command? = nil) -> [String: Problem] {
        var problems: [String: Problem] = [:]
        let shown = visibleKeys(manifest, entry: entry)
        for field in manifest.fields where shown.contains(field.key) && command?.needs?.contains(field.key) != false {
            guard let value = value(field, entry: entry, secrets: secrets) else {
                if field.required { problems[field.key] = .required }
                continue
            }
            if let pattern = field.pattern, !matches(value, pattern) { problems[field.key] = .pattern }
            if let options = field.options {
                if options.command == nil, !options.values.contains(where: { $0.value == value }) { problems[field.key] = .choice }
                if let loaded = choices[field.key], !loaded.contains(where: { $0.value == value && $0.enabled }) { problems[field.key] = .choice }
            }
        }
        return problems
    }

    /// One JSON object of strings, keys sorted: the shown fields and what their choices fill in, cut down to the command's
    /// `needs` when it has them. Holds secrets: only ever written to the command's settings descriptor.
    public static func payload(_ manifest: ServiceManifest, entry: ServiceEntry, secrets: [String: String],
                               for command: ServiceManifest.Command? = nil) -> Data {
        var object: [String: String] = [:]
        let shown = visibleKeys(manifest, entry: entry)
        for field in manifest.fields where shown.contains(field.key) {
            guard let value = value(field, entry: entry, secrets: secrets) else { continue }
            object[field.key] = value
            for target in (field.options?.sets[value] ?? [:]).keys {
                if let filled = entry.values[target], !filled.isEmpty { object[target] = filled }
            }
        }
        if let needs = command?.needs { object = object.filter { needs.contains($0.key) } }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    }

    /// The secret fields a command's payload can hold.
    public static func secretKeys(_ manifest: ServiceManifest, for command: ServiceManifest.Command) -> Set<String> {
        guard command.config else { return [] }
        return Set(manifest.fields.filter { $0.kind == .secret && command.needs?.contains($0.key) != false }.map(\.key))
    }

    /// What a command is given on its descriptor, from every stored secret: only the secrets it may get go into building it,
    /// and `payload` cuts the rest to its `needs`. nil for a command without `config`.
    public static func settings(for command: ServiceManifest.Command, of manifest: ServiceManifest, entry: ServiceEntry,
                                secrets: [String: String]) -> Data? {
        guard command.config else { return nil }
        let given = secretKeys(manifest, for: command)
        return payload(manifest, entry: entry, secrets: secrets.filter { given.contains($0.key) }, for: command)
    }
}

/// One choice of a command-backed select, from the JSON array the command prints.
public struct ServiceOption: Equatable, Sendable, Identifiable {
    public let value: String
    public let label: String
    public let enabled: Bool
    /// How the user is signed in, for example «claude.ai (max)».
    public let detail: String?
    public let version: String?
    /// What to run to sign in, as the service printed it. Shown, never run: it is not a manifest command.
    public let login: String?
    /// Setting key → value, from the manifest's `sets` for this choice.
    public let sets: [String: String]
    public var id: String { value }

    public init(value: String, label: String, enabled: Bool, detail: String? = nil, version: String? = nil,
                login: String? = nil, sets: [String: String] = [:]) {
        self.value = value; self.label = label; self.enabled = enabled
        self.detail = detail; self.version = version; self.login = login; self.sets = sets
    }

    /// nil when the output is not a JSON array; entries without a usable value are skipped.
    public static func parse(_ data: Data, options: ServiceManifest.Options) -> [ServiceOption]? {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return nil }
        func text(_ any: Any?) -> String? {
            guard let text = any as? String, !text.isEmpty, text.count <= 500, ServiceManifest.plain(text) else { return nil }
            return text
        }
        var seen = Set<String>()
        return array.prefix(32).compactMap { item -> ServiceOption? in
            guard let object = item as? [String: Any], let value = text(object[options.valueKey]), seen.insert(value).inserted else { return nil }
            let enabled = options.enabledWhen.map { (object[$0] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false } ?? true
            var sets: [String: String] = [:]
            for (target, property) in options.sets[value] ?? [:] { sets[target] = text(object[property]) }
            return ServiceOption(value: value, label: text(object[options.labelKey]) ?? value, enabled: enabled,
                                 detail: text(object["method"]) ?? text(object["detail"]), version: text(object["version"]),
                                 login: text(object["login"]), sets: sets)
        }
    }
}
