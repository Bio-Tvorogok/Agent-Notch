import Foundation

/// `codex exec --json` runs without a session file (codex-job and other scripts).
struct ExecChecks {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testReadsExecRunArguments() {
        let native = ["/opt/codex/bin/codex", "exec", "--json", "-m", "gpt-6.1-sol", "-c", "model_reasoning_effort=high",
                      "-s", "workspace-write", "-C", "/tmp/wt/usage", "-o", "/tmp/r.md"]
        let run = ExecRun.parse(pid: 7, args: native, stdout: "/tmp/jobs/a.log.jsonl", env: ["CLAUDE_CODE_SESSION_ID=6753c5ed-aaaa", "HOME=/x"])
        XCTAssertEqual(run?.cwd, "/tmp/wt/usage")
        XCTAssertEqual(run?.model, "gpt-6.1-sol")
        XCTAssertEqual(run?.effort, .high)
        XCTAssertEqual(run?.parents, ["6753c5ed-aaaa"], "started from a Claude Code session")
        // The node wrapper runs the same command; an interactive session or a terminal stdout is not an exec log.
        XCTAssertEqual(ExecRun.parse(pid: 8, args: ["node", "/usr/local/bin/codex", "exec", "--json", "--cd=/x"], stdout: "/tmp/b.jsonl")?.cwd, "/x")
        XCTAssertNil(ExecRun.parse(pid: 9, args: ["/opt/codex", "--json"], stdout: "/tmp/c.jsonl"))
        XCTAssertNil(ExecRun.parse(pid: 9, args: ["/opt/codex", "exec", "--json"], stdout: "/dev/ttys003"))
        XCTAssertNil(ExecRun.parse(pid: 9, args: ["/opt/codex", "exec", "--json"], stdout: nil))
    }

    func testShellWrapperIsStripped() {
        XCTAssertEqual(ExecLine.unwrapShell("/bin/zsh -lc 'cat README.md'"), "cat README.md")
        XCTAssertEqual(ExecLine.unwrapShell("/bin/zsh -lc \"cat > a.swift <<'EOF'\nlet x = 1\nEOF\""), "cat > a.swift <<'EOF'\nlet x = 1\nEOF")
        XCTAssertEqual(ExecLine.unwrapShell("git status"), "git status")
        XCTAssertEqual(ExecLine.unwrapShell("/bin/zsh -lc ./scripts/build.sh"), "./scripts/build.sh")
    }

    func testExecRunIsWorkingUntilItsProcessEnds() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("exec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let log = home.appendingPathComponent("job.log.jsonl")
        let lines = [
            #"{"type":"thread.started","thread_id":"t1"}"#,
            #"{"type":"turn.started"}"#,
            #"{"type":"item.started","item":{"id":"i0","type":"command_execution","command":"/bin/zsh -lc 'cat README.md'","exit_code":null,"status":"in_progress"}}"#,
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: log, atomically: true, encoding: .utf8)
        // The Claude session that started it, so the parent is known.
        let claude = home.appendingPathComponent(".claude/projects/p")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let parentLog = claude.appendingPathComponent("claude-1.jsonl")
        try (#"{"type":"user","sessionId":"claude-1","cwd":"/tmp/p","timestamp":"2027-01-15T08:00:00Z","message":{"content":"go"}}"# + "\n")
            .write(to: parentLog, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: parentLog.path)
        var running = [ExecRun(pid: 7, log: log.path, cwd: "/tmp/wt/usage", model: "gpt-6.1-sol", effort: .medium, parents: ["claude-1"])]
        let scanner = LogScanner(home: home, execRuns: { running })
        func agent(_ at: Date? = nil) -> Agent? { scanner.poll(now: at ?? now).first { $0.logPath == log.path } }

        XCTAssertEqual(agent()?.state, .working)
        XCTAssertEqual(agent()?.vendor, .codex)
        XCTAssertEqual(agent()?.title, "usage")
        XCTAssertEqual(agent()?.model, "gpt-6.1-sol")
        XCTAssertEqual(agent()?.activity, "shell · cat README.md")
        XCTAssertEqual(agent()?.parentId, "claude-1", "nests under the Claude session that started it")
        // An ephemeral run keeps no session: codex://threads/<id> fails with "no rollout found".
        XCTAssertNil(agent()?.chatId, "nothing to resume")
        let all = scanner.poll(now: now)
        let run = try XCTUnwrap(agent())
        XCTAssertEqual(JumpResolver.owner(of: run, in: all).id, "claude-1", "opens the session that started it")
        let orphan = Agent(id: "t9", vendor: .codex, title: "x", state: .working, project: "p", parentId: nil, cwd: "/tmp/p")
        XCTAssertFalse(JumpResolver.resolve(agent: orphan, home: home).contains { if case .codexApp = $0 { return true } else { return false } })
        // Without a parent it never builds a codex:// link.
        running = []
        // Processes are looked up with discovery, every 5 seconds.
        XCTAssertEqual(agent(now.addingTimeInterval(6))?.state, .done, "the process is gone")
    }
}

/// Who started whom, from the ids agents leave in their children's environment.
struct LineageChecks {
    func testPicksTheNearestKnownParent() {
        // Claude A started Codex B, which started Claude C: C carries both ids, B is the nearer one.
        let picked = Lineage.resolve(["C": ["B", "A"], "B": ["A"]], known: ["A", "B", "C"])
        XCTAssertEqual(picked["C"], "B")
        XCTAssertEqual(picked["B"], "A")
        // Order in the list does not matter.
        XCTAssertEqual(Lineage.resolve(["C": ["A", "B"], "B": ["A"]], known: ["A", "B", "C"])["C"], "B")
        // Unknown ids and the agent itself are not parents.
        XCTAssertNil(Lineage.resolve(["C": ["C", "Z"]], known: ["C"])["C"])
    }

    func testReadsBothVendorIdsFromTheEnvironment() {
        let env = ["CODEX_THREAD_ID=t-1", "CLAUDE_CODE_SESSION_ID=s-1", "PATH=/bin"]
        XCTAssertEqual(Lineage.parents(env: env), ["t-1", "s-1"])
        XCTAssertEqual(Lineage.parents(env: ["PATH=/bin"]), [])
    }
}
