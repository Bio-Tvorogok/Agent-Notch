import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

/// Status files, check results, logs and secrets.
extension ServiceChecks {
    static let status = #"""
    {
      "pid": 4242, "startedAt": "2026-10-30T10:00:00.000Z",
      "discord": { "online": true, "servers": [{ "id": "1", "name": "AqulaSoft", "answers": true }, { "id": "2", "name": "Lab", "answers": null }] },
      "voice": { "enabled": true, "in": { "channelId": "9", "channelName": "public", "guildId": "1", "guildName": "AqulaSoft" } },
      "brain": { "provider": "claude", "alive": true },
      "tts": { "ok": true, "url": "http://192.168.1.130:3900" },
      "stt": { "ok": null, "url": "http://127.0.0.1:8178" },
      "extra": { "ok": false },
      "lastError": "boom‮\nsecond",
      "updatedAt": "2026-10-30T10:00:05Z"
    }
    """#

    func statusFile() throws {
        let s = try XCTUnwrap(ServiceStatus.parse(Data(Self.status.utf8)))
        XCTAssertEqual(s.pid, 4242)
        XCTAssertEqual(s.startedAt, Date(timeIntervalSince1970: 1_793_354_400))
        XCTAssertEqual(s.updatedAt, Date(timeIntervalSince1970: 1_793_354_405))
        XCTAssertEqual(s.lastError, "boom second")
        XCTAssertEqual(s.rows.map(\.key), ["discord", "voice", "brain", "tts", "stt", "extra"])
        XCTAssertEqual(s.rows[0].value, .online(true, servers: [.init(name: "AqulaSoft", answers: true), .init(name: "Lab", answers: nil)]))
        XCTAssertEqual(s.rows[1].value, .place(enabled: true, at: "public · AqulaSoft"))
        XCTAssertEqual(s.rows[2].value, .provider("claude", alive: true))
        XCTAssertEqual(s.rows[3].value, .check(ok: true, url: "http://192.168.1.130:3900"))
        XCTAssertEqual(s.rows[4].value, .check(ok: nil, url: "http://127.0.0.1:8178"))
        let out = try XCTUnwrap(ServiceStatus.parse(Data(#"{"voice":{"enabled":true,"in":null},"tts":{"enabled":false,"in":null}}"#.utf8)))
        XCTAssertEqual(out.rows.map(\.value), [.place(enabled: true, at: nil), .place(enabled: false, at: nil)])
        XCTAssertNil(ServiceStatus.parse(Data("[]".utf8)))
        XCTAssertNil(ServiceStatus.read(home + "/missing.json"))
        let odd = try XCTUnwrap(ServiceStatus.parse(Data(#"{"pid":true,"bad key":{"ok":true},"tts":{"ok":true,"url":"http://u:pw-secret@pc:1"}}"#.utf8)))
        XCTAssertNil(odd.pid, "true is not pid 1")
        XCTAssertEqual(odd.rows.map(\.key), ["tts"])
        XCTAssertEqual(odd.masked(secrets: []).rows.first?.value, .check(ok: true, url: "http://u:***@pc:1"))

        // Not regular files: a FIFO would block, /dev/zero never ends, a final link is not followed.
        let fifo = home + "/status.fifo"
        XCTAssertEqual(mkfifo(fifo, 0o600), 0)
        // Not left behind: a recursive read of the temporary folder would block on it.
        defer { unlink(fifo) }
        let began = Date()
        XCTAssertNil(ServiceStatus.read(fifo))
        XCTAssertEqual(ServiceLogs.tail(fifo), [])
        XCTAssertEqual(ServiceLogs.tail("/dev/zero"), [])
        XCTAssertTrue(Date().timeIntervalSince(began) < 1, "special files are refused at once")
        let real = home + "/real-status.json"
        try Self.status.write(toFile: real, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: home + "/link-status.json", withDestinationPath: real)
        XCTAssertTrue(ServiceStatus.read(real) != nil)
        XCTAssertNil(ServiceStatus.read(home + "/link-status.json"))

        func running(_ pid: Int32, _ startedAt: Date) -> Bool {
            ServiceStatus(pid: pid, startedAt: startedAt, updatedAt: nil, lastError: nil, rows: []).isRunning()
        }
        XCTAssertTrue(running(getpid(), Date()))
        XCTAssertTrue(!running(getpid(), Date(timeIntervalSince1970: 1_000_000)), "a pid that started after the file was written is someone else")
        XCTAssertFalse(s.isRunning())
        let gone = try Self.finishedPid()
        XCTAssertFalse(running(gone, Date()))
    }

    static func finishedPid() throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try p.run()
        p.waitUntilExit()
        return p.processIdentifier
    }

    func checkResult() throws {
        let m = try load(try folder(try manifest()))
        func check(_ json: String, exit: Int = 0) throws -> ServiceCheck {
            ServiceCheck.parse(try run(m, ["json", json, "\(exit)"]), secrets: ["vs-key-123456"])
        }
        XCTAssertEqual(try check(#"{"ok":true,"url":"http://pc:3900","healthMs":64,"latencyMs":5100.4,"error":null}"#),
                       ServiceCheck(ok: true, url: "http://pc:3900", healthMs: 64, latencyMs: 5100))
        XCTAssertEqual(try check(#"{"ok":false,"url":"http://pc:3900","healthMs":null,"latencyMs":null,"error":"401 for vs-key-123456"}"#, exit: 1),
                       ServiceCheck(ok: false, url: "http://pc:3900", error: "401 for ***"))
        XCTAssertEqual(try check(#"{"ok":true}"#, exit: 1), ServiceCheck(ok: false, error: "код выхода 1"))
        let noJSON = ServiceCheck.parse(try run(m, ["exit", "3"]))
        XCTAssertEqual(noJSON, ServiceCheck(ok: false, error: "said 3"))
    }

    func logs() throws {
        let file = home + "/svc.log"
        try (1...10).map { "line \($0)" }.joined(separator: "\n").appending("\n").write(toFile: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(ServiceLogs.tail(file, lines: 3), ["line 8", "line 9", "line 10"])
        let big = home + "/big.log"
        try String(repeating: "0123456789abcdef\n", count: 10_000).write(toFile: big, atomically: true, encoding: .utf8)
        let tail = ServiceLogs.tail(big, lines: 100_000)
        XCTAssertTrue(tail.allSatisfy { $0 == "0123456789abcdef" }, "a line cut by the window is dropped")
        XCTAssertEqual(ServiceLogs.tail(home + "/none.log"), [])

        // Made up; assembled at run time so secret scanners do not take it for a real token.
        let discord = ["MTA4NzQ1Njc4OTAxMjM0NTY3OA", "GaBcDe", "abcdefghijklmnopqrstuvwxyz0123"].joined(separator: ".")
        let cases: [(String, String)] = [
            ("login with \(discord) failed", "login with *** failed"),
            ("key sk-ant-api03-AbC_dEf-123 used", "key sk-ant-*** used"),
            ("openai sk-proj-abcdefghijklmnopqrstuv", "openai sk-***"),
            (#"VOICESTUDIO_API_KEY=abc123 next"#, "VOICESTUDIO_API_KEY=*** next"),
            ("refused (api_key=vs-live-123456)", "refused (api_key=***)"),
            (#"{"token": "abc.def", "ok": true}"#, #"{"token": "***", "ok": true}"#),
            ("Authorization: Bearer abcdefgh12345", "Authorization: Bearer ***"),
            ("GET https://bot:hunter2@example.com/x", "GET https://bot:***@example.com/x"),
            ("pushed with ghp_abcdefghijklmnopqrstuvwxyz", "pushed with ghp_***"),
            ("the stored s3cr3t-value leaked", "the stored *** leaked"),
            ("connected to AqulaSoft in 64 ms", "connected to AqulaSoft in 64 ms"),
        ]
        // Hostile lines stay linear: «tokentoken…» once took 11 s.
        for hostile in [String(repeating: "token", count: 13_000), String(repeating: "api_key_", count: 8_000),
                        "http://" + String(repeating: "a:", count: 32_000), String(repeating: "a", count: 65_000)] {
            let began = Date()
            _ = ServiceLogs.mask(hostile, secrets: ["s3cr3t-value"])
            XCTAssertTrue(Date().timeIntervalSince(began) < 1, "masking \(hostile.prefix(12))… took too long")
        }
        for (raw, masked) in cases {
            XCTAssertEqual(ServiceLogs.mask(raw, secrets: ["s3cr3t-value", "abc"]), masked, raw)
        }
    }

    func secrets() throws {
        let m = try load(try folder(try manifest()))
        let store = MemorySecretStore()
        try store.write("t0ken", m.secretScope, "TOKEN")
        try store.write("ignored", "other", "TOKEN")
        XCTAssertEqual(store.all(m), ["TOKEN": "t0ken"])
        XCTAssertTrue(store.contains(m.secretScope, "TOKEN") && !store.contains(m.secretScope, "OWNER"))
        try store.write("", m.secretScope, "TOKEN")
        XCTAssertEqual(store.all(m), [:], "an empty value deletes")

        // Secrets belong to the id and the folder: another folder claiming the same id sees none.
        let twin = try load(try folder(try manifest()))
        XCTAssertEqual(twin.id, m.id)
        XCTAssertTrue(twin.secretScope != m.secretScope && twin.secretScope.hasPrefix("svc."))
        XCTAssertEqual(ServiceEntry(manifest: m).secretScope, m.secretScope)
        try store.write("t0ken", m.secretScope, "TOKEN")
        XCTAssertEqual(store.all(twin), [:])

        // Removing takes every key of the scope, also ones the manifest no longer lists.
        try store.write("old", m.secretScope, "RENAMED_KEY")
        XCTAssertEqual(store.keys(m.secretScope), ["RENAMED_KEY", "TOKEN"])
        try store.removeAll(m.secretScope)
        XCTAssertEqual(store.keys(m.secretScope), [])
        XCTAssertEqual(store.read("other", "TOKEN"), "ignored")
        XCTAssertEqual(KeychainSecretStore.service("chedrik.0a1b2c3d4e5f"), "com.forichok.agents-notch.service.chedrik.0a1b2c3d4e5f")
    }
}
