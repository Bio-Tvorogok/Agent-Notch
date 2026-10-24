
struct WidgetPlanChecks {
    private func a(_ id: String, _ state: AgentState, _ project: String = "p", parent: String? = nil) -> Agent {
        Agent(id: id, vendor: .claude, title: id, state: state, project: project, parentId: parent, startedAt: Double(id.hashValue & 0xffff))
    }

    private func ids(_ lines: [WidgetLine]) -> [String] {
        lines.map {
            switch $0 {
            case .project(let name): return "#" + name
            case .session(let a, let folded): return folded > 0 ? "\(a.id)+\(folded)" : a.id
            case .kid(let a, let last): return (last ? "└" : "├") + a.id
            case .doneKids(let kids): return "done:" + kids.map(\.id).joined(separator: ",")
            case .attention(let a, _): return "!" + a.id
            case .more(let n): return "more:\(n)"
            }
        }
    }

    func projectsAreAlphabetical() {
        let p = Tree.build([a("z1", .working, "zeta"), a("a1", .waiting, "alpha"), a("m1", .working, "mid")])
        XCTAssertEqual(ids(WidgetPlan.lines(p, tree: .auto, capacity: 20)), ["#alpha", "!a1", "#mid", "m1", "#zeta", "z1"])
    }

    func everythingFitsUntouched() {
        let p = Tree.build([a("s", .working), a("k1", .working, parent: "s"), a("k2", .done, parent: "s"), a("f", .done)], includeFinished: true)
        XCTAssertEqual(ids(WidgetPlan.lines(p, tree: .expanded, capacity: 20)), ["s", "├k1", "done:k2", "f"])
    }

    /// Finished agents go first, then subagents fold, then calm sessions give way; waiting and failed ones stay.
    func overflowSteps() {
        let p = Tree.build([a("s", .working), a("k1", .working, parent: "s"), a("k2", .done, parent: "s"), a("f", .done)], includeFinished: true)
        XCTAssertEqual(ids(WidgetPlan.lines(p, tree: .expanded, capacity: 3)), ["s", "└k1", "more:1"])
        XCTAssertEqual(ids(WidgetPlan.lines(p, tree: .expanded, capacity: 2)), ["s+2", "more:1"])
        let busy = Tree.build((1...6).map { a("w\($0)", .working) } + [a("x", .error), a("q", .waiting)])
        let lines = WidgetPlan.lines(busy, tree: .auto, capacity: 9)
        XCTAssertTrue(ids(lines).contains("!x") && ids(lines).contains("!q"), "urgent agents always stay")
        XCTAssertEqual(ids(lines).last, "more:2")
        XCTAssertTrue(WidgetPlan.cost(lines) <= 9)
        let tiny = WidgetPlan.lines(busy, tree: .auto, capacity: 2)
        XCTAssertEqual(ids(tiny), ["!x", "!q", "more:6"], "urgent agents stay even past the capacity")
    }

    func urgentSubagentStaysWhenFolded() {
        let p = Tree.build([a("s", .working), a("k1", .working, parent: "s"), a("k2", .working, parent: "s"), a("k3", .waiting, parent: "s")]
                           + (1...4).map { a("w\($0)", .working) })
        let lines = WidgetPlan.lines(p, tree: .expanded, capacity: 6)
        XCTAssertTrue(ids(lines).contains("s+2"))
        XCTAssertTrue(lines.contains(.attention(p[0].sessions.first { $0.id == "s" }!.kids[0], parent: "s")))
    }

    func pendingRequestPins() {
        let p = Tree.build([a("s", .working), a("t", .working)])
        XCTAssertEqual(ids(WidgetPlan.lines(p, tree: .auto, pinned: ["t"], capacity: 10)).filter { $0.hasPrefix("!") }, ["!t"])
    }

    func russianPlurals() {
        XCTAssertEqual([1, 2, 5, 11, 21, 22, 25].map(WidgetText.working),
                       ["агент работает", "агента работают", "агентов работают", "агентов работают", "агент работает", "агента работают", "агентов работают"])
    }
}
