import Foundation

struct SecurityStateChecks {
    func currentLabels() throws {
        let q = try AnswerTests().event(AnswerTests.questionPayload).questions
        func build(_ picked: [String: [String]], own: [String: String] = [:], open: Set<String> = []) -> [String: String]? {
            QuestionAnswers.build(questions: q, picked: picked, own: own, ownOpen: open)
        }
        XCTAssertNil(build(["Which framework?": ["Old label"], "Which extras?": ["Router"]]))
        XCTAssertNil(build(["Which framework?": ["React"], "Which extras?": ["Router", "Old label"]]))
        XCTAssertNil(build(["Which framework?": ["React", "Vue"], "Which extras?": ["Router"]]))
        XCTAssertNil(build(["Which framework?": ["React"], "Which extras?": ["Router"], "Old question": ["Old label"]]))
        XCTAssertEqual(build(["Which framework?": ["Vue"], "Which extras?": ["Store", "Router"]]),
                       ["Which framework?": "Vue", "Which extras?": "Router, Store"])
        XCTAssertEqual(build(["Which extras?": ["Router"]], own: ["Which framework?": " Свой ответ "], open: ["Which framework?"]),
                       ["Which framework?": "Свой ответ", "Which extras?": "Router"])
    }

    func concurrentEdit() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("security-update-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent("settings.json")
        try Data("original".utf8).write(to: file)
        var reads = 0
        try HookFileUpdate.apply(read: {
            reads += 1
            if reads == 2 { try Data("concurrent".utf8).write(to: file) }
            return try String(contentsOf: file, encoding: .utf8)
        }, merge: { $0 + "+managed" }, write: { _, next in try Data(next.utf8).write(to: file, options: .atomic) })
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "concurrent+managed")
    }

    func boundedRetries() throws {
        var reads = 0, writes = 0
        do {
            try HookFileUpdate.apply(read: { reads += 1; return "edit-\(reads)" }, merge: { $0 + "+managed" },
                                     write: { _, _ in writes += 1 })
            XCTFail("overwrote a changing file")
        } catch { }
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(reads, 4)
    }

    func serverIdentity() throws {
        for path in ["/Applications/AgentsNotch.app/Contents/MacOS/AgentsNotch", "/tmp/Other.app/Contents/MacOS/AgentsNotch"] {
            XCTAssertTrue(HookClient.isAppExecutable(path))
        }
        for path in ["/tmp/AgentsNotch", "/tmp/notch.app/AgentsNotch", "/tmp/notch.app/Contents/MacOS/notch-hook",
                     "/tmp/notch.app/Contents/Helpers/AgentsNotch", "/tmp/notch/Contents/MacOS/AgentsNotch"] {
            XCTAssertFalse(HookClient.isAppExecutable(path))
        }
        let path = "/tmp/an06-t7-id-\(UUID().uuidString.prefix(8)).sock"
        let server = HookServer(path: path)
        let received = DispatchSemaphore(value: 0)
        server.onEvent = { _, _ in received.signal() }
        try server.start()
        defer { server.stop() }
        let payload = Data(#"{"session_id":"s","hook_event_name":"Stop"}"#.utf8)
        var checked = false
        XCTAssertNil(HookClient.send(vendor: .claude, payload: payload, wait: 0, path: path, pathCheck: { executable in
            checked = !executable.isEmpty
            return false
        }))
        XCTAssertTrue(checked, "must resolve the peer executable before sending")
        XCTAssertTrue(received.wait(timeout: .now() + 0.2) == .timedOut, "untrusted server received the payload")
        XCTAssertNil(HookClient.send(vendor: .claude, payload: payload, wait: 0, path: path))
        XCTAssertTrue(received.wait(timeout: .now() + 0.2) == .timedOut, "test runner is not AgentsNotch.app")
    }
}
