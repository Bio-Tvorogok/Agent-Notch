import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

/// Settings → Services: manifests, the settings descriptor, status files, logs and secrets.
struct ServiceChecks {
    let home: String = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notch-services-home-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return ServiceManifest.canonical(url.path) ?? url.path
    }()

    static let script = """
    #!/bin/sh
    case "$1" in
      read) cat <&3 ;;
      fd3) if { : <&3; } 2>/dev/null; then echo open; else echo closed; fi ;;
      fd) if [ -e "/dev/fd/$2" ]; then echo leaked; else echo clean; fi ;;
      env) env; echo "ARGS:$*" ;;
      pwd) pwd -P ;;
      stdin) cat; echo "eof" ;;
      exit) echo "said $2" >&2; exit "$2" ;;
      sleep) sleep 30 ;;
      daemon) (sleep 30 &); echo hi ;;
      flood) head -c 1048576 /dev/zero | tr '\\0' 'x' ;;
      json) printf '%s' "$2"; exit "${3:-0}" ;;
    esac
    """

    /// A service folder with the manifest at ops/agent-notch.json and an executable ops/svc.
    func folder(_ manifest: String, extra: [String: String] = [:]) throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notch-service-\(UUID().uuidString)")
        let ops = root.appendingPathComponent("ops")
        try FileManager.default.createDirectory(at: ops, withIntermediateDirectories: true)
        chmod(root.path, 0o755)
        chmod(ops.path, 0o755)
        try manifest.write(to: ops.appendingPathComponent("agent-notch.json"), atomically: true, encoding: .utf8)
        chmod(ops.appendingPathComponent("agent-notch.json").path, 0o644)
        for (name, text) in ["ops/svc": Self.script].merging(extra, uniquingKeysWith: { $1 }) {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            chmod(url.path, 0o755)
        }
        return ServiceManifest.canonical(root.path)!
    }

    /// A small manifest using ops/svc for every command; `patch` edits the decoded object before it is written.
    func manifest(_ patch: (inout [String: Any]) -> Void = { _ in }) throws -> String {
        var object: [String: Any] = [
            "manifest": 1, "id": "svc", "name": "Test service", "cwd": ".",
            "settings": ["via": "fd", "fd": 3],
            "fields": [
                ["key": "TOKEN", "label": "Token", "type": "secret", "required": true],
                ["key": "OWNER", "label": "Owner", "type": "string", "required": true, "pattern": #"^\d{3,5}$"#],
                ["key": "MODE", "label": "Mode", "type": "select", "default": "on",
                 "options": ["values": [["value": "on", "label": "On"], ["value": "off", "label": "Off"]]]],
                ["key": "BRAIN", "label": "Brain", "type": "select", "default": "claude",
                 "options": ["command": "providers", "value": "id", "label": "name", "enabledWhen": "loggedIn",
                             "sets": ["claude": ["CLAUDE_BIN": "path"], "codex": ["CODEX_BIN": "path"]]]],
            ],
            "commands": [
                "start": ["run": ["ops/svc", "read"], "config": true],
                "stop": ["run": ["ops/svc", "fd3"]],
                "providers": ["run": ["ops/svc", "json", "[]"], "json": true],
                "check-pc": ["run": ["ops/svc", "json", "{}"], "config": true, "json": true],
            ],
            "status": "~/.svc/status.json",
            "logs": ["bot": "~/.svc/bot.log", "local": "logs/x.log"],
        ]
        patch(&object)
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    func load(_ root: String) throws -> ServiceManifest { try ServiceManifest.load(folder: root, home: home) }

    // MARK: - Manifest

    func goshaManifest() throws {
        let text = try String(contentsOfFile: "Tests/Fixtures/Services/chedrik.json", encoding: .utf8)
        let root = try folder(text, extra: ["ops/gosha": "#!/bin/sh\nexit 0\n"])
        let m = try load(root)
        XCTAssertEqual(m.id, "chedrik")
        XCTAssertEqual(m.name, "Гоша")
        XCTAssertEqual(m.root, root)
        XCTAssertEqual(m.cwd, root)
        XCTAssertEqual(m.configFD, 3)
        XCTAssertEqual(m.commands.map(\.name), ["start", "stop", "restart", "status", "check-pc", "providers"])
        XCTAssertEqual(m.command("start")?.run, ["ops/gosha", "start", "--config-fd", "3"])
        XCTAssertEqual(m.command("start")?.executable, root + "/ops/gosha")
        XCTAssertTrue(m.command("start")?.config == true && m.command("stop")?.config == false)
        XCTAssertTrue(m.command("check-pc")?.json == true && m.command("check-pc")?.config == true)
        XCTAssertEqual(m.fields.map(\.key), ["DISCORD_BOT_TOKEN", "OWNER_DISCORD_ID", "VOICE_CHANNEL_ID", "VOICE_TTS",
                                             "VOICESTUDIO_URL", "VOICESTUDIO_API_KEY", "CHEDRIK_PERSONA", "BRAIN_PROVIDER"])
        XCTAssertEqual(m.fields.filter { $0.kind == .secret }.map(\.key), ["DISCORD_BOT_TOKEN", "VOICESTUDIO_API_KEY"])
        let brain = try XCTUnwrap(m.field("BRAIN_PROVIDER")?.options)
        XCTAssertEqual(brain.command, "providers")
        XCTAssertEqual(brain.valueKey, "id")
        XCTAssertEqual(brain.enabledWhen, "loggedIn")
        XCTAssertEqual(brain.sets["codex"], ["CODEX_BIN": "path"])
        XCTAssertEqual(m.field("VOICE_TTS")?.options?.values.map(\.value), ["voicestudio", "off"])
        XCTAssertEqual(m.status, home + "/.chedrik/run/status.json")
        XCTAssertEqual(m.logs.map(\.name), ["bot", "whisper"])
        XCTAssertEqual(m.logs.first?.path, home + "/.chedrik/logs/chedrik.log")
        XCTAssertEqual(m.fingerprint.count, 64)
    }

    func manifestRejects() throws {
        func expect(_ problem: ServiceManifestError.Problem, _ path: String, _ note: String,
                    extra: [String: String] = [:], _ patch: (inout [String: Any]) -> Void) throws {
            let root = try folder(try manifest(patch), extra: extra)
            do {
                _ = try load(root)
                XCTFail("accepted: \(note)")
            } catch let error as ServiceManifestError {
                XCTAssertEqual(error, ServiceManifestError(problem, path), note)
            }
        }
        func command(_ name: String, _ body: [String: Any]) -> (inout [String: Any]) -> Void {
            { o in var c = o["commands"] as! [String: Any]; c[name] = body; o["commands"] = c }
        }
        func field(_ i: Int, _ edit: @escaping (inout [String: Any]) -> Void) -> (inout [String: Any]) -> Void {
            { o in var f = o["fields"] as! [[String: Any]]; edit(&f[i]); o["fields"] = f }
        }
        try expect(.unsupportedVersion, "manifest", "version 2") { $0["manifest"] = 2 }
        try expect(.wrongType, "manifest", "version as a string") { $0["manifest"] = "1" }
        try expect(.invalid, "id", "id with a slash") { $0["id"] = "../svc" }
        try expect(.missing, "name", "no name") { $0["name"] = nil }
        try expect(.invalid, "name", "blank name") { $0["name"] = "  " }
        try expect(.invalid, "name", "right-to-left override") { $0["name"] = "Safe\u{202E}hs.lave" }
        try expect(.outsideFolder, "cwd", "cwd up") { $0["cwd"] = "../" }
        try expect(.outsideFolder, "cwd", "cwd absolute") { $0["cwd"] = "/tmp" }
        try expect(.outsideFolder, "commands.start.run[0]", "absolute program", command("start", ["run": ["/bin/sh", "-c", "id"]]))
        try expect(.outsideFolder, "commands.start.run[0]", "home program", command("start", ["run": ["~/bin/x"]]))
        try expect(.notExecutable, "commands.start.run[0]", "missing program", command("start", ["run": ["ops/nope"]]))
        try expect(.notExecutable, "commands.start.run[0]", "a folder", command("start", ["run": ["ops"]]))
        try expect(.invalid, "commands.start.run[1]", "control character", command("start", ["run": ["ops/svc", "a\u{1B}[2Jb"]]))
        try expect(.missing, "commands.start.run", "empty run", command("start", ["run": [String]()]))
        try expect(.wrongType, "commands.start.config", "config as text", command("start", ["run": ["ops/svc"], "config": "yes"]))
        try expect(.invalid, "commands.start.timeout", "zero timeout", command("start", ["run": ["ops/svc"], "timeout": 0]))
        try expect(.invalid, "commands.Start", "command name", command("Start", ["run": ["ops/svc"]]))
        try expect(.missing, "commands", "no commands") { $0["commands"] = nil }
        try expect(.missing, "settings", "config without a channel") { $0["settings"] = nil }
        try expect(.invalid, "settings.via", "settings in the environment") { $0["settings"] = ["via": "env", "fd": 3] }
        try expect(.invalid, "settings.fd", "settings on stdout") { $0["settings"] = ["via": "fd", "fd": 1] }
        try expect(.duplicate, "fields[1].key", "repeated key", field(1) { $0["key"] = "TOKEN"; $0["type"] = "string" })
        try expect(.invalid, "fields[1].key", "key with a dash", field(1) { $0["key"] = "OWNER-ID" })
        try expect(.unknownType, "fields[1].type", "number type", field(1) { $0["type"] = "number" })
        try expect(.badPattern, "fields[1].pattern", "broken pattern", field(1) { $0["pattern"] = "(" })
        try expect(.badDefault, "fields[1].default", "default off pattern", field(1) { $0["default"] = "12" })
        try expect(.badDefault, "fields[0].default", "secret with a default", field(0) { $0["default"] = "x" })
        try expect(.missing, "fields[0].label", "no label", field(0) { $0["label"] = nil })
        try expect(.missing, "fields[2].options", "select without options", field(2) { $0["options"] = nil })
        try expect(.badDefault, "fields[2].default", "default not a choice", field(2) { $0["default"] = "maybe" })
        try expect(.invalid, "fields[2].options", "values and command", field(2) { $0["options"] = ["values": [["value": "a"]], "command": "providers"] })
        try expect(.duplicate, "fields[2].options.values[1]", "repeated choice", field(2) { $0["options"] = ["values": [["value": "a"], ["value": "a"]]] })
        try expect(.unknownCommand, "fields[3].options.command", "missing source", field(3) { $0["options"] = ["command": "nope"] })
        try expect(.invalid, "fields[3].options.command", "source that is not JSON", field(3) { $0["options"] = ["command": "stop"] })
        try expect(.invalid, "fields[3].options.command", "source that gets the settings", field(3) { $0["options"] = ["command": "check-pc"] })
        try expect(.duplicate, "fields[3].options.sets.OWNER", "choice overwriting a field",
                   field(3) { $0["options"] = ["command": "providers", "sets": ["claude": ["OWNER": "path"]]] })
        try expect(.invalid, "status", "another user's home") { $0["status"] = "~root/status.json" }
        try expect(.invalid, "logs.a b", "log name") { $0["logs"] = ["a b": "x.log"] }

        // Paths that only exist on disk.
        let outside = try folder(try manifest())
        try expect(.outsideFolder, "commands.start.run[0]", "up and out", extra: ["../x.sh": "#!/bin/sh\n"],
                   command("start", ["run": ["../x.sh"]]))
        let linked = try folder(try manifest())
        try FileManager.default.createSymbolicLink(atPath: linked + "/ops/link", withDestinationPath: outside + "/ops/svc")
        let linkedManifest = try manifest(command("start", ["run": ["ops/link"]]))
        try linkedManifest.write(toFile: linked + "/ops/agent-notch.json", atomically: true, encoding: .utf8)
        do { _ = try load(linked); XCTFail("followed a link out of the folder") }
        catch let error as ServiceManifestError { XCTAssertEqual(error, ServiceManifestError(.outsideFolder, "commands.start.run[0]")) }

        let plainFile = try folder(try manifest())
        chmod(plainFile + "/ops/svc", 0o644)
        do { _ = try load(plainFile); XCTFail("ran a file without the executable bit") }
        catch let error as ServiceManifestError { XCTAssertEqual(error.problem, .notExecutable) }

        let shared = try folder(try manifest())
        chmod(shared + "/ops/svc", 0o775)
        do { _ = try load(shared); XCTFail("group-writable program") }
        catch let error as ServiceManifestError { XCTAssertEqual(error, ServiceManifestError(.unsafePermissions, "commands.start.run[0]")) }

        let open = try folder(try manifest())
        chmod(open + "/ops/agent-notch.json", 0o666)
        do { _ = try load(open); XCTFail("world-writable manifest") }
        catch let error as ServiceManifestError { XCTAssertEqual(error.problem, .unsafePermissions) }

        for (text, problem) in [("[1, 2]", ServiceManifestError.Problem.notJSON), ("{oops", .notJSON),
                                (String(repeating: " ", count: 300_000) + "{}", .tooLarge)] {
            do { _ = try load(try folder(text)); XCTFail("accepted \(problem)") }
            catch let error as ServiceManifestError { XCTAssertEqual(error.problem, problem) }
        }
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("notch-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        chmod(empty.path, 0o755)
        do { _ = try load(empty.path); XCTFail("no manifest") }
        catch let error as ServiceManifestError { XCTAssertEqual(error.problem, .notFound) }
    }

    // MARK: - Values

    func values() throws {
        let m = try load(try folder(try manifest()))
        var entry = ServiceEntry(manifest: m)
        XCTAssertFalse(entry.set("s3cret-token", for: "TOKEN", in: m))
        XCTAssertTrue(entry.values.isEmpty, "a secret never reaches the entry")
        XCTAssertFalse(entry.set("x", for: "UNKNOWN", in: m))
        XCTAssertEqual(ServiceValues.problems(m, entry: entry, secrets: [:]), ["TOKEN": .required, "OWNER": .required])

        entry.set("12", for: "OWNER", in: m)
        XCTAssertEqual(ServiceValues.problems(m, entry: entry, secrets: ["TOKEN": "t0ken-value"]), ["OWNER": .pattern])
        entry.set("1234", for: "OWNER", in: m)
        entry.set("sideways", for: "MODE", in: m)
        XCTAssertEqual(ServiceValues.problems(m, entry: entry, secrets: ["TOKEN": "t0ken-value"]), ["MODE": .choice])
        entry.set(nil, for: "MODE", in: m)

        let brain = try XCTUnwrap(m.field("BRAIN"))
        let options = try XCTUnwrap(ServiceOption.parse(Data(Self.providers.utf8), options: try XCTUnwrap(brain.options)))
        entry.choose(options[0], for: brain, in: m)
        XCTAssertEqual(entry.values["CLAUDE_BIN"], "/Users/me/.local/bin/claude")
        XCTAssertEqual(ServiceValues.problems(m, entry: entry, secrets: ["TOKEN": "t0ken-value"], choices: ["BRAIN": options]), [:])
        entry.set("codex", for: "BRAIN", in: m)
        XCTAssertEqual(ServiceValues.problems(m, entry: entry, secrets: ["TOKEN": "t0ken-value"], choices: ["BRAIN": options]),
                       ["BRAIN": .choice], "codex is not logged in")
        entry.set("claude", for: "BRAIN", in: m)
        entry.set("/old/codex", for: "CODEX_BIN", in: m)

        let payload = ServiceValues.payload(m, entry: entry, secrets: ["TOKEN": "t0ken-value"])
        XCTAssertEqual(String(decoding: payload, as: UTF8.self),
                       #"{"BRAIN":"claude","CLAUDE_BIN":"/Users/me/.local/bin/claude","MODE":"on","OWNER":"1234","TOKEN":"t0ken-value"}"#,
                       "defaults filled, only the chosen provider's path")
        let stored = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
        XCTAssertFalse(stored.contains("t0ken-value"))
    }

    static let providers = #"""
    [
      { "id": "claude", "name": "Claude Code", "path": "/Users/me/.local/bin/claude", "version": "2.1.311 (Claude Code)", "loggedIn": true, "method": "claude.ai (max)" },
      { "id": "codex", "name": "Codex", "path": "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex", "version": "codex-cli 0.163.0", "loggedIn": false, "login": "ops/gosha codex-login" },
      { "name": "no id" },
      "junk",
      { "id": "claude", "name": "Claude again", "loggedIn": true },
      { "id": "gemini", "name": "Gemini", "loggedIn": "yes" }
    ]
    """#

    func providerOptions() throws {
        let m = try load(try folder(try manifest()))
        let options = try XCTUnwrap(m.field("BRAIN")?.options)
        let parsed = try XCTUnwrap(ServiceOption.parse(Data(Self.providers.utf8), options: options))
        XCTAssertEqual(parsed.map(\.value), ["claude", "codex", "gemini"])
        XCTAssertEqual(parsed.map(\.enabled), [true, false, false], "only a real true enables a choice")
        XCTAssertEqual(parsed[0].label, "Claude Code")
        XCTAssertEqual(parsed[0].detail, "claude.ai (max)")
        XCTAssertEqual(parsed[0].sets, ["CLAUDE_BIN": "/Users/me/.local/bin/claude"])
        XCTAssertEqual(parsed[1].login, "ops/gosha codex-login")
        XCTAssertEqual(parsed[1].sets, ["CODEX_BIN": "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"])
        XCTAssertNil(ServiceOption.parse(Data(#"{"id":"claude"}"#.utf8), options: options))
        XCTAssertEqual(ServiceOption.parse(Data("[]".utf8), options: options), [])
    }
}
