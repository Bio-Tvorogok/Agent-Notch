import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

/// Labels in two languages, fields shown on a condition, what a command is given, and the service's own commands.
extension ServiceChecks {
    func expectRejected(_ problem: ServiceManifestError.Problem, _ path: String, _ note: String,
                        _ patch: (inout [String: Any]) -> Void) throws {
        do {
            _ = try load(try folder(try manifest(patch)))
            XCTFail("accepted: \(note)")
        } catch let error as ServiceManifestError {
            XCTAssertEqual(error, ServiceManifestError(problem, path), note)
        }
    }

    func editField(_ i: Int, _ edit: @escaping (inout [String: Any]) -> Void) -> (inout [String: Any]) -> Void {
        { o in var f = o["fields"] as! [[String: Any]]; edit(&f[i]); o["fields"] = f }
    }

    func addFields(_ added: [[String: Any]]) -> (inout [String: Any]) -> Void {
        { o in o["fields"] = (o["fields"] as! [[String: Any]]) + added }
    }

    func editCommand(_ name: String, _ body: [String: Any]) -> (inout [String: Any]) -> Void {
        { o in var c = o["commands"] as! [String: Any]; c[name] = body; o["commands"] = c }
    }

    func localizedText() throws {
        let saved = Loc.forced
        defer { Loc.forced = saved }
        let text = try manifest { o in
            o["name"] = ["ru": "Сервис", "en": "Service"]
            o["description"] = ["ru-RU": "Описание", "en-US": "About"]
            var f = o["fields"] as! [[String: Any]]
            f[0]["label"] = ["en": "Token"]
            f[0]["help"] = ["fr": "Aide", "de": "Hilfe"]
            f[2]["options"] = ["values": [["value": "on", "label": ["ru": "Вкл", "en": "On"]], ["value": "off", "label": "Off"]]]
            o["fields"] = f
            var c = o["commands"] as! [String: Any]
            c["codex-login"] = ["run": ["ops/svc", "json", "[]"], "label": ["ru": "Войти", "en": "Sign in"]]
            o["commands"] = c
        }
        let root = try folder(text)
        Loc.forced = .ru
        let ru = try load(root)
        XCTAssertEqual([ru.name, ru.description, ru.fields[0].label, ru.fields[0].help, ru.fields[2].options?.values.first?.label,
                        ru.command("codex-login")?.label], ["Сервис", "Описание", "Token", "Hilfe", "Вкл", "Войти"],
                       "own language, then a regional variant, then English, then the first by name")
        Loc.forced = .en
        let en = try load(root)
        XCTAssertEqual([en.name, en.description, en.fields[0].label, en.command("codex-login")?.label], ["Service", "About", "Token", "Sign in"])
        XCTAssertEqual(en.fingerprint, ru.fingerprint, "the approval is for the file, whatever language reads it")
        Loc.forced = .ru

        try expectRejected(.invalid, "name.RU", "language code") { $0["name"] = ["RU": "x"] }
        try expectRejected(.wrongType, "name.ru", "variant that is not text") { $0["name"] = ["ru": 5] }
        try expectRejected(.invalid, "name", "no variants") { $0["name"] = [String: String]() }
        try expectRejected(.invalid, "name.en", "a hidden variant is checked too") { $0["name"] = ["ru": "Гоша", "en": "Safe\u{202E}evil"] }
        try expectRejected(.wrongType, "name", "a number") { $0["name"] = 5 }
    }

