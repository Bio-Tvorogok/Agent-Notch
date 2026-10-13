import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

/// Questions and plans answered from the notch: parsing, the reply JSON, the socket carrying the answer.
struct AnswerTests {
    static let questionPayload = #"""
    {"session_id":"s-q","hook_event_name":"PermissionRequest","cwd":"/tmp","tool_name":"AskUserQuestion","tool_input":{"questions":[
    {"question":"Which framework?","header":"Framework","options":[{"label":"React","description":"Component library"},{"label":"Vue","description":"Progressive"}],"multiSelect":false},
    {"question":"Which extras?","header":"Extras","options":[{"label":"Router","description":"Routing"},{"label":"Store","description":"State"}],"multiSelect":true}]}}
    """#
    static let planPayload = #"{"session_id":"s-p","hook_event_name":"PermissionRequest","tool_name":"ExitPlanMode","tool_input":{"plan":"1. Do a\n2. Do b","planFilePath":"/tmp/p.md"}}"#

    func event(_ json: String) throws -> HookEvent {
        let r = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        return try XCTUnwrap(HookEvent(vendor: .claude, payload: r))
    }

    func object(_ s: String?) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(s).utf8)) as? [String: Any])
    }

    func decisionObject(_ out: String?) throws -> [String: Any] {
        let top = try object(out)
        return try XCTUnwrap((top["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
    }

    func testParsesQuestionsAndPlan() throws {
        let q = try event(Self.questionPayload)
        XCTAssertTrue(q.isQuestion)
        XCTAssertFalse(q.isPlan)
        XCTAssertFalse(q.answeredElsewhere)
        XCTAssertEqual(q.questions.count, 2)
        XCTAssertEqual(q.questions[0].question, "Which framework?")
        XCTAssertEqual(q.questions[0].header, "Framework")
        XCTAssertEqual(q.questions[0].options.map(\.label), ["React", "Vue"])
        XCTAssertEqual(q.questions[0].options[1].description, "Progressive")
        XCTAssertFalse(q.questions[0].multiSelect)
        XCTAssertTrue(q.questions[1].multiSelect)
        XCTAssertTrue(q.needsClick)
        let p = try event(Self.planPayload)
        XCTAssertTrue(p.isPlan)
        XCTAssertEqual(p.plan, "1. Do a\n2. Do b")
        XCTAssertFalse(p.answeredElsewhere)
        // Nothing readable inside: the tool stays with the agent's own window, as before.
        let broken = try event(#"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":"?"}}"#)
        XCTAssertTrue(broken.answeredElsewhere)
        XCTAssertFalse(broken.isQuestion)
        XCTAssertTrue(try event(#"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"ExitPlanMode"}"#).answeredElsewhere)
    }

    func testAnswerReplyCarriesTheChosenAnswers() throws {
        let q = try event(Self.questionPayload)
        let d = try XCTUnwrap(HookDecision.answer(q, ["Which framework?": "React", "Which extras?": "Router, Store"]))
        let dec = try decisionObject(HookReply.stdout(event: "PermissionRequest", decision: d))
        XCTAssertEqual(dec["behavior"] as? String, "allow")
        let input = try XCTUnwrap(dec["updatedInput"] as? [String: Any])
        let answers = try XCTUnwrap(input["answers"] as? [String: String])
        XCTAssertEqual(answers["Which framework?"], "React")
        XCTAssertEqual(answers["Which extras?"], "Router, Store")
        // The original questions travel along: updatedInput replaces the whole input.
        XCTAssertEqual((input["questions"] as? [Any])?.count, 2)
        // A free-text answer with quotes and a newline stays valid JSON.
        let own = try XCTUnwrap(HookDecision.answer(q, ["Which framework?": "Свой \"вариант\"\nвторая строка"]))
        let ownInput = try XCTUnwrap(try decisionObject(HookReply.stdout(event: "PermissionRequest", decision: own))["updatedInput"] as? [String: Any])
        XCTAssertEqual((ownInput["answers"] as? [String: String])?["Which framework?"], "Свой \"вариант\"\nвторая строка")
        // Answers need a question to answer.
        XCTAssertNil(HookDecision.answer(try event(Self.planPayload), ["x": "y"]))
    }

    func testPlanAcceptAndReturnReplies() throws {
        let p = try event(Self.planPayload)
        let accept = try XCTUnwrap(HookDecision.approvePlan(p))
        let ok = try decisionObject(HookReply.stdout(event: "PermissionRequest", decision: accept))
        XCTAssertEqual(ok["behavior"] as? String, "allow")
        XCTAssertEqual((ok["updatedInput"] as? [String: Any])?["plan"] as? String, "1. Do a\n2. Do b")
        let back = HookDecision.returnPlan(feedback: "Добавьте \"тесты\"\nсначала")
        let no = try decisionObject(HookReply.stdout(event: "PermissionRequest", decision: back))
        XCTAssertEqual(no["behavior"] as? String, "deny")
        XCTAssertTrue((no["message"] as? String)?.contains("Добавьте \"тесты\"\nсначала") == true)
        XCTAssertNil(no["interrupt"])
        XCTAssertNil(HookDecision.approvePlan(try event(Self.questionPayload)))
        // The old replies are unchanged.
        XCTAssertEqual(HookReply.stdout(event: "PermissionRequest", decision: .allow), #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#)
    }

    func testSocketCarriesTheAnswerBack() throws {
        let server = HookServer(path: "/tmp/notch-\(UUID().uuidString.prefix(8)).sock")
        let got = DispatchSemaphore(value: 0)
        let tickets = Box<[Int]>([])
        server.onEvent = { e, ticket in
            if let ticket { tickets.value.append(ticket) }
            got.signal()
        }
        try server.start()
        defer { server.stop() }
        let path = server.path
        let q = try event(Self.questionPayload)
        let sent = try XCTUnwrap(HookDecision.answer(q, ["Which framework?": "Vue"]))
        let answer = Box<HookDecision?>(nil)
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            answer.value = HookClient.send(vendor: .claude, payload: Data(Self.questionPayload.utf8), wait: 3, path: path, pathCheck: { _ in true })
            done.signal()
        }
        XCTAssertTrue(got.wait(timeout: .now() + 2) == .success)
        server.answer(try XCTUnwrap(tickets.value.first), sent)
        XCTAssertTrue(done.wait(timeout: .now() + 2) == .success)
        XCTAssertEqual(answer.value, sent)
        let back = try decisionObject(HookReply.stdout(event: "PermissionRequest", decision: try XCTUnwrap(answer.value)))
        XCTAssertEqual(((back["updatedInput"] as? [String: Any])?["answers"] as? [String: String])?["Which framework?"], "Vue")

        // A returned plan travels the same way, with its comment.
        let again = Box<HookDecision?>(nil)
        let done2 = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            again.value = HookClient.send(vendor: .claude, payload: Data(Self.planPayload.utf8), wait: 3, path: path, pathCheck: { _ in true })
            done2.signal()
        }
        XCTAssertTrue(got.wait(timeout: .now() + 2) == .success)
        server.answer(try XCTUnwrap(tickets.value.last), .returnPlan(feedback: "ещё раз"))
        XCTAssertTrue(done2.wait(timeout: .now() + 2) == .success)
        XCTAssertEqual(again.value, .returnPlan(feedback: "ещё раз"))
    }
}
