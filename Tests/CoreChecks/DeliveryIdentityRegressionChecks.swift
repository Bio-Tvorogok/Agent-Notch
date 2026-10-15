import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

/// These checks use the original API so they can also exercise the unmodified master module.
struct DeliveryIdentityRegressionChecks {
    func event(_ id: String, _ name: String, question: Bool = false) throws -> HookEvent {
        try XCTUnwrap(HookEvent(vendor: .claude, payload: ["session_id": "s", "hook_event_name": name,
            "tool_use_id": id, "tool_name": question ? "AskUserQuestion" : "Bash",
            "tool_input": question ? ["questions": [["question": "Where?", "options": [["label": "Here"]]]]] : ["command": "echo hello"]]))
    }

    func identicalCommands() throws {
        var state = HookState()
        _ = state.receive(try event("a", "PermissionRequest"), ticket: 1, now: 0)
        _ = state.receive(try event("b", "PostToolUse"), ticket: nil, now: 1)
        XCTAssertEqual(state.pending.map(\.ticket), [1], "a different tool_use_id cannot resolve the displayed request")
    }

    func questionRoute() throws {
        var route = AnswerRoute()
        route.noteRouted(try event("a", "PreToolUse", question: true), now: 0)
        XCTAssertFalse(route.isHandedBack(try event("b", "PermissionRequest", question: true), now: 1))
        XCTAssertTrue(route.isHandedBack(try event("a", "PermissionRequest", question: true), now: 2))
    }
}
