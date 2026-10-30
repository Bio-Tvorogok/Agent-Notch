import CryptoKit
import Foundation

/// A service the app runs and configures from Settings → Services: a folder whose manifest describes the settings form,
/// the commands and where the service keeps its status and logs (docs/services.md).
/// The user approves what a manifest runs, so parsing refuses anything it would have to guess.
public struct ServiceManifest: Equatable, Sendable {
    public static let version = 1
    /// Where a service folder keeps its manifest, in the order they are tried.
    public static let locations = ["ops/agent-notch.json", "agent-notch.json"]
    static let maxBytes = 256 * 1024
    /// Commands with a meaning of their own, in the order the app lists them.
    public static let knownCommands = ["start", "stop", "restart", "status", "check-pc", "providers"]
    static let defaultTimeout: TimeInterval = 180

    public struct Field: Equatable, Sendable {
        public enum Kind: String, Sendable { case string, secret, select }
        public let key: String
        public let label: String
        public let help: String?
        public let placeholder: String?
        public let kind: Kind
        public let required: Bool
        public let pattern: String?
        public let defaultValue: String?
        public let options: Options?
    }

    /// A select's choices: listed in the manifest, or the JSON array a command prints.
    public struct Options: Equatable, Sendable {
        public let values: [Choice]
        public let command: String?
        public let valueKey: String
        public let labelKey: String
        /// A property that must be true for a choice to be selectable, such as `loggedIn`.
        public let enabledWhen: String?
        /// Choice value → setting key → the choice's property copied into that setting when the choice is picked.
        public let sets: [String: [String: String]]
    }

    public struct Choice: Equatable, Sendable {
        public let value: String
        public let label: String
    }

    public struct Command: Equatable, Sendable {
        public let name: String
        public let run: [String]
        public let label: String?
        /// The settings go to the descriptor in `settings.fd`.
        public let config: Bool
        /// Stdout is JSON.
        public let json: Bool
        public let timeout: TimeInterval
        /// `run[0]` resolved inside the service folder.
        public let executable: String
    }

    public struct Log: Equatable, Sendable {
        public let name: String
        public let path: String
    }

    public let id: String
    public let name: String
    public let description: String?
    /// The folder the user picked, symlinks resolved.
    public let root: String
    public let manifestPath: String
    /// Where every command runs.
    public let cwd: String
    public let configFD: Int32?
    public let fields: [Field]
    public let commands: [Command]
    /// Absolute paths; `~` is the user's home.
    public let status: String?
    public let logs: [Log]
    /// SHA-256 of the manifest bytes: approval is for exactly this text.
    public let fingerprint: String

    public func command(_ name: String) -> Command? { commands.first { $0.name == name } }

