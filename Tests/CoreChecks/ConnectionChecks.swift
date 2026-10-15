import Foundation

struct ConnectionChecks {
    func home() -> URL { URL(fileURLWithPath: "/tmp/ct-" + UUID().uuidString.prefix(8)) }

    func fullSet() throws {
        let root = home(), inst = HookInstaller(home: root)
        defer { try? FileManager.default.removeItem(at: root) }
        for vendor in [Vendor.claude, .codex] {
            try inst.install(vendor)
            let original = try Data(contentsOf: inst.file(vendor))
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: original) as? Rec)
            let hooks = try XCTUnwrap(object["hooks"] as? Rec)
            XCTAssertTrue(inst.isInstalled(vendor))
            for event in hooks.keys {
                var partial = hooks
                partial.removeValue(forKey: event)
                try JSONSerialization.data(withJSONObject: ["hooks": partial]).write(to: inst.file(vendor))
                XCTAssertFalse(inst.isInstalled(vendor))
            }
            var groups = try XCTUnwrap(hooks["PreToolUse"] as? [Rec])
            if vendor == .claude { groups.removeLast() }
            else { groups[0]["matcher"] = "Bash" }
            var partial = hooks
            partial["PreToolUse"] = groups
            try JSONSerialization.data(withJSONObject: ["hooks": partial]).write(to: inst.file(vendor))
            XCTAssertFalse(inst.isInstalled(vendor))
            for replacement in ["/old/notch-hook", vendor == .claude ? "codex" : "claude"] {
                let text = String(decoding: original, as: UTF8.self)
                let changed = replacement.hasPrefix("/") ? text.replacingOccurrences(of: inst.helper.path, with: replacement)
                    : text.replacingOccurrences(of: "\\\" \(vendor.rawValue)", with: "\\\" \(replacement)")
                try changed.write(to: inst.file(vendor), atomically: true, encoding: .utf8)
                XCTAssertFalse(inst.isInstalled(vendor))
            }
            try original.write(to: inst.file(vendor))
            var wrong = hooks
            var permission = try XCTUnwrap(hooks["PermissionRequest"] as? [Rec])
            var entries = try XCTUnwrap(permission[0]["hooks"] as? [Rec])
            entries[0]["async"] = true
            permission[0]["hooks"] = entries
            wrong["PermissionRequest"] = permission
            try JSONSerialization.data(withJSONObject: ["hooks": wrong]).write(to: inst.file(vendor))
            XCTAssertFalse(inst.isInstalled(vendor))
            for (field, value) in [("async", "garbage" as Any), ("async", 1 as Any), ("timeout", true as Any)] {
                var malformed = hooks
                var group = try XCTUnwrap(hooks["PermissionRequest"] as? [Rec])
                var entries = try XCTUnwrap(group[0]["hooks"] as? [Rec])
                entries[0][field] = value
                group[0]["hooks"] = entries
                malformed["PermissionRequest"] = group
                try JSONSerialization.data(withJSONObject: ["hooks": malformed]).write(to: inst.file(vendor))
                XCTAssertFalse(inst.isInstalled(vendor))
            }
            var malformed = hooks
            var group = try XCTUnwrap(hooks["PostToolUse"] as? [Rec])
            group[0]["matcher"] = 123
            malformed["PostToolUse"] = group
            try JSONSerialization.data(withJSONObject: ["hooks": malformed]).write(to: inst.file(vendor))
            XCTAssertFalse(inst.isInstalled(vendor))
        }
    }

    func states() throws {
        let root = home(), inst = HookInstaller(home: root)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(ConnectionReport.read(.claude, installer: inst, listening: { true }).missing, .config)
        for vendor in [Vendor.claude, .codex] { try inst.install(vendor) }
        XCTAssertEqual(ConnectionReport.read(.claude, installer: inst, listening: { true }).missing, .helper)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: inst.helper)
        chmod(inst.helper.path, 0o644)
        XCTAssertFalse(ConnectionReport.read(.claude, installer: inst, listening: { true }).helperAlive)
        chmod(inst.helper.path, 0o755)
        XCTAssertEqual(ConnectionReport.read(.claude, installer: inst, listening: { false }).missing, .helper)
        XCTAssertEqual(ConnectionReport.read(.claude, installer: inst, listening: { true }).missing, .firstHook)
        XCTAssertEqual(ConnectionReport.read(.codex, installer: inst, listening: { true }).missing, .trust)
        try ConnectionReceipt(installer: inst).record(.claude, at: 123)
        try ConnectionReceipt(installer: inst).record(.claude, at: 456)
        let connected = ConnectionReport.read(.claude, installer: inst, listening: { true })
        XCTAssertNil(connected.missing)
        XCTAssertEqual(connected.firstHookAt, 123)
        XCTAssertNil(ConnectionReport.read(.codex, installer: inst, listening: { true }).firstHookAt)
        try inst.install(.claude)
        XCTAssertNil(ConnectionReport.read(.claude, installer: inst, listening: { true }).firstHookAt)
        try Data("broken".utf8).write(to: ConnectionReceipt(installer: inst).file(.codex))
        XCTAssertNil(ConnectionReport.read(.codex, installer: inst, listening: { true }).firstHookAt)
    }

    func diagnostic() throws {
        let path = "/tmp/dt-" + UUID().uuidString.prefix(8) + ".sock"
        let server = HookServer(path: path)
        let events = Box(0)
        server.onEvent = { _, _ in events.value += 1 }
        try server.start()
        defer { server.stop() }
        XCTAssertTrue(HookClient.probe(path: path, pathCheck: { _ in true }))
        XCTAssertFalse(HookClient.probe(path: path, pathCheck: { _ in false }))
        XCTAssertEqual(events.value, 0)
        server.stop()
        XCTAssertFalse(HookClient.probe(path: path, pathCheck: { _ in true }))
    }

    func doctor() throws {
        let root = home(), inst = HookInstaller(home: root)
        defer { try? FileManager.default.removeItem(at: root) }
        Loc.forced = .en
        defer { Loc.forced = .ru }
        let missing = ConnectionReport.doctor(installer: inst)
        XCTAssertTrue(missing.contains("claude: config written: no"))
        XCTAssertTrue(missing.contains("codex: config written: no"))
        try inst.install(.codex)
        let text = ConnectionReport.doctor(installer: inst)
        XCTAssertTrue(text.contains("codex: config written: yes; helper alive: no; first hook received: no; Codex waits for trust: yes"))
        XCTAssertTrue(text.contains("/hooks"))
    }
    func trust() throws {
        let root = home(), inst = HookInstaller(home: root)
        defer { try? FileManager.default.removeItem(at: root) }
        try inst.install(.codex)
        try ConnectionReceipt(installer: inst).record(.codex, at: 123)
        // No readable trust database: a real receipt is the fallback evidence.
        XCTAssertFalse(ConnectionReport.read(.codex, installer: inst, listening: { true }).waitsForTrust)
        let config = root.appendingPathComponent(".codex/config.toml")
        try "[hooks]\n".write(to: config, atomically: true, encoding: .utf8)
        XCTAssertTrue(ConnectionReport.read(.codex, installer: inst, listening: { true }).waitsForTrust)
        let key = inst.file(.codex).path + ":permission_request:0:0"
        let quoted = String(decoding: try JSONEncoder().encode(key), as: UTF8.self)
        try ("[hooks.state." + quoted + "]\ntrusted_hash = \"sha256:obsolete\"\nenabled = false\n")
            .write(to: config, atomically: true, encoding: .utf8)
        XCTAssertTrue(ConnectionReport.read(.codex, installer: inst, listening: { true }).waitsForTrust)
        let disabled = try String(contentsOf: config, encoding: .utf8)
        try ("# state = unrelated comment\n[mcp_servers.fixture]\nenv = { KEY = \"value\" }\n" + disabled)
            .write(to: config, atomically: true, encoding: .utf8)
        XCTAssertTrue(ConnectionReport.read(.codex, installer: inst, listening: { true }).waitsForTrust)
        try ("notify = [\n \"python3\",\n \"notify.py\",\n]\n" + disabled)
            .write(to: config, atomically: true, encoding: .utf8)
        XCTAssertTrue(ConnectionReport.read(.codex, installer: inst, listening: { true }).waitsForTrust)
        try ("description = " + String(repeating: "\"", count: 3) + "\n[hooks.state.fake]\nstate = text\n"
             + String(repeating: "\"", count: 3) + "\n" + disabled).write(to: config, atomically: true, encoding: .utf8)
        XCTAssertTrue(ConnectionReport.read(.codex, installer: inst, listening: { true }).waitsForTrust)
        try "[hooks]\nstate = { }\n".write(to: config, atomically: true, encoding: .utf8)
        XCTAssertNil(CodexHookTrust.read(installer: inst))
    }

    func doctorCLI() throws {
        let (tools, helper, _) = try SafeUninstallChecks.tools.get()
        let result = try SafeUninstallChecks.process(URL(fileURLWithPath: "/bin/sh"), ["Tests/Fixtures/connection-cli.sh", helper.path])
        XCTAssertEqual(result.0, 0, result.1)
        XCTAssertTrue(result.1.contains("OK connection CLI"))
        let root = home(), inst = HookInstaller(home: root)
        defer { try? FileManager.default.removeItem(at: root) }
        try inst.install(.claude)
        try inst.install(.codex)
        try FileManager.default.copyItem(at: helper, to: inst.helper)
        chmod(inst.helper.path, 0o755)
        let app = tools.appendingPathComponent("Probe.app/Contents/MacOS/AgentsNotch")
        try FileManager.default.createDirectory(at: app.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SafeUninstallChecks.compile(["-I", tools.path, "-L", tools.path, "-lNotchCore", "-o", app.path,
                                         "Tests/Fixtures/ConnectionProbe/main.swift"])
        try Data((app.path + "\n").utf8).write(to: inst.appPin)
        chmod(inst.appPin.path, 0o600)
        let server = Process()
        server.executableURL = app
        server.arguments = [root.path]
        try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("ready").path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        for vendor in [Vendor.claude, .codex] {
            XCTAssertTrue(ConnectionReport.testRequest(vendor, installer: inst))
            XCTAssertNil(ConnectionReceipt(installer: inst).timestamp(vendor))
        }
        let doctor = try SafeUninstallChecks.process(helper, ["doctor", "--home", root.path])
        XCTAssertEqual(doctor.0, 0)
        XCTAssertTrue(doctor.1.contains("helper alive: yes"))
        XCTAssertTrue(doctor.1.contains("first hook received: no"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("event-received").path))
        server.terminate()
        server.waitUntilExit()
        XCTAssertFalse(ConnectionReport.testRequest(.codex, installer: inst))

    }

}
