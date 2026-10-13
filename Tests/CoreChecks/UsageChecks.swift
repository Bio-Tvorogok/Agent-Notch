import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

struct UsageChecks {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func home() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID())") }
    func write(_ file: URL, _ records: [Rec], append: Bool = false) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data()
        for record in records { data += try JSONSerialization.data(withJSONObject: record); data.append(10) }
        if append {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: data)
        } else { try data.write(to: file) }
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
    }
    func stamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    func claude(_ id: String, model: String = "claude-sonnet-4", date: Date? = nil) -> Rec {
        ["type": "assistant", "timestamp": stamp(date ?? now), "cwd": "/repo", "message": [
            "id": id, "model": model, "usage": ["input_tokens": 100, "cache_creation_input_tokens": 20,
                                                     "cache_read_input_tokens": 30, "output_tokens": 50]]]
    }
    func codex(_ total: Int, date: Date? = nil, last: Int = 40) -> Rec {
        ["type": "event_msg", "timestamp": stamp(date ?? now), "payload": ["type": "token_count", "info": [
            "model_context_window": 1000, "last_token_usage": ["input_tokens": last - 10, "output_tokens": 10, "total_tokens": last],
            "total_token_usage": ["input_tokens": total - 20, "cached_input_tokens": 0, "output_tokens": 20, "total_tokens": total]]]]
    }
    func limits() throws {
        let h = home(); defer { try? FileManager.default.removeItem(at: h) }
        let file = h.appendingPathComponent(".codex/sessions/2027/01/15/a.jsonl")
        var record = codex(200)
        var payload = record["payload"] as? Rec ?? [:]
        payload["rate_limits"] = ["primary": ["used_percent": 27.5, "window_minutes": 300, "resets_at": 1_800_001_000],
                                  "secondary": ["used_percent": 61, "window_minutes": 10080], "plan_type": "pro",
                                  "credits": ["has_credits": true, "balance": "12"]] as Rec
        record["payload"] = payload
        try write(file, [record, codex(220)])
        let result = try XCTUnwrap(LimitsReader.read(home: h, now: now).first)
        XCTAssertEqual(result.vendor, .codex); XCTAssertEqual(result.plan, "pro")
        XCTAssertEqual(result.windows.map(\.usedPercent), [27.5, 61])
        XCTAssertEqual(result.windows.map(\.label), ["5 ч", "неделя"])
        XCTAssertEqual(result.windows.first?.resetsAt, Date(timeIntervalSince1970: 1_800_001_000))
        XCTAssertEqual(result.updatedAt, now)
        XCTAssertFalse(LimitsReader.read(home: h, now: now).contains { $0.vendor == .claude })
        XCTAssertTrue(LimitsReader.read(home: home(), now: now).isEmpty)
        let stale = h.appendingPathComponent(".codex/sessions/2027/01/15/old.jsonl")
        record["timestamp"] = stamp(now.addingTimeInterval(-3600))
        payload["rate_limits"] = ["primary": ["used_percent": 1, "window_minutes": 300]]
        record["payload"] = payload
        try write(stale, [record])
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(30)], ofItemAtPath: stale.path)
        XCTAssertEqual(LimitsReader.read(home: h, now: now).first?.windows.first?.usedPercent, 27.5,
                       "unrelated appends must not replace a newer rate-limit snapshot")

    }
    func claudeLimits() throws {
        let h = home(); defer { try? FileManager.default.removeItem(at: h) }
        let file = h.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let history: Rec = ["version": 2, "samples": [
            ["t": now.addingTimeInterval(-600).timeIntervalSince1970 * 1000, "org": "synthetic", "u": ["fh": 10, "sd": 30]],
            ["t": now.addingTimeInterval(-60).timeIntervalSince1970 * 1000, "org": "synthetic", "u": ["fh": 12, "sd": 33]]]]
        try JSONSerialization.data(withJSONObject: history).write(to: file)
        let result = try XCTUnwrap(LimitsReader.read(home: h, now: now).first)
        XCTAssertEqual(result.vendor, .claude)
        XCTAssertEqual(result.windows.map(\.usedPercent), [12, 33])
        XCTAssertEqual(result.updatedAt, now.addingTimeInterval(-60))
        XCTAssertTrue(result.windows.allSatisfy { $0.resetsAt == nil })
        XCTAssertNil(result.plan)
    }
    func context() throws {
        let h = home(); defer { try? FileManager.default.removeItem(at: h) }
        let c = h.appendingPathComponent("claude.jsonl"), x = h.appendingPathComponent("codex.jsonl")
        try write(c, [claude("a"), claude("b", model: "claude-opus-4[1m]")])
        let big = try XCTUnwrap(ContextFill.read(path: c.path, vendor: .claude))
        XCTAssertEqual(big.usedTokens, 200); XCTAssertEqual(big.windowTokens, 1_000_000)
        XCTAssertEqual(big.percent, 0.02)
        try write(c, [claude("a")])
        XCTAssertEqual(ContextFill.read(path: c.path, vendor: .claude)?.windowTokens, 200_000)
        try write(x, [codex(200), codex(300, last: 70)])
        XCTAssertEqual(ContextFill.read(path: x.path, vendor: .codex)?.usedTokens, 70)
        XCTAssertEqual(ContextFill.read(path: x.path, vendor: .codex)?.percent, 7)
        try write(x, [["type": "event_msg", "payload": ["type": "token_count", "info": [
            "model_context_window": 1000, "total_token_usage": ["total_tokens": 250]]]]])
        XCTAssertEqual(ContextFill.read(path: x.path, vendor: .codex)?.percent, 25)
        try write(x, [["type": "event_msg", "payload": ["type": "token_count", "info": ["model_context_window": 0]]]])
        XCTAssertNil(ContextFill.read(path: x.path, vendor: .codex))
        XCTAssertNil(ContextFill.read(path: h.appendingPathComponent("missing").path, vendor: .claude))
    }
    /// A model name without a [1m] marker still runs a 1M window once it holds more than 200k tokens.
    func contextOverDefaultWindow() throws {
        let h = home(); defer { try? FileManager.default.removeItem(at: h) }
        let c = h.appendingPathComponent("claude.jsonl")
        var rec = claude("a", model: "claude-opus-5-5")
        var msg = rec["message"] as! Rec
        msg["usage"] = ["input_tokens": 10, "cache_read_input_tokens": 259_850, "output_tokens": 0]
        rec["message"] = msg
        try write(c, [rec])
        let fill = try XCTUnwrap(ContextFill.read(path: c.path, vendor: .claude))
        XCTAssertEqual(fill.windowTokens, 1_000_000)
        XCTAssertTrue(fill.percent <= 100)
    }
    func spend() throws {
        let h = home(); defer { try? FileManager.default.removeItem(at: h) }
        let c = h.appendingPathComponent(".claude/projects/p/a.jsonl")
        let x = h.appendingPathComponent(".codex/sessions/2027/01/15/a.jsonl")
        let midnight = Calendar.current.startOfDay(for: now)
        try write(c, [claude("old", date: midnight.addingTimeInterval(-1)), claude("a"), claude("a")])
        try write(x, [["type": "session_meta", "payload": ["cwd": "/repo"]],
                      ["type": "turn_context", "payload": ["model": "gpt-6.1-sol"]],
                      codex(100, date: midnight.addingTimeInterval(-1)), codex(300), codex(300)])
        let result = Spend.today(home: h, now: now, project: { $0 ?? "unknown" })
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result.first?.project, "/repo")
        XCTAssertEqual(result.first?.tokens, 400, "Claude message counted once; Codex cumulative delta excludes yesterday")
        XCTAssertTrue((result.first?.usd ?? 0) > 0)
        XCTAssertEqual(Spend.today(home: h, now: now, project: { $0 ?? "unknown" }).first?.tokens, 400)
        try write(c, [claude("b", model: "unknown-model")], append: true)
        XCTAssertEqual(Spend.today(home: h, now: now, project: { $0 ?? "unknown" }).first?.tokens, 600)
        XCTAssertNil(Spend.today(home: h, now: now, project: { $0 ?? "unknown" }).first?.usd)
        try write(c, [claude("replacement")])
        XCTAssertEqual(Spend.today(home: h, now: now, project: { $0 ?? "unknown" }).first?.tokens, 400)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        XCTAssertTrue(Spend.today(home: h, now: tomorrow, project: { $0 ?? "unknown" }).isEmpty)
    }
    func incrementalSpend() throws {
        let h = home(); defer { try? FileManager.default.removeItem(at: h) }
        let file = h.appendingPathComponent(".claude/projects/p/a.jsonl")
        try write(file, [claude("a")])
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        let filler = Data(("{\"type\":\"user\",\"padding\":\"" + String(repeating: "x", count: 1024) + "\"}\n").utf8)
        for _ in 0..<9000 { try handle.write(contentsOf: filler) }
        try handle.close()
        try write(file, [claude("b")], append: true)
        XCTAssertEqual(Spend.today(home: h, now: now, project: { _ in "p" }).first?.tokens, 200)
        XCTAssertFalse(Spend.isComplete)
        XCTAssertTrue(Spend.today(home: h, now: now, project: { _ in "p" }).first?.tokens == 400)
        XCTAssertTrue(Spend.isComplete)
        let message = try JSONSerialization.data(withJSONObject: claude("c"))
        let append = try FileHandle(forWritingTo: file)
        try append.seekToEnd(); try append.write(contentsOf: message.prefix(message.count / 2))
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
        XCTAssertEqual(Spend.today(home: h, now: now, project: { _ in "p" }).first?.tokens, 400)
        try append.write(contentsOf: message.suffix(message.count - message.count / 2) + Data([10]))
        try append.close()
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
        XCTAssertEqual(Spend.today(home: h, now: now, project: { _ in "p" }).first?.tokens, 600)
    }
    func cachedSpend() throws {
        let h = home(); defer { try? FileManager.default.removeItem(at: h) }
        let file = h.appendingPathComponent(".codex/sessions/a.jsonl")
        func event(_ input: Int, _ cached: Int, _ output: Int) -> Rec {
            ["type": "event_msg", "timestamp": stamp(now), "payload": ["type": "token_count", "info": [
                "total_token_usage": ["input_tokens": input, "cached_input_tokens": cached, "output_tokens": output]]]]
        }
        try write(file, [["type": "session_meta", "payload": ["cwd": "/repo"]],
                         ["type": "turn_context", "payload": ["model": "gpt-6.1-sol"]],
                         event(100, 0, 10), event(110, 100, 20), event(110, 100, 20)])
        let row = try XCTUnwrap(Spend.today(home: h, now: now, project: { _ in "p" }).first)
        XCTAssertEqual(row.tokens, 130, "cache is a subset of input; repeated events add nothing")
        XCTAssertTrue(abs((row.usd ?? 0) - 0.0005525) < 0.000000001)
    }

    func spendCopiesAndSynthetic() throws {
        let h = home(); defer { try? FileManager.default.removeItem(at: h) }
        let a = h.appendingPathComponent(".claude/projects/p/a.jsonl")
        let z = h.appendingPathComponent(".claude/projects/p/z.jsonl")
        var stale = claude("same", date: now.addingTimeInterval(-60))
        var message = stale["message"] as? Rec ?? [:]
        var amounts = message["usage"] as? Rec ?? [:]
        amounts["output_tokens"] = 1; message["usage"] = amounts; stale["message"] = message
        try write(a, [claude("same")]); try write(z, [stale])
        XCTAssertEqual(Spend.today(home: h, now: now, project: { _ in "p" }).first?.tokens, 200)
        try FileManager.default.removeItem(at: z)
        let zero: Rec = ["type": "assistant", "timestamp": stamp(now), "message": ["id": "error",
            "model": "<synthetic>", "usage": ["input_tokens": 0, "output_tokens": 0]]]
        try write(a, [zero], append: true)
        let row = Spend.today(home: h, now: now, project: { _ in "p" }).first
        XCTAssertEqual(row?.tokens, 200)
        XCTAssertTrue(abs((row?.usd ?? 0) - 0.001134) < 0.000000001)
        XCTAssertEqual(ContextFill.read(path: a.path, vendor: .claude)?.usedTokens, 200)
    }

}
