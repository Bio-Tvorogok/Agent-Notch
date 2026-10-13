import Foundation

extension SettingsChecks {
    func sessionSorts() {
        let a = Agent(id: "a", vendor: .claude, title: "Zulu", state: .working, project: "p", startedAt: 30)
        let b = Agent(id: "b", vendor: .codex, title: "alpha", state: .working, project: "p", startedAt: 10)
        let kid = Agent(id: "k", vendor: .claude, title: "kid", state: .waiting, project: "p", parentId: "b")
        let c = Agent(id: "c", vendor: .claude, title: "Beta", state: .error, project: "p", startedAt: 20)
        let sessions = [SessionNode(agent: a, kids: []), SessionNode(agent: b, kids: [kid]), SessionNode(agent: c, kids: [])]
        XCTAssertEqual(ListFilter.sorted(sessions, by: .attention).map(\.id), ["c", "b", "a"])
        XCTAssertEqual(ListFilter.sorted(sessions, by: .recent).map(\.id), ["a", "c", "b"])
        XCTAssertEqual(ListFilter.sorted(sessions, by: .name).map(\.id), ["b", "c", "a"])
        var tie = a; tie.id = "d"
        XCTAssertEqual(ListFilter.sorted([SessionNode(agent: tie, kids: []), sessions[0]], by: .recent).map(\.id), ["a", "d"])
    }

