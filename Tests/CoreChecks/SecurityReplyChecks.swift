import Foundation

struct SecurityReplyChecks {
    func invalidAlways() throws {
        let e = AlwaysChecks().event("Bash", "git status")
        let rule = try XCTUnwrap(AlwaysRule.suggest(for: AlwaysChecks().event()))
        XCTAssertNil(HookReply.helperStdout(event: e, name: e.name, decision: .allowAlways(rule)))
        XCTAssertNil(HookReply.helperStdout(event: nil, name: e.name, decision: .allowAlways(rule)))
        for value: Any in [[:], "invalid", NSNull()] {
            XCTAssertNil(HookDecision(wire: ["decision": "allow", "always": value]))
        }
        let mcp = AlwaysChecks().event("mcp__docs__search", nil)
        let mcpRule = try XCTUnwrap(AlwaysRule.suggest(for: mcp))
        for field in ["ruleContent", "prefix"] {
            for invalid: Any in [false, 123, NSNull()] {
                var wire = mcpRule.wire
                wire[field] = invalid
                let decision = HookDecision(wire: ["decision": "allow", "always": wire])
                XCTAssertNil(decision)
                XCTAssertNil(decision.flatMap { HookReply.helperStdout(event: mcp, name: mcp.name, decision: $0) })
            }
        }
        XCTAssertEqual(HookDecision(wire: ["decision": "allow"]), .allow)
        let valid = AlwaysChecks().event()
        let out = try XCTUnwrap(HookReply.helperStdout(event: valid, name: valid.name, decision: .allowAlways(rule)))
        XCTAssertTrue(out.contains("updatedPermissions"))
    }
}