    func conditions() throws {
        let m = try load(try folder(try manifest(addFields([
            ["key": "URL", "label": "Url", "type": "string", "required": true, "when": ["MODE": "on"]],
            ["key": "DEEP", "label": "Deep", "type": "string", "required": true, "when": ["URL": ["a", "b"]]],
        ]))))
        XCTAssertEqual(m.field("DEEP")?.when, ["URL": ["a", "b"]])
        var entry = ServiceEntry(manifest: m)
        entry.set("1234", for: "OWNER", in: m)
        let secrets = ["TOKEN": "t0ken-value"]
        let url = try XCTUnwrap(m.field("URL")), deep = try XCTUnwrap(m.field("DEEP"))
        XCTAssertTrue(ServiceValues.visible(url, in: m, entry: entry), "MODE defaults to on")
        XCTAssertFalse(ServiceValues.visible(deep, in: m, entry: entry))
        XCTAssertEqual(ServiceValues.problems(m, entry: entry, secrets: secrets), ["URL": .required])
        entry.set("a", for: "URL", in: m)
        XCTAssertEqual(ServiceValues.problems(m, entry: entry, secrets: secrets), ["DEEP": .required], "a chain of conditions")
        entry.set("deep", for: "DEEP", in: m)
        XCTAssertTrue(String(decoding: ServiceValues.payload(m, entry: entry, secrets: secrets), as: UTF8.self).contains(#""DEEP":"deep""#))

        // MODE off hides URL, and with it DEEP: neither required nor sent, though both are still stored.
        entry.set("off", for: "MODE", in: m)
        XCTAssertFalse(ServiceValues.visible(url, in: m, entry: entry))
        XCTAssertFalse(ServiceValues.visible(deep, in: m, entry: entry))
        XCTAssertEqual(ServiceValues.problems(m, entry: entry, secrets: secrets), [:])
        let sent = try JSONSerialization.jsonObject(with: ServiceValues.payload(m, entry: entry, secrets: secrets)) as? [String: String]
        XCTAssertEqual(sent.map { Set($0.keys) }, ["BRAIN", "MODE", "OWNER", "TOKEN"])
        XCTAssertEqual(entry.values["URL"], "a")

        // A hidden select does not send what its choice filled in.
        let gated = try load(try folder(try manifest(editField(3) { $0["when"] = ["MODE": "on"] })))
        var picked = ServiceEntry(manifest: gated)
        let brain = try XCTUnwrap(gated.field("BRAIN"))
        let options = try XCTUnwrap(ServiceOption.parse(Data(Self.providers.utf8), options: try XCTUnwrap(brain.options)))
        picked.choose(options[0], for: brain, in: gated)
        picked.set("off", for: "MODE", in: gated)
        let hidden = String(decoding: ServiceValues.payload(gated, entry: picked, secrets: secrets), as: UTF8.self)
        XCTAssertTrue(!hidden.contains("BRAIN") && !hidden.contains("CLAUDE_BIN"), hidden)

        // Eight layers of eight fields, each depending on every field of the layer before: 8^8 paths, worked out in one pass.
        var layered: [[String: Any]] = []
        for layer in 0..<8 {
            for i in 0..<8 {
                var field: [String: Any] = ["key": "L\(layer)_\(i)", "label": "x", "type": "string", "default": "v"]
                if layer > 0 { field["when"] = Dictionary(uniqueKeysWithValues: (0..<8).map { ("L\(layer - 1)_\($0)", "v") }) }
                layered.append(field)
            }
        }
        let wide = try load(try folder(try manifest { o in o["fields"] = layered }))
        let began = Date()
        let wideEntry = ServiceEntry(manifest: wide)
        XCTAssertEqual(ServiceValues.visibleKeys(wide, entry: wideEntry).count, 64)
        _ = ServiceValues.problems(wide, entry: wideEntry, secrets: [:])
        _ = ServiceValues.payload(wide, entry: wideEntry, secrets: [:])
        XCTAssertTrue(Date().timeIntervalSince(began) < 1, "shared conditions are worked out once")

        try expectRejected(.invalid, "fields[1].when.NOPE", "unknown field", editField(1) { $0["when"] = ["NOPE": "x"] })
        try expectRejected(.invalid, "fields[1].when.OWNER", "itself", editField(1) { $0["when"] = ["OWNER": "x"] })
        try expectRejected(.invalid, "fields[1].when.TOKEN", "a secret's value is not in the form", editField(1) { $0["when"] = ["TOKEN": "x"] })
        try expectRejected(.wrongType, "fields[1].when.MODE", "a number", editField(1) { $0["when"] = ["MODE": 1] })
        try expectRejected(.invalid, "fields[1].when.MODE", "no values", editField(1) { $0["when"] = ["MODE": [String]()] })
        try expectRejected(.invalid, "fields[4].when", "a cycle", addFields([
            ["key": "A", "label": "A", "type": "string", "when": ["B": "x"]],
            ["key": "B", "label": "B", "type": "string", "when": ["C": "x"]],
            ["key": "C", "label": "C", "type": "string", "when": ["A": "x"]],
        ]))
    }

    func needs() throws {
        let m = try load(try folder(try manifest(editCommand("check-pc", ["run": ["ops/svc", "read"], "config": true, "json": true,
                                                                          "needs": ["OWNER", "MODE", "CLAUDE_BIN"]]))))
        let check = try XCTUnwrap(m.command("check-pc"))
        XCTAssertEqual(check.needs, ["OWNER", "MODE", "CLAUDE_BIN"])
        XCTAssertEqual(m.commandSummary["check-pc"], "ops/svc read → ops/svc [settings: OWNER,MODE,CLAUDE_BIN]", "a change of needs shows on re-approval")
        XCTAssertEqual(m.commandSummary["start"], "ops/svc read → ops/svc [settings: all]")
        XCTAssertNil(ServiceValues.settings(for: try XCTUnwrap(m.command("stop")), of: m, entry: ServiceEntry(manifest: m), secrets: ["TOKEN": "x"]))
        XCTAssertEqual(ServiceValues.secretKeys(m, for: check), [], "no secret is needed, so none is read for it")
        XCTAssertEqual(ServiceValues.secretKeys(m, for: try XCTUnwrap(m.command("start"))), ["TOKEN"])
        var entry = ServiceEntry(manifest: m)
        let brain = try XCTUnwrap(m.field("BRAIN"))
        entry.choose(try XCTUnwrap(ServiceOption.parse(Data(Self.providers.utf8), options: try XCTUnwrap(brain.options)))[0], for: brain, in: m)
        let secrets = ["TOKEN": "fd3-only-s3cret"]
        XCTAssertEqual(ServiceValues.problems(m, entry: entry, secrets: [:], for: check), ["OWNER": .required],
                       "only the needed fields count: the missing token does not")
        XCTAssertEqual(ServiceValues.problems(m, entry: entry, secrets: [:]), ["TOKEN": .required, "OWNER": .required])

        // Through the real descriptor, built the way the app builds it from every stored secret:
        // the child reads exactly the needed keys, and the token is not among them.
        entry.set("1234", for: "OWNER", in: m)
        let payload = try XCTUnwrap(ServiceValues.settings(for: check, of: m, entry: entry, secrets: secrets))
        let read = try ServiceRunner.run(check, of: m, settings: payload, environment: ServiceEnvironment.make(path: "/usr/bin:/bin"))
        XCTAssertEqual(String(decoding: read.stdout, as: UTF8.self), #"{"CLAUDE_BIN":"/Users/me/.local/bin/claude","MODE":"on","OWNER":"1234"}"#)
        XCTAssertTrue(!String(decoding: read.stdout, as: UTF8.self).contains("fd3-only-s3cret"))
        let all = String(decoding: ServiceValues.payload(m, entry: entry, secrets: secrets), as: UTF8.self)
        XCTAssertTrue(all.contains("fd3-only-s3cret"), "without needs every setting goes, as before")

        // Empty needs sends an empty object.
        let none = try load(try folder(try manifest(editCommand("check-pc", ["run": ["ops/svc", "read"], "config": true, "json": true, "needs": [String]()]))))
        XCTAssertEqual(String(decoding: ServiceValues.payload(none, entry: ServiceEntry(manifest: none), secrets: secrets,
                                                             for: try XCTUnwrap(none.command("check-pc"))), as: UTF8.self), "{}")

        try expectRejected(.invalid, "commands.check-pc.needs.NOPE", "unknown key",
                           editCommand("check-pc", ["run": ["ops/svc"], "config": true, "json": true, "needs": ["NOPE"]]))
        try expectRejected(.invalid, "commands.stop.needs", "needs without config", editCommand("stop", ["run": ["ops/svc"], "needs": ["OWNER"]]))
        try expectRejected(.duplicate, "commands.check-pc.needs", "a key twice",
                           editCommand("check-pc", ["run": ["ops/svc"], "config": true, "needs": ["OWNER", "OWNER"]]))
        try expectRejected(.invalid, "commands.check-pc.needs[0]", "not a key",
                           editCommand("check-pc", ["run": ["ops/svc"], "config": true, "needs": ["a b"]]))
    }

    func ownCommands() throws {
        let login: (inout [String: Any]) -> Void = { o in
            var c = o["commands"] as! [String: Any]
            c["codex-login"] = ["run": ["ops/svc", "json", "[]"], "label": "Войти в Codex", "timeout": 600]
            c["zz-tool"] = ["run": ["ops/svc", "pwd"]]
            o["commands"] = c
            var f = o["fields"] as! [[String: Any]]
            var options = f[3]["options"] as! [String: Any]
            options["loginCommand"] = ["codex": "codex-login"]
            f[3]["options"] = options
            o["fields"] = f
        }
        let m = try load(try folder(try manifest(login)))
        XCTAssertEqual(m.customCommands.map(\.name), ["codex-login", "zz-tool"], "the service's own, after the known ones")
        XCTAssertEqual(m.customCommands.first?.timeout, 600)
        XCTAssertEqual(m.field("BRAIN")?.options?.loginCommand, ["codex": "codex-login"])

        func withLogin(_ value: Any, on field: Int = 3) -> (inout [String: Any]) -> Void {
            { o in
                login(&o)
                var f = o["fields"] as! [[String: Any]]
                var options = f[field]["options"] as! [String: Any]
                options["loginCommand"] = value
                f[field]["options"] = options
                o["fields"] = f
            }
        }
        try expectRejected(.unknownCommand, "fields[3].options.loginCommand.codex", "missing command", withLogin(["codex": "nope"]))
        try expectRejected(.invalid, "fields[3].options.loginCommand.codex", "a known command", withLogin(["codex": "start"]))
        try expectRejected(.wrongType, "fields[3].options.loginCommand.codex", "not a name", withLogin(["codex": 1]))
        try expectRejected(.invalid, "fields[2].options.loginCommand", "a listed select", withLogin(["on": "codex-login"], on: 2))
        // A sign-in that takes settings must say which: «Sign in» does not hand over every setting.
        let settingsLogin: (inout [String: Any]) -> Void = { o in
            login(&o)
            var c = o["commands"] as! [String: Any]
            c["codex-login"] = ["run": ["ops/svc", "read"], "config": true]
            o["commands"] = c
        }
        try expectRejected(.invalid, "fields[3].options.loginCommand.codex", "settings without needs", settingsLogin)
        XCTAssertEqual(try load(try folder(try manifest { o in
            settingsLogin(&o)
            var c = o["commands"] as! [String: Any]
            c["codex-login"] = ["run": ["ops/svc", "read"], "config": true, "needs": ["MODE"]]
            o["commands"] = c
        })).command("codex-login")?.needs, ["MODE"])

        // A button may not say what another command does.
        for label: Any in ["Остановить", "  stop ", ["ru": "Пуск", "en": "Stop"], "Проверить  ПК", "providers"] {
            try expectRejected(.invalid, "commands.evil.label", "label \(label)", editCommand("evil", ["run": ["ops/svc"], "label": label]))
        }
        try expectRejected(.invalid, "commands.check-pc.label", "check-pc called Start",
                           editCommand("check-pc", ["run": ["ops/svc"], "config": true, "json": true, "label": "Запустить"]))
        let own = try load(try folder(try manifest(editCommand("check-pc", ["run": ["ops/svc"], "config": true, "json": true, "label": "Проверить ПК"]))))
        XCTAssertEqual(own.command("check-pc")?.label, "Проверить ПК", "a command may use its own word")

        // Two fields may not fill the same setting: a hidden one's fill-in would go out under the other's name.
        try expectRejected(.duplicate, "fields[4].options.sets.CLAUDE_BIN", "a fill-in claimed twice", addFields([
            ["key": "OTHER", "label": "Other", "type": "select", "options": ["command": "providers", "value": "id", "sets": ["claude": ["CLAUDE_BIN": "path"]]]],
        ]))
    }

    /// Gosha's manifest: check-pc gets the VoiceStudio settings and node, never the Discord token.
    func goshaNeeds() throws {
        let text = try String(contentsOfFile: "Tests/Fixtures/Services/chedrik.json", encoding: .utf8)
        let m = try load(try folder(text, extra: ["ops/gosha": "#!/bin/sh\nexit 0\n"]))
        var entry = ServiceEntry(manifest: m)
        for (key, value) in ["OWNER_DISCORD_ID": "301234567890123456", "VOICESTUDIO_URL": "http://pc:3900", "CHEDRIK_NODE": "~/n/node"] {
            entry.set(value, for: key, in: m)
        }
        let secrets = ["DISCORD_BOT_TOKEN": "discord-t0ken", "VOICESTUDIO_API_KEY": "vs-key"]
        let check = try XCTUnwrap(m.command("check-pc"))
        let sent = try XCTUnwrap(try JSONSerialization.jsonObject(with: ServiceValues.payload(m, entry: entry, secrets: secrets, for: check)) as? [String: String])
        XCTAssertEqual(sent, ["VOICE_TTS": "voicestudio", "VOICESTUDIO_URL": "http://pc:3900", "VOICESTUDIO_API_KEY": "vs-key",
                              "CHEDRIK_PERSONA": "podyobshik", "CHEDRIK_NODE": "~/n/node"])
        XCTAssertEqual(ServiceValues.secretKeys(m, for: check), ["VOICESTUDIO_API_KEY"])
        entry.set("off", for: "VOICE_TTS", in: m)
        let silent = String(decoding: ServiceValues.payload(m, entry: entry, secrets: secrets, for: try XCTUnwrap(m.command("start"))), as: UTF8.self)
        XCTAssertTrue(!silent.contains("VOICESTUDIO") && silent.contains("discord-t0ken"), "without voice, no VoiceStudio settings")
    }
}
