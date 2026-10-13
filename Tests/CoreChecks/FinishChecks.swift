import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

struct FinishChecks {
    func agent(_ id: String, _ state: AgentState, parent: String? = nil) -> Agent {
        Agent(id: id, vendor: .claude, title: id, state: state, project: "p", parentId: parent)
    }

    func summary() {
        let tests = CommandRun(command: "./scripts/test.sh", ok: true, at: 100)
        var d = AgentDetail(files: [FileChange(path: "a", added: 1, removed: 0), FileChange(path: "b", added: 2, removed: 1),
                                    FileChange(path: "c", added: 1, removed: 1)],
                            commands: [CommandRun(command: "make", ok: false, at: 90), tests,
                                       CommandRun(command: "cd x && git commit -m wip", ok: true, at: 110)],
                            lastMessage: "\n  Готово: загрузка сжимается.\nВторая строка")
        XCTAssertEqual(FinishSummary.line(d, commit: "abc1234"), "готово · 3 файла · тесты ✓ · коммит abc1234")
        XCTAssertEqual(FinishSummary.line(d), "готово · 3 файла · тесты ✓ · коммит")
        XCTAssertEqual(FinishSummary.preview(d), "Готово: загрузка сжимается.")
        XCTAssertTrue(FinishSummary.madeCommit(d, since: 50))
        // Work stamped before this run does not count.
        XCTAssertEqual(FinishSummary.line(d, since: 105), "готово · 3 файла · коммит")
        XCTAssertFalse(FinishSummary.madeCommit(d, since: 120))
        // Files changed before this run are not counted; unstamped ones stay.
        d.files = [FileChange(path: "a", added: 1, removed: 0, at: 90), FileChange(path: "b", added: 1, removed: 0, at: 120),
                   FileChange(path: "c", added: 1, removed: 0)]
        XCTAssertEqual(FinishSummary.line(d, since: 105), "готово · 2 файла · коммит")
        XCTAssertEqual(FinishSummary.line(d, since: 200), "готово · 1 файл")
        d.files = [FileChange(path: "a", added: 1, removed: 0), FileChange(path: "b", added: 2, removed: 1),
                   FileChange(path: "c", added: 1, removed: 1)]
        // A failed last test shows ✗; a failed commit is not announced; nothing to say leaves just the word.
        d.commands = [CommandRun(command: "pnpm vitest run", ok: false), CommandRun(command: "git commit -m x", ok: false)]
        XCTAssertEqual(FinishSummary.line(d), "готово · 3 файла · тесты ✗")
        XCTAssertEqual(FinishSummary.line(AgentDetail()), "готово")
        XCTAssertNil(FinishSummary.preview(AgentDetail()))
        for (n, text) in [(1, "1 файл"), (2, "2 файла"), (5, "5 файлов"), (11, "11 файлов"), (21, "21 файл"), (24, "24 файла"), (112, "112 файлов")] {
            let files = (0..<n).map { FileChange(path: "f\($0)", added: 0, removed: 0) }
            XCTAssertEqual(FinishSummary.line(AgentDetail(files: files)), "готово · \(text)")
        }
    }

    func watcher() {
        var w = FinishWatcher()
        // The first poll announces nothing, even for a finished agent.
        XCTAssertEqual(w.update([agent("a", .done), agent("b", .working)], now: 1).count, 0)
        let done = w.update([agent("a", .done), agent("b", .done)], now: 5)
        XCTAssertEqual(done.map(\.agent.id), ["b"])
        XCTAssertEqual(done.first?.workedSince, 1)
        XCTAssertEqual(w.update([agent("b", .done)], now: 6).count, 0, "announced once")
        // A permission pause keeps the run; subagents never announce.
        XCTAssertEqual(w.update([agent("c", .working), agent("s", .working, parent: "c")], now: 10).count, 0)
        XCTAssertEqual(w.update([agent("c", .waiting), agent("s", .working, parent: "c")], now: 11).count, 0)
        XCTAssertEqual(w.update([agent("c", .working), agent("s", .done, parent: "c")], now: 12).count, 0)
        let end = w.update([agent("c", .done), agent("s", .done, parent: "c")], now: 13)
        XCTAssertEqual(end.map(\.agent.id), ["c"])
        XCTAssertEqual(end.first?.workedSince, 10)
        // An agent that vanished is forgotten, not announced.
        _ = w.update([agent("d", .working)], now: 20)
        XCTAssertEqual(w.update([], now: 21).count, 0)
        XCTAssertEqual(w.update([agent("d", .done)], now: 22).count, 0)
    }
}
