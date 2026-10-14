import Foundation

struct LogTimeChecks {
    func datesKeepTheirValues() {
        let cases: [(String, Double)] = [
            ("1970-01-01T00:00:00Z", 0),
            ("1969-12-31T23:59:59.999Z", -0.001),
            ("2026-10-14T06:24:04Z", 1_791_959_044),
            ("2026-10-14T06:24:04.123Z", 1_791_959_044.123),
            ("2026-10-14T06:24:04.1Z", 1_791_959_044.1),
            ("2026-10-14T06:24:04.12Z", 1_791_959_044.12),
            ("2026-10-14T06:24:04.123456Z", 1_791_959_044.123),
            ("2026-10-14T09:24:04.123+03:00", 1_791_959_044.123),
            ("2026-10-14T01:24:04-05:00", 1_791_959_044),
            ("2024-02-29T00:00:00.500Z", 1_709_164_800.5),
        ]
        for (text, expected) in cases {
            guard let actual = LogText.time(text) else { XCTFail("missing timestamp: \(text)"); continue }
            XCTAssertTrue(abs(actual - expected) < 0.000001, "timestamp changed: \(text): \(actual)")
        }
        for invalid in ["", "not a date", "2026-10-14TgarbageZ", "2026-10-14T96:24:04.123Z", "2026-10-14T06:60:04Z", "2026-10-14T06:24:60Z"] {
            XCTAssertNil(LogText.time(invalid), invalid)
        }
        XCTAssertNil(LogText.time(nil))
        XCTAssertNil(LogText.time(123))
    }

    func invalidTimeDoesNotExtendSession() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("timestamp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".claude/projects/p/thread.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let rows = """
        {"type":"user","timestamp":"2026-10-14T06:14:04Z","cwd":"/tmp","message":{"content":"hello"}}
        {"type":"assistant","timestamp":"2026-10-14T96:24:04.123Z","message":{"content":[],"stop_reason":"tool_use"}}

        """
        try rows.write(to: file, atomically: false, encoding: .utf8)
        let now = Date(timeIntervalSince1970: 1_791_959_044)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
        XCTAssertEqual(LogScanner(home: home, execRuns: { [] }).poll(now: now).map(\.state), [.done],
                       "a malformed future timestamp must not keep an idle session working")
    }
}
