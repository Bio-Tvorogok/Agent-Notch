import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

#if CARD_MODEL_CHECK
@main
struct CardModelChecks {
    @MainActor static func main() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: path) }
        try "{\"type\":\"session_meta\",\"payload\":{\"cwd\":\"/test\"}}\n".write(to: path, atomically: true, encoding: .utf8)
        let model = CardDetailModel()
        var agent = Agent(id: "test", vendor: .codex, title: "initial", state: .working, project: "test")
        model.show(agent)
        await settle(model)
        agent.logPath = path.path
        agent.title = "updated"
        model.update(agent)
        await settle(model)
        guard model.agent?.title == "updated", model.detail?.meta.cwd == "/test" else {
            print("FAIL card does not pick up a newly discovered log path"); exit(1)
        }
        agent.state = .done
        model.update(agent)
        guard model.agent?.state == .done, model.detail?.meta.cwd == "/test" else { exit(1) }
        model.close()
        guard model.agent == nil, model.detail == nil else { exit(1) }
        print("OK card model late log path and close")
    }

    @MainActor private static func settle(_ model: CardDetailModel) async {
        for _ in 0..<100 where model.loading { try? await Task.sleep(for: .milliseconds(20)) }
    }
}
#else
struct CardChecks {
    func grouping() {
        let detail = AgentDetail(plan: [
            PlanItem(text: "later", status: .todo), PlanItem(text: "shipped", status: .done),
            PlanItem(text: "now", status: .active)
        ], commands: [CommandRun(command: "make", ok: true), CommandRun(command: "pytest", ok: false)])
        XCTAssertEqual(CardContent.plan(detail, tab: .done).map(\.text), ["shipped"])
        XCTAssertEqual(CardContent.plan(detail, tab: .remaining).map(\.text), ["now", "later"])
        XCTAssertTrue(CardContent.plan(detail, tab: .files).isEmpty)
        XCTAssertEqual(CardContent.commands(detail, limit: 1).map(\.command), ["pytest"])
        XCTAssertTrue(CardContent.commands(detail, limit: 0).isEmpty)
        XCTAssertTrue(CardContent.commands(detail, limit: -1).isEmpty)
        XCTAssertEqual(CardContent.result(detail.commands[0]), "✓")
        XCTAssertEqual(CardContent.result(detail.commands[1]), "✗")
        XCTAssertEqual(CardContent.result(CommandRun(command: "running")), "…")
    }

    func visibility() {
        XCTAssertEqual(CardContent.tabs(blocks: [.files, .remaining, .files]), [.files, .remaining])
        XCTAssertTrue(CardContent.tabs(blocks: [.commands, .errors]).isEmpty)
        XCTAssertEqual(CardContent.tabs(blocks: CardBlock.allCases), [.done, .remaining, .files, .log])
    }

    func formatting() {
        XCTAssertNil(CardFormat.duration(startedAt: nil, now: 100))
        XCTAssertNil(CardFormat.duration(startedAt: .nan, now: 100))
        XCTAssertNil(CardFormat.duration(startedAt: 1, now: .infinity))
        XCTAssertEqual(CardFormat.duration(startedAt: 100, now: 99), "0 с")
        XCTAssertEqual(CardFormat.duration(startedAt: 100, now: 159), "59 с")
        XCTAssertEqual(CardFormat.duration(startedAt: 100, now: 161), "1 мин")
        XCTAssertEqual(CardFormat.duration(startedAt: 100, now: 3760), "1 ч 1 мин")
        // A finished run stops at its last activity; a live one runs to now; over two days is nonsense.
        XCTAssertEqual(CardFormat.runTime(startedAt: 100, lastAt: 220, live: false, now: 9_000), "2 мин")
        XCTAssertEqual(CardFormat.runTime(startedAt: 100, lastAt: 220, live: true, now: 160), "1 мин")
        XCTAssertNil(CardFormat.runTime(startedAt: 100, lastAt: nil, live: false, now: 9_000))
        XCTAssertNil(CardFormat.runTime(startedAt: 100, lastAt: nil, live: true, now: 100 + 2 * 86_400))
        XCTAssertNil(CardFormat.runTime(startedAt: 100, lastAt: 100 + 3 * 86_400, live: false, now: 0))
        XCTAssertEqual(CardFormat.path("/repo/src/a.swift", cwd: "/repo", home: "/Users/test"), "src/a.swift")
        XCTAssertEqual(CardFormat.path("/repository/a", cwd: "/repo", home: "/Users/test"), "/repository/a")
        XCTAssertEqual(CardFormat.path("/Users/test/repo/a", cwd: nil, home: "/Users/test"), "~/repo/a")
        XCTAssertEqual(CardFormat.path("/Users/test-other/a", cwd: nil, home: "/Users/test"), "/Users/test-other/a")
        XCTAssertEqual(CardFormat.path("src/a.swift", cwd: "/repo/", home: "/Users/test"), "src/a.swift")
        XCTAssertEqual(CardFormat.path("/repo/a", cwd: "/repo/", home: "/Users/test"), "a")
        XCTAssertEqual(CardFormat.path("/repo", cwd: "/repo", home: "/Users/test"), ".")
    }
}
#endif
