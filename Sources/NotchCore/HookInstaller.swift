import CoreFoundation
import Foundation
import JavaScriptCore

/// Adds and removes our entries in the vendors’ settings.json and hooks.json.
/// Other hooks, keys and their order stay as they were (JSON is edited with JavaScript, which keeps key order);
/// the previous file is kept next to it as `<name>.agents-notch-backup`.
public struct HookInstaller: Sendable {
    public let home: URL
    /// Where the helper is copied, so the hooks keep working when the app moves.
    public let helper: URL
    /// How long a permission request waits for a click before the agent asks in its own window.
    public static let wait = 100

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        helper = home.appendingPathComponent("Library/Application Support/AgentsNotch/notch-hook")
    }

    public func file(_ v: Vendor) -> URL {
        ConfigRoots(home: home).root(v).appendingPathComponent(v == .claude ? "settings.json" : "hooks.json")
    }

    /// One hook entry: the event, its options, and for a matcher group the tools it covers.
    struct Entry {
        let event: String
        var opts: [String: Any] = [:]
        var matcher: String?
        /// Appended to the command: `--wait` tells notch-hook this entry is the one that holds the call for a click.
        var args = ""
    }

    /// Tools answered through PreToolUse: Claude takes `permissionDecision` + `updatedInput` there.
    static let answerMatcher = AnswerTools.names.joined(separator: "|")

    /// Everything except the permission request and the answer entry returns at once.
    /// Claude keeps the async PreToolUse entry for activity and adds a synchronous one for the question and plan tools.
    static func events(_ v: Vendor) -> [Entry] {
        let ask: [String: Any] = ["timeout": wait + 10]
        switch v {
        case .claude:
            let quick: [String: Any] = ["async": true]
            return [Entry(event: "PermissionRequest", opts: ask), Entry(event: "Notification", opts: quick),
                    Entry(event: "PreToolUse", opts: quick), Entry(event: "PreToolUse", opts: ask, matcher: answerMatcher, args: " --wait"),
                    Entry(event: "PostToolUse", opts: quick), Entry(event: "UserPromptSubmit", opts: quick),
                    Entry(event: "Stop", opts: quick), Entry(event: "SessionEnd", opts: quick)]
        case .codex:
            return [Entry(event: "PermissionRequest", opts: ask), Entry(event: "PreToolUse"), Entry(event: "PostToolUse"),
                    Entry(event: "UserPromptSubmit"), Entry(event: "Stop"), Entry(event: "SessionEnd", opts: ["timeout": 1])]
        }
    }

    /// Remaining managed hooks still need the helper refreshed after the app moves.
    public func hasManagedHook(_ v: Vendor) -> Bool {
        guard let text = try? String(contentsOf: file(v), encoding: .utf8),
              let object = HookDecision.object(text), let hooks = object["hooks"] as? Rec else { return false }
        let command = "\"\(helper.path)\" \(v.rawValue)"
        return hooks.values.contains { value in
            (value as? [Rec] ?? []).contains { group in
                (group["hooks"] as? [Rec] ?? []).contains { hook in
                    guard hook["type"] as? String == "command", let text = hook["command"] as? String else { return false }
                    return text == command || text == command + " --wait"
                }
            }
        }
    }

    public func isInstalled(_ v: Vendor) -> Bool {
        guard let text = try? String(contentsOf: file(v), encoding: .utf8),
              let object = HookDecision.object(text), let hooks = object["hooks"] as? Rec else { return false }
        return Self.events(v).allSatisfy { entry in
            (hooks[entry.event] as? [Rec] ?? []).contains { group in
                if let value = group["matcher"], !(value is String) { return false }
                let matcher = (group["matcher"] as? String)?.nilIfEmpty
                guard matcher == entry.matcher else { return false }
                return (group["hooks"] as? [Rec] ?? []).contains { hook in
                    if let value = hook["async"] {
                        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
                    }
                    if let value = hook["timeout"] {
                        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                              number.doubleValue >= 1, number.doubleValue.rounded() == number.doubleValue else { return false }
                    }
                    guard hook["type"] as? String == "command",
                          hook["command"] as? String == "\"\(helper.path)\" \(v.rawValue)" + entry.args,
                          (hook["async"] as? Bool ?? false) == (entry.opts["async"] as? Bool ?? false) else { return false }
                    return entry.opts.allSatisfy { key, value in
                        (hook[key] as? NSObject)?.isEqual(value) == true
                    }
                }
            }
        }
    }

    private var managedCommands: [String] {
        [Vendor.claude, .codex].flatMap { v in
            let command = "\"\(helper.path)\" \(v.rawValue)"
            return [command, command + " --wait"]
        }
    }

    static let appPinName = "app-path"
    /// The app executable the helper may answer to, written by the app that placed it.
    public var appPin: URL { helper.deletingLastPathComponent().appendingPathComponent(Self.appPinName) }

    /// Copies the helper from the app bundle when it is missing or differs, and pins the app that may answer it.
    public func placeHelper(from bundled: URL, app: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pin = appPin.appendingPathExtension("new")
        try? fm.removeItem(at: pin)
        guard fm.createFile(atPath: pin.path, contents: Data((app + "\n").utf8), attributes: [.posixPermissions: 0o600]) else {
            throw POSIXError(.EIO)
        }
        guard rename(pin.path, appPin.path) == 0 else { throw POSIXError(.EIO) }
        if fm.contentsEqual(atPath: bundled.path, andPath: helper.path) { return }
        let tmp = helper.appendingPathExtension("new")
        try? fm.removeItem(at: tmp)
        try fm.copyItem(at: bundled, to: tmp)
        _ = try fm.replaceItemAt(helper, withItemAt: tmp)
        chmod(helper.path, 0o755)
    }

    private func pathRecord(_ v: Vendor) -> URL {
        helper.deletingLastPathComponent().appendingPathComponent("hook-paths-\(v.rawValue).json")
    }

    private func recordedPaths(_ v: Vendor) throws -> [String] {
        let record = pathRecord(v)
        guard FileManager.default.fileExists(atPath: record.path) else { return [] }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: record))
    }

    private func remember(_ url: URL, for v: Vendor) throws {
        var paths = try recordedPaths(v)
        guard !paths.contains(url.path) else { return }
        paths.append(url.path)
        let record = pathRecord(v)
        try FileManager.default.createDirectory(at: record.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(paths).write(to: record, options: .atomic)
        chmod(record.path, 0o600)
    }

    public func install(_ v: Vendor) throws {
        try ConnectionReceipt(installer: self).reset(v)
        try edit(v, at: file(v), add: true)
    }
    public func uninstall(_ v: Vendor) throws {
        var paths = [file(v).path]
        var failures: [String] = []
        do { paths += try recordedPaths(v) }
        catch { failures.append("\(pathRecord(v).path): \(error.localizedDescription)") }
        for path in Set(paths).sorted() {
            do { try edit(v, at: URL(fileURLWithPath: path), add: false) }
            catch { failures.append("\(path): \(error.localizedDescription)") }
        }
        // Retain the history so failed paths can be retried on the next uninstall.
        if !failures.isEmpty {
            throw NSError(domain: "HookInstaller", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "\n")])
        }
        try ConnectionReceipt(installer: self).reset(v)
    }

    /// Edits both vendors even when one config cannot be changed.
    public func editHooks(install: Bool) -> Int32 {
        var failed = false
        for v in [Vendor.claude, .codex] {
            do {
                try install ? self.install(v) : uninstall(v)
                print("\(v.rawValue): \(isInstalled(v) ? "installed" : "removed") in \(file(v).path)")
            } catch {
                FileHandle.standardError.write(Data("\(v.rawValue): \(error.localizedDescription)\n".utf8))
                failed = true
            }
        }
        return failed ? 1 : 0
    }

    private func edit(_ v: Vendor, at file: URL, add: Bool) throws {
        // A symlinked settings file (dotfile managers) is edited where it really lives.
        let url = file.resolvingSymlinksInPath()
        let fm = FileManager.default
        // A symlink pointing nowhere: leave it for the person to fix rather than replace it with a file.
        if (try? fm.destinationOfSymbolicLink(atPath: file.path)) != nil && !fm.fileExists(atPath: url.path) {
            throw POSIXError(.ENOENT)
        }
        // Only a missing file counts as empty: one that cannot be read must never be overwritten.
        let entries = add ? Self.events(v).map { e in
            ["event": e.event, "opts": e.opts, "matcher": e.matcher ?? "", "args": e.args] as [String: Any]
        } : []
        let spec: [String: Any] = ["command": "\"\(helper.path)\" \(v.rawValue)", "managedCommands": managedCommands, "entries": entries]
        var mode = 0o644
        try HookFileUpdate.apply(read: {
            fm.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .utf8) : ""
        }, merge: { text in
            do { return try Self.merge(text, spec: spec) }
            catch {
                throw NSError(domain: "HookInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "Cannot edit \(url.path); file left unchanged. \(error.localizedDescription)"])
            }
        }, prepare: { old in
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            mode = (try? fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? 0o644
            let backup = url.appendingPathExtension("agents-notch-backup")
            if !old.isEmpty && !fm.fileExists(atPath: backup.path) {
                try Data(old.utf8).write(to: backup)
                chmod(backup.path, 0o600)
            }
        }, write: { _, next in
            // Record first: a state-write failure must not leave an untracked hook behind.
            if add { try remember(url, for: v) }
            try Data(next.utf8).write(to: url, options: .atomic)
            chmod(url.path, mode_t(mode))
        })
    }

    static let script = """
    function merge(text, spec) {
      const d = text.trim() ? JSON.parse(text) : {};
      if (!d || typeof d !== 'object' || Array.isArray(d)) throw new Error('Expected a JSON object');
      const hooks = d.hooks || {};
      let removed = false;
      for (const ev of Object.keys(hooks)) {
        hooks[ev] = hooks[ev].flatMap(g => {
          const kept = (g.hooks || []).filter(h => !spec.managedCommands.includes(h.command));
          if (kept.length === (g.hooks || []).length) return [g];
          removed = true;
          return kept.length ? [Object.assign({}, g, { hooks: kept })] : [];
        });
        if (!hooks[ev].length) delete hooks[ev];
      }
      if (!removed && !spec.entries.length) return text;
      for (const e of spec.entries) {
        const h = Object.assign({ type: 'command', command: spec.command + e.args }, e.opts);
        (hooks[e.event] = hooks[e.event] || []).push(e.matcher ? { matcher: e.matcher, hooks: [h] } : { hooks: [h] });
      }
      if (Object.keys(hooks).length) d.hooks = hooks; else delete d.hooks;
      return JSON.stringify(d, null, 2) + '\\n';
    }
    """

    static func merge(_ text: String, spec: [String: Any]) throws -> String {
        guard let ctx = JSContext() else { throw POSIXError(.ENOMEM) }
        var failure: (message: String, syntax: Bool)?
        ctx.exceptionHandler = { _, e in
            if let e { failure = (e.toString(), e.forProperty("name")?.toString() == "SyntaxError") }
        }
        ctx.evaluateScript(script)
        let out = ctx.objectForKeyedSubscript("merge")?.call(withArguments: [text, spec])
        if let failure {
            let hint = failure.syntax ? "Strict JSON object required; comments and trailing commas are not supported. " : ""
            throw NSError(domain: "HookInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey:
                hint + failure.message])
        }
        guard let s = out?.toString() else { throw POSIXError(.EINVAL) }
        return s
    }
}
