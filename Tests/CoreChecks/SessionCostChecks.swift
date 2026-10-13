import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

/// Per-session cost: the whole log of one session, not just today, priced by its own models.
struct SessionCostChecks {
    let u = UsageChecks()

    func close(_ a: Double?, _ b: Double, file: StaticString = #fileID, line: UInt = #line) {
        guard let a else { return report("expected \(b), got nil", file, line) }
        if abs(a - b) > 1e-9 { report("\(a) != \(b)", file, line) }
    }

    func claude() throws {
        let h = u.home(); defer { try? FileManager.default.removeItem(at: h) }
        let file = h.appendingPathComponent("s.jsonl")
        let old = u.now.addingTimeInterval(-3 * 86_400)
        // A repeated message id is one reply, counted once; days do not matter for a session.
        try u.write(file, [u.claude("m1", date: old), u.claude("m1", date: old), u.claude("m2", model: "claude-opus-5")])
        let spend = SessionSpend()
        let cost = try XCTUnwrap(spend.read(path: file.path, vendor: .claude))
        XCTAssertEqual(cost.tokens, 400)
        // sonnet: 100×3 + 30×0.3 + 20×3.75 + 50×15; opus: 100×5 + 30×0.5 + 20×6.25 + 50×25 (per million)
        close(cost.usd, (1134 + 1890) / 1_000_000)
        let read = spend.bytesRead
        XCTAssertEqual(spend.read(path: file.path, vendor: .claude), cost, "unchanged log gives the cached answer")
        XCTAssertEqual(spend.bytesRead, read, "an unchanged log is not read again")
        try u.write(file, [u.claude("m3")], append: true)
        let next = try XCTUnwrap(spend.read(path: file.path, vendor: .claude))
        XCTAssertEqual(next.tokens, 600)
        XCTAssertTrue(spend.bytesRead - read < 1000, "only the appended line is read")
        try u.write(file, [u.claude("m4", model: "claude-mystery-9")], append: true)
        let unknown = try XCTUnwrap(spend.read(path: file.path, vendor: .claude))
        XCTAssertNil(unknown.usd, "an unknown model price gives no number, not $0")
        XCTAssertNil(CardFormat.cost(unknown))
        XCTAssertNil(SessionSpend().read(path: h.appendingPathComponent("none.jsonl").path, vendor: .claude))
    }

    func codex() throws {
        let h = u.home(); defer { try? FileManager.default.removeItem(at: h) }
        let file = h.appendingPathComponent("c.jsonl")
        let turn: Rec = ["type": "turn_context", "timestamp": u.stamp(u.now), "payload": ["model": "gpt-6.1-sol", "cwd": "/repo"]]
        try u.write(file, [turn, u.codex(200), u.codex(300)])
        let cost = try XCTUnwrap(SessionSpend().read(path: file.path, vendor: .codex))
        XCTAssertEqual(cost.tokens, 300)
        // sol: 280 input × 2.5 + 20 output × 15 (per million)
        close(cost.usd, 0.001)
        XCTAssertEqual(CardFormat.cost(cost), "< $0.01")
        let other = h.appendingPathComponent("d.jsonl")
        var mystery = turn; mystery["payload"] = ["model": "gpt-mystery"]
        try u.write(other, [mystery, u.codex(200)])
        XCTAssertNil(try XCTUnwrap(SessionSpend().read(path: other.path, vendor: .codex)).usd)
    }

    func format() {
        XCTAssertEqual(CardFormat.cost(SessionCost(tokens: 1, usd: 0.4217)), "≈ $0.42")
        XCTAssertEqual(CardFormat.cost(SessionCost(tokens: 1, usd: 12.5)), "≈ $12.50")
        XCTAssertEqual(CardFormat.cost(SessionCost(tokens: 1, usd: 0.0004)), "< $0.01")
        XCTAssertNil(CardFormat.cost(SessionCost(tokens: 1, usd: nil)))
        XCTAssertNil(CardFormat.cost(nil))
    }
}