    /// Round 2: a held request always has a row, hiding follows the agent, and a subfolder never hides its whole repo.
    func filterOwnersAndRoots() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let repo = home.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("docs"), withIntermediateDirectories: true)
        let inDocs = Agent(id: "d", vendor: .claude, title: "d", state: .working, project: "repo", cwd: repo.appendingPathComponent("docs").path)
        let inSrc = Agent(id: "s", vendor: .claude, title: "s", state: .working, project: "repo", cwd: repo.appendingPathComponent("src").path)
        let byFolder = ListFilter(hiddenProjects: [repo.appendingPathComponent("docs").path])
        XCTAssertEqual(byFolder.apply([inDocs, inSrc]).map(\.id), ["s"], "hiding a subfolder keeps the rest of the repo")
        XCTAssertEqual(ListFilter(hiddenProjects: [repo.path]).apply([inDocs, inSrc]).map(\.id), [])
        // A hidden agent with a held request still gets its row.
        XCTAssertEqual(byFolder.apply([inDocs, inSrc], keeping: ["d"]).map(\.id), ["d", "s"])
        // The event's cwd is visible but the agent it belongs to is hidden: hand it back.
        let event = HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: "d", cwd: repo.appendingPathComponent("src").path, tool: "Bash")
        XCTAssertTrue(byFolder.shouldPass(event, project: "repo", answerFromNotch: true, owner: inDocs))
        XCTAssertFalse(byFolder.shouldPass(event, project: "repo", answerFromNotch: true, owner: inSrc))
    }

    func flatSessions() {
        let agents = [Agent(id: "a", vendor: .claude, title: "Zulu", state: .working, project: "one"),
                      Agent(id: "b", vendor: .codex, title: "Alpha", state: .working, project: "two"),
                      Agent(id: "k", vendor: .codex, title: "kid", state: .working, project: "two", parentId: "b")]
        let projects = Tree.build(agents)
        let flat = ListFilter.sections(projects, grouped: false, order: .name)
        XCTAssertEqual(flat.count, 1)
        XCTAssertEqual(flat.flatMap(\.sessions).map(\.id), ["b", "a"])
        XCTAssertEqual(flat.first?.sessions.first?.kids.map(\.id), ["k"])
        XCTAssertEqual(ListFilter.sections(projects, grouped: true, order: .name).count, 2)
        XCTAssertEqual(ListFilter.sections([], grouped: false, order: .name), [])
    }

    func visibilityAndPass() {
        let agents = [Agent(id: "a", vendor: .claude, title: "a", state: .working, project: "repo", cwd: "/tmp/repo/src"),
                      Agent(id: "b", vendor: .codex, title: "b", state: .working, project: "repo-other", cwd: "/tmp/repo-other"),
                      Agent(id: "c", vendor: .claude, title: "c", state: .working, project: "other")]
        XCTAssertEqual(ListFilter(claude: false).apply(agents).map(\.id), ["b"])
        XCTAssertEqual(ListFilter(codex: false).apply(agents).map(\.id), ["a", "c"])
        let filter = ListFilter(hiddenProjects: ["/tmp/repo/"])
        XCTAssertEqual(filter.apply(agents).map(\.id), ["b", "c"])
        XCTAssertEqual(ListFilter(hiddenProjects: ["other"]).apply(agents).map(\.id), ["a", "b"])
        let event = HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: "a", cwd: "/tmp/repo/src", tool: "Bash")
        XCTAssertTrue(filter.shouldPass(event, project: "repo", answerFromNotch: true))
        XCTAssertTrue(ListFilter(claude: false).shouldPass(event, project: "repo", answerFromNotch: true))
        var codex = event; codex.vendor = .codex
        XCTAssertTrue(ListFilter(codex: false).shouldPass(codex, project: "repo", answerFromNotch: true))
        XCTAssertFalse(ListFilter().shouldPass(event, project: "repo", answerFromNotch: true))
        XCTAssertTrue(ListFilter().shouldPass(event, project: "repo", answerFromNotch: false))
        var external = event; external.tool = "AskUserQuestion"
        XCTAssertTrue(ListFilter().shouldPass(external, project: "repo", answerFromNotch: true))
    }

    func treeModes() {
        XCTAssertTrue(SessionTreeMode.expanded.showsChildren(override: nil))
        XCTAssertFalse(SessionTreeMode.collapsed.showsChildren(override: nil))
        XCTAssertTrue(SessionTreeMode.collapsed.showsChildren(override: true))
        XCTAssertFalse(SessionTreeMode.expanded.showsChildren(override: false))
        XCTAssertFalse(SessionTreeMode.hidden.showsChildren(override: true))
        // Auto: a short or troubled family opens, a big calm one stays folded.
        func kid(_ s: AgentState) -> Agent { Agent(id: UUID().uuidString, vendor: .claude, title: "k", state: s, project: "p") }
        XCTAssertTrue(SessionTreeMode.auto.showsChildren(override: nil, kids: [kid(.working), kid(.done)]))
        XCTAssertFalse(SessionTreeMode.auto.showsChildren(override: nil, kids: [kid(.working), kid(.working), kid(.done)]))
        XCTAssertTrue(SessionTreeMode.auto.showsChildren(override: nil, kids: [kid(.working), kid(.working), kid(.error)]))
        XCTAssertTrue(SessionTreeMode.auto.showsChildren(override: true, kids: [kid(.working), kid(.working), kid(.done)]))
        XCTAssertEqual(SessionTreeMode.allCases.first, .auto)
    }

    func hiddenWorktree() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let repo = home.appendingPathComponent("repo")
        let work = home.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git/worktrees/w"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: work.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "gitdir: \(repo.path)/.git/worktrees/w\n".write(to: work.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        let filter = ListFilter(hiddenProjects: [repo.path])
        XCTAssertFalse(filter.includes(vendor: .claude, project: "repo", cwd: work.appendingPathComponent("src").path))
        let event = HookEvent(vendor: .codex, name: "PermissionRequest", sessionId: "x", cwd: work.path)
        XCTAssertTrue(filter.shouldPass(event, project: "repo", answerFromNotch: true))
    }

    func pendingVisibility() {
        var hooks = HookState()
        let a = HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: "a", cwd: "/tmp/repo")
        let b = HookEvent(vendor: .codex, name: "PermissionRequest", sessionId: "b", cwd: "/tmp/other")
        _ = hooks.receive(a, ticket: 1, now: 0)
        _ = hooks.receive(b, ticket: 2, now: 1)
        let passed = ListFilter(claude: false).requestsToPass(hooks.pending, project: { _ in "repo" }, answerFromNotch: true)
        XCTAssertEqual(passed.map(\.ticket), [1])
        for ask in passed { hooks.resolve(ask.ticket) }
        XCTAssertEqual(hooks.pending.map(\.ticket), [2])
        XCTAssertEqual(ListFilter(hiddenProjects: ["/tmp/other"]).requestsToPass(hooks.pending, project: { _ in "other" }, answerFromNotch: true).map(\.ticket), [2])
        XCTAssertEqual(ListFilter().requestsToPass(hooks.pending, project: { _ in "other" }, answerFromNotch: true), [])
    }

    func legacySort() throws {
        XCTAssertEqual(try JSONDecoder().decode(SessionSort.self, from: Data(#""newest""#.utf8)), .recent)
        XCTAssertEqual(try JSONDecoder().decode(SessionSort.self, from: Data(#""project""#.utf8)), .name)
        XCTAssertEqual(try JSONDecoder().decode(SessionSort.self, from: Data(#""vendor""#.utf8)), .attention)
    }
}