    /// Where its secrets live: the id and a hash of the folder, so another folder that claims the same id gets none of them.
    public var secretScope: String { Self.secretScope(id: id, folder: root) }
    static func secretScope(id: String, folder: String) -> String {
        id + "." + SHA256.hash(data: Data(folder.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// Each command as the approval sheet shows it, for comparing with what was approved before.
    public var commandSummary: [String: String] {
        Dictionary(uniqueKeysWithValues: commands.map { command in
            let resolved = String(command.executable.dropFirst(root.count + 1))
            return (command.name, command.run.joined(separator: " ") + " → " + resolved + (command.config ? " [settings]" : ""))
        })
    }
    public func field(_ key: String) -> Field? { fields.first { $0.key == key } }

    /// Reads the manifest from a service folder.
    public static func load(folder: String, home: String = NSHomeDirectory()) throws -> ServiceManifest {
        guard let root = canonical(folder), isDirectory(root) else { throw ServiceManifestError(.notFound, folder) }
        guard safe(root) else { throw ServiceManifestError(.unsafePermissions, root) }
        guard let relative = locations.first(where: { FileManager.default.fileExists(atPath: root + "/" + $0) }) else {
            throw ServiceManifestError(.notFound, root)
        }
        guard let path = canonical(root + "/" + relative), inside(path, root) else { throw ServiceManifestError(.outsideFolder, relative) }
        guard safe(path), safe((path as NSString).deletingLastPathComponent) else { throw ServiceManifestError(.unsafePermissions, relative) }
        let data: Data
        do { data = try ServiceFiles.contents(path, max: maxBytes) }
        catch ServiceFiles.Failure.tooLarge { throw ServiceManifestError(.tooLarge, relative) }
        catch { throw ServiceManifestError(.notFound, relative) }
        return try parse(data, root: root, manifestPath: path, home: home)
    }

    static func parse(_ data: Data, root: String, manifestPath: String, home: String) throws -> ServiceManifest {
        guard data.count <= maxBytes else { throw ServiceManifestError(.tooLarge, "") }
        guard let any = try? JSONSerialization.jsonObject(with: data), let top = any as? [String: Any] else {
            throw ServiceManifestError(.notJSON, "")
        }
        let r = Reader(top, "")
        guard try r.int("manifest", required: true) == version else { throw ServiceManifestError(.unsupportedVersion, "manifest") }
        let id = try r.string("id", required: true)!
        guard matches(id, #"^[a-z0-9][a-z0-9._-]{0,63}$"#) else { throw ServiceManifestError(.invalid, "id") }
        let name = try r.text("name", required: true, max: 80)!
        let description = try r.text("description", max: 500)

        let cwdText = try r.string("cwd") ?? "."
        let cwd = try folder(cwdText, in: root, path: "cwd")

        var configFD: Int32?
        if let settings = try r.object("settings") {
            let s = Reader(settings, "settings")
            guard try s.string("via", required: true) == "fd" else { throw ServiceManifestError(.invalid, "settings.via") }
            let fd = try s.int("fd", required: true)!
            guard (3...9).contains(fd) else { throw ServiceManifestError(.invalid, "settings.fd") }
            configFD = Int32(fd)
        }

        guard let rawCommands = try r.object("commands", required: true), !rawCommands.isEmpty else {
            throw ServiceManifestError(.missing, "commands")
        }
        guard rawCommands.count <= 32 else { throw ServiceManifestError(.tooMany, "commands") }
        var commands: [Command] = []
        // In the order they are listed, so the first problem reported is always the same one.
        let names = rawCommands.keys.sorted { order($0) < order($1) || order($0) == order($1) && $0 < $1 }
        for commandName in names {
            let value = rawCommands[commandName]!
            let path = "commands.\(commandName)"
            guard matches(commandName, #"^[a-z][a-z0-9-]{0,31}$"#) else { throw ServiceManifestError(.invalid, path) }
            guard let object = value as? [String: Any] else { throw ServiceManifestError(.wrongType, path) }
            commands.append(try command(commandName, object, path: path, root: root, cwd: cwd, configFD: configFD))
        }

        let rawFields = try r.array("fields") ?? []
        guard rawFields.count <= 64 else { throw ServiceManifestError(.tooMany, "fields") }
        var fields: [Field] = []
        for (i, value) in rawFields.enumerated() {
            let path = "fields[\(i)]"
            guard let object = value as? [String: Any] else { throw ServiceManifestError(.wrongType, path) }
            let field = try Self.field(object, path: path, commands: commands)
            guard !fields.contains(where: { $0.key == field.key }) else { throw ServiceManifestError(.duplicate, path + ".key") }
            fields.append(field)
        }
        // A choice may fill extra settings, never one the form asks for: the user's own value would be overwritten.
        for (i, field) in fields.enumerated() {
            for target in field.options?.sets.values.flatMap(\.keys) ?? [] where fields.contains(where: { $0.key == target }) {
                throw ServiceManifestError(.duplicate, "fields[\(i)].options.sets.\(target)")
            }
        }

        let status = try r.string("status").map { try location($0, root: root, home: home, path: "status") }
        var logs: [Log] = []
        if let rawLogs = try r.object("logs") {
            guard rawLogs.count <= 16 else { throw ServiceManifestError(.tooMany, "logs") }
            for (logName, value) in rawLogs.sorted(by: { $0.key < $1.key }) {
                let path = "logs.\(logName)"
                guard matches(logName, #"^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$"#) else { throw ServiceManifestError(.invalid, path) }
                guard let text = value as? String else { throw ServiceManifestError(.wrongType, path) }
                logs.append(Log(name: logName, path: try location(text, root: root, home: home, path: path)))
            }
        }

        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ServiceManifest(id: id, name: name, description: description, root: root, manifestPath: manifestPath, cwd: cwd,
                               configFD: configFD, fields: fields, commands: commands, status: status, logs: logs,
                               fingerprint: fingerprint)
    }

    private static func order(_ name: String) -> Int { knownCommands.firstIndex(of: name) ?? knownCommands.count }

    private static func command(_ name: String, _ object: [String: Any], path: String, root: String, cwd: String,
                                configFD: Int32?) throws -> Command {
        let r = Reader(object, path)
        guard let run = try r.array("run", required: true), (1...64).contains(run.count) else { throw ServiceManifestError(.missing, path + ".run") }
        let args = try run.enumerated().map { i, value -> String in
            guard let arg = value as? String else { throw ServiceManifestError(.wrongType, "\(path).run[\(i)]") }
            guard arg.utf8.count <= 4096, plain(arg), i > 0 || !arg.isEmpty else { throw ServiceManifestError(.invalid, "\(path).run[\(i)]") }
            return arg
        }
        let config = try r.bool("config") ?? false
        if config && configFD == nil { throw ServiceManifestError(.missing, "settings") }
        var timeout = defaultTimeout
        if let seconds = try r.int("timeout") {
            guard (1...3600).contains(seconds) else { throw ServiceManifestError(.invalid, path + ".timeout") }
            timeout = TimeInterval(seconds)
        }
        // Only a program inside the service folder: what the user approved is that folder, not the whole Mac.
        let program = args[0]
        guard !program.hasPrefix("/"), !program.hasPrefix("~") else { throw ServiceManifestError(.outsideFolder, path + ".run[0]") }
        guard let executable = canonical(cwd + "/" + program) else { throw ServiceManifestError(.notExecutable, path + ".run[0]") }
        guard inside(executable, root) else { throw ServiceManifestError(.outsideFolder, path + ".run[0]") }
        var info = stat()
        guard stat(executable, &info) == 0, info.st_mode & S_IFMT == S_IFREG, access(executable, X_OK) == 0 else {
            throw ServiceManifestError(.notExecutable, path + ".run[0]")
        }
        guard safe(executable), safe((executable as NSString).deletingLastPathComponent) else {
            throw ServiceManifestError(.unsafePermissions, path + ".run[0]")
        }
        return Command(name: name, run: args, label: try r.text("label", max: 60), config: config, json: try r.bool("json") ?? false,
                       timeout: timeout, executable: executable)
    }

    private static func field(_ object: [String: Any], path: String, commands: [Command]) throws -> Field {
        let r = Reader(object, path)
        let key = try r.string("key", required: true)!
        guard matches(key, #"^[A-Za-z_][A-Za-z0-9_]{0,63}$"#) else { throw ServiceManifestError(.invalid, path + ".key") }
        let typeName = try r.string("type", required: true)!
        guard let kind = Field.Kind(rawValue: typeName) else { throw ServiceManifestError(.unknownType, path + ".type") }
        let pattern = try r.string("pattern")
        if let pattern, (try? NSRegularExpression(pattern: pattern)) == nil { throw ServiceManifestError(.badPattern, path + ".pattern") }
        if pattern != nil && kind == .select { throw ServiceManifestError(.invalid, path + ".pattern") }
        let defaultValue = try r.string("default")
        if defaultValue != nil && kind == .secret { throw ServiceManifestError(.badDefault, path + ".default") }
        // The default is not matched against the pattern here: parsing runs no manifest regex, which could be built to
        // backtrack for minutes. The form reports a default that does not fit.

        var options: Options?
        if kind == .select {
            guard let raw = try r.object("options", required: true) else { throw ServiceManifestError(.missing, path + ".options") }
            options = try Self.options(raw, path: path + ".options", commands: commands)
            if let defaultValue, options?.command == nil, !(options?.values.contains { $0.value == defaultValue } ?? false) {
                throw ServiceManifestError(.badDefault, path + ".default")
            }
        }
        return Field(key: key, label: try r.text("label", required: true, max: 200)!, help: try r.text("help", max: 1000),
                     placeholder: try r.text("placeholder", max: 200), kind: kind, required: try r.bool("required") ?? false,
                     pattern: pattern, defaultValue: defaultValue, options: options)
    }

    private static func options(_ object: [String: Any], path: String, commands: [Command]) throws -> Options {
        let r = Reader(object, path)
        let rawValues = try r.array("values")
        let command = try r.string("command")
        guard (rawValues == nil) != (command == nil) else { throw ServiceManifestError(.invalid, path) }
        var values: [Choice] = []
        if let rawValues {
            guard !rawValues.isEmpty, rawValues.count <= 64 else { throw ServiceManifestError(.invalid, path + ".values") }
            for (i, value) in rawValues.enumerated() {
                let itemPath = "\(path).values[\(i)]"
                guard let item = value as? [String: Any] else { throw ServiceManifestError(.wrongType, itemPath) }
                let c = Reader(item, itemPath)
                let choice = try c.string("value", required: true)!
                guard !values.contains(where: { $0.value == choice }) else { throw ServiceManifestError(.duplicate, itemPath) }
                values.append(Choice(value: choice, label: try c.text("label", max: 200) ?? choice))
            }
        }
        if let command {
            guard let source = commands.first(where: { $0.name == command }) else { throw ServiceManifestError(.unknownCommand, path + ".command") }
            // Choices come from what the command prints, so it must promise JSON and must not be handed the settings.
            guard source.json, !source.config else { throw ServiceManifestError(.invalid, path + ".command") }
        }
        var sets: [String: [String: String]] = [:]
        for (choice, value) in try r.object("sets") ?? [:] {
            guard let targets = value as? [String: Any] else { throw ServiceManifestError(.wrongType, "\(path).sets.\(choice)") }
            var copied: [String: String] = [:]
            for (target, property) in targets {
                guard matches(target, #"^[A-Za-z_][A-Za-z0-9_]{0,63}$"#), let property = property as? String, !property.isEmpty else {
                    throw ServiceManifestError(.invalid, "\(path).sets.\(choice).\(target)")
                }
                copied[target] = property
            }
            sets[choice] = copied
        }
        return Options(values: values, command: command, valueKey: try r.string("value") ?? "value",
                       labelKey: try r.string("label") ?? "label", enabledWhen: try r.string("enabledWhen"), sets: sets)
    }

    /// `cwd`: a folder inside the service folder.
    private static func folder(_ text: String, in root: String, path: String) throws -> String {
        guard !text.hasPrefix("/"), !text.hasPrefix("~"), plain(text) else { throw ServiceManifestError(.outsideFolder, path) }
        guard let resolved = canonical(root + "/" + text) else { throw ServiceManifestError(.notFound, path) }
        guard inside(resolved, root) else { throw ServiceManifestError(.outsideFolder, path) }
        guard isDirectory(resolved) else { throw ServiceManifestError(.notFound, path) }
        guard safe(resolved) else { throw ServiceManifestError(.unsafePermissions, path) }
        return resolved
    }

    /// A status or log file: `~/…`, absolute, or relative to the service folder. The file may not exist yet.
    private static func location(_ text: String, root: String, home: String, path: String) throws -> String {
        guard !text.isEmpty, plain(text) else { throw ServiceManifestError(.invalid, path) }
        let expanded: String
        if text == "~" || text.hasPrefix("~/") { expanded = home + text.dropFirst() }
        else if text.hasPrefix("~") { throw ServiceManifestError(.invalid, path) }
        else if text.hasPrefix("/") { expanded = text }
        else { expanded = root + "/" + text }
        return (expanded as NSString).standardizingPath
    }

    // MARK: - File system

    static func canonical(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func inside(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    private static func isDirectory(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    /// Owned by this user (or root) and writable by no one else, by mode or ACL: another account cannot change it.
    static func safe(_ path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0, info.st_uid == getuid() || info.st_uid == 0, info.st_mode & 0o022 == 0 else { return false }
        return !ServiceFiles.aclGrantsWrite(path)
    }

    // MARK: - Text

    static func matches(_ text: String, _ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }

    /// No control, invisible formatting or line-breaking characters: a right-to-left override or a line separator could make
    /// an approved command read differently.
    static func plain(_ text: String) -> Bool {
        !text.unicodeScalars.contains(where: hidden)
    }

    static func hidden(_ scalar: Unicode.Scalar) -> Bool {
        [.control, .format, .lineSeparator, .paragraphSeparator].contains(scalar.properties.generalCategory)
    }
}

public struct ServiceManifestError: LocalizedError, Equatable, Sendable {
    public enum Problem: Equatable, Sendable {
        case notFound, tooLarge, notJSON, unsupportedVersion, missing, wrongType, invalid, outsideFolder, duplicate,
             unknownType, badPattern, badDefault, unknownCommand, notExecutable, unsafePermissions, tooMany
    }
    public let problem: Problem
    /// Where in the manifest: `fields[2].pattern`, `commands.start.run[0]`.
    public let path: String

    public init(_ problem: Problem, _ path: String) {
        self.problem = problem
        // Paths can carry the manifest's own key names; they reach an alert, so only plain text and not too much of it.
        self.path = String(String(path.unicodeScalars.filter { !ServiceManifest.hidden($0) }).prefix(160))
    }

    public var errorDescription: String? {
        let text: String = switch problem {
        case .notFound: Loc.t("No service manifest (ops/agent-notch.json) here", "Здесь нет манифеста сервиса (ops/agent-notch.json)")
        case .tooLarge: Loc.t("The manifest is too large", "Манифест слишком большой")
        case .notJSON: Loc.t("The manifest is not a JSON object", "Манифест — не JSON-объект")
        case .unsupportedVersion: Loc.t("Unsupported manifest version", "Неподдерживаемая версия манифеста")
        case .missing: Loc.t("Required entry is missing", "Нет обязательной записи")
        case .wrongType: Loc.t("Wrong value type", "Неверный тип значения")
        case .invalid: Loc.t("Invalid value", "Недопустимое значение")
        case .outsideFolder: Loc.t("Points outside the service folder", "Указывает за пределы папки сервиса")
        case .duplicate: Loc.t("Repeated name", "Повторяющееся имя")
        case .unknownType: Loc.t("Unknown field type", "Неизвестный тип поля")
        case .badPattern: Loc.t("The pattern is not a valid regular expression", "Шаблон — неверное регулярное выражение")
        case .badDefault: Loc.t("The default value does not fit the field", "Значение по умолчанию не подходит полю")
        case .unknownCommand: Loc.t("Refers to a command the manifest does not have", "Ссылается на команду, которой нет в манифесте")
        case .notExecutable: Loc.t("The program is missing or not executable", "Программы нет или она не исполняемая")
        case .unsafePermissions: Loc.t("Other users can change this file", "Этот файл могут менять другие пользователи")
        case .tooMany: Loc.t("Too many entries", "Слишком много записей")
        }
        return path.isEmpty ? text : "\(text): \(path)"
    }
}

/// Typed reads from a JSON object, failing with the entry's manifest path.
private struct Reader {
    let object: [String: Any]
    let path: String
    init(_ object: [String: Any], _ path: String) { self.object = object; self.path = path }

    private func at(_ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }

    private func value(_ key: String, required: Bool) throws -> Any? {
        guard let value = object[key], !(value is NSNull) else {
            if required { throw ServiceManifestError(.missing, at(key)) }
            return nil
        }
        return value
    }

    func string(_ key: String, required: Bool = false) throws -> String? {
        guard let value = try value(key, required: required) else { return nil }
        guard let text = value as? String else { throw ServiceManifestError(.wrongType, at(key)) }
        guard text.utf8.count <= 4096, !text.contains("\0") else { throw ServiceManifestError(.invalid, at(key)) }
        return text
    }

    /// Shown to the user: not empty, one line of plain text.
    func text(_ key: String, required: Bool = false, max: Int) throws -> String? {
        guard let text = try string(key, required: required) else { return nil }
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, text.count <= max, text.utf8.count <= max * 4,
              ServiceManifest.plain(text) else {
            throw ServiceManifestError(.invalid, at(key))
        }
        return text
    }

    func bool(_ key: String) throws -> Bool? {
        guard let value = try value(key, required: false) else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw ServiceManifestError(.wrongType, at(key)) }
        return number.boolValue
    }

    func int(_ key: String, required: Bool = false) throws -> Int? {
        guard let value = try value(key, required: required) else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == number.doubleValue.rounded(), abs(number.doubleValue) < 1e9 else {
            throw ServiceManifestError(.wrongType, at(key))
        }
        return number.intValue
    }

    func object(_ key: String, required: Bool = false) throws -> [String: Any]? {
        guard let value = try value(key, required: required) else { return nil }
        guard let object = value as? [String: Any] else { throw ServiceManifestError(.wrongType, at(key)) }
        return object
    }

    func array(_ key: String, required: Bool = false) throws -> [Any]? {
        guard let value = try value(key, required: required) else { return nil }
        guard let array = value as? [Any] else { throw ServiceManifestError(.wrongType, at(key)) }
        return array
    }
}
