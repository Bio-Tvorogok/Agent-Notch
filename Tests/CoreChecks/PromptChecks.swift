import Foundation

/// The owner's own words in a session: the first prompt and every later one, without harness inserts.
struct PromptChecks {
    let detail = DetailChecks()

    func claude() throws {
        func user(_ content: Any, _ extra: Rec = [:], at: String = "2026-10-13T10:00:00Z") -> Rec {
            ["type": "user", "timestamp": at, "message": ["role": "user", "content": content]].merging(extra) { $1 }
        }
        let human: Rec = ["origin": ["kind": "human"]]
        try detail.fixture([
            user([["type": "text", "text": "<system-reminder>\nworktree\n</system-reminder>"],
                  ["type": "text", "text": "Сделай вкладку\nс запросами"]], human),
            user("Stop hook feedback:\nreview", ["isMeta": true]),
            user("<task-notification>\n<task-id>b1</task-id>", ["origin": ["kind": "task-notification"]]),
            user("This session is being continued from a previous conversation", ["isCompactSummary": true]),
            user("<bash-input>git status</bash-input>", human),
            user([["type": "tool_result", "tool_use_id": "t", "content": "ok"]]),
            user([["type": "text", "text": "[Request interrupted by user]"]]),
            user("Another Claude session sent a message:\nhi", ["isMeta": true, "origin": ["from": "local_x"]]),
            user("продолжай", human, at: "2026-10-13T10:05:00Z"),
            user("  ", human),
            ["type": "user", "isSidechain": true, "message": ["content": "subagent brief"]]
        ]) { path in
            let d = try XCTUnwrap(DetailReader.read(path: path, vendor: .claude))
            XCTAssertEqual(d.prompts.map(\.text), ["Сделай вкладку\nс запросами", "продолжай"])
            XCTAssertEqual(d.startPrompt?.text, "Сделай вкладку\nс запросами")
            XCTAssertEqual(d.prompts.last?.at, LogText.time("2026-10-13T10:05:00Z"))
            XCTAssertEqual(CardContent.prompts(d).later.map(\.text), ["продолжай"])
        }
    }

    func codex() throws {
        func said(_ text: String, at: String = "2026-10-13T10:01:00Z") -> Rec {
            ["type": "response_item", "timestamp": at,
             "payload": ["type": "message", "role": "user", "content": [["type": "input_text", "text": text]]]]
        }
        try detail.fixture([
            ["type": "session_meta", "payload": ["cwd": "/repo"]],
            said("# AGENTS.md instructions\n\n<INSTRUCTIONS>rules</INSTRUCTIONS>"),
            said("<environment_context>\n<cwd>/repo</cwd>\n</environment_context>"),
            said("Card: X-1\nTask: собрать карточку"),
            // Older Codex writes the same prompt again as an event: it must not double.
            ["type": "event_msg", "payload": ["type": "user_message", "message": "Card: X-1\nTask: собрать карточку"]],
            ["type": "response_item", "payload": ["type": "message", "role": "assistant",
                "content": [["type": "output_text", "text": "готово"]]]],
            said("а теперь тесты", at: "2026-10-13T10:09:00Z")
        ]) { path in
            let d = try XCTUnwrap(DetailReader.read(path: path, vendor: .codex))
            XCTAssertEqual(d.prompts.map(\.text), ["Card: X-1\nTask: собрать карточку", "а теперь тесты"])
            XCTAssertEqual(d.startPrompt?.text, "Card: X-1\nTask: собрать карточку")
            XCTAssertEqual(d.prompts.last?.at, LogText.time("2026-10-13T10:09:00Z"))
        }
    }

    /// A long session is read from its tail, but the first prompt still comes from the head.
    func startSurvivesTail() throws {
        try detail.fixture([
            ["type": "user", "message": ["content": "первый запрос"], "origin": ["kind": "human"]],
            ["type": "padding", "value": String(repeating: "x", count: 9 << 20)],
            ["type": "user", "message": ["content": "поздний запрос"], "origin": ["kind": "human"]]
        ]) { path in
            let d = try XCTUnwrap(DetailReader.read(path: path, vendor: .claude))
            XCTAssertEqual(d.startPrompt?.text, "первый запрос")
            XCTAssertEqual(d.prompts.map(\.text), ["поздний запрос"])
        }
    }

    /// Long prompts are kept whole up to a cap; only the newest prompts are kept.
    func bounds() throws {
        let rows: [Rec] = (0..<80).map { ["type": "user", "message": ["content": "запрос \($0)"]] }
            + [["type": "user", "message": ["content": String(repeating: "я", count: 9000)]]]
        try detail.fixture(rows) { path in
            let d = try XCTUnwrap(DetailReader.read(path: path, vendor: .claude))
            XCTAssertEqual(d.prompts.count, 50)
            XCTAssertEqual(d.startPrompt?.text, "запрос 0")
            XCTAssertEqual(d.prompts.last?.text.count, 4000)
        }
    }
}
