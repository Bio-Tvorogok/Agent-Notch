import Darwin
import Foundation

struct SecurityDeliveryChecks {
    func connect(_ path: String, toolID: String? = nil) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = try HookServer.address(path)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { close(fd); throw POSIXError(.ECONNREFUSED) }
        Socket.configure(fd, readTimeout: 1)
        var payload: [String: Any] = ["session_id": "delivery", "hook_event_name": "PermissionRequest", "tool_name": "Bash",
                                      "tool_input": ["command": "echo hello"]]
        payload["tool_use_id"] = toolID
        let data = try JSONSerialization.data(withJSONObject: ["vendor": "claude", "wait": true, "payload": payload])
        XCTAssertTrue(Socket.write(fd, data + [10]))
        return fd
    }

    // Uses only the pre-change API so this assertion also runs against master.
    func waitsForReceipt() throws {
        let server = HookServer(path: HookTests().socketPath())
        let ready = DispatchSemaphore(value: 0)
        let ticket = Box<Int?>(nil)
        server.onEvent = { _, t in ticket.value = t; ready.signal() }
        try server.start()
        defer { server.stop() }
        let fd = try connect(server.path)
        defer { close(fd) }
        XCTAssertTrue(ready.wait(timeout: .now() + 2) == .success)
        server.answer(try XCTUnwrap(ticket.value), .allow)
        XCTAssertTrue(Socket.readLine(fd, limit: 4096) != nil)
        // The server must keep the socket open for the hook's receipt, rather than forget the answer.
        var byte: UInt8 = 0
        XCTAssertEqual(recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT), -1, "decision socket closed before receipt")
    }
}

extension SecurityDeliveryChecks {
    func receiptAndFailure(_ mode: String) throws {
        let server = HookServer(path: HookTests().socketPath(), writeDecision: { fd, data in
            // Force a real EBADF at the write boundary; no dependence on TCP/Unix half-close timing.
            Socket.write(mode == "write-error" ? -1 : fd, data)
        })
        let ready = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
        let ticket = Box<Int?>(nil), statuses = Box<[AnswerDelivery]>([])
        server.onEvent = { _, t in ticket.value = t; ready.signal() }
        server.onDelivery = { _, s in
            statuses.value.append(s)
            if s == .delivered || s == .notDelivered { finished.signal() }
        }
        try server.start()
        defer { server.stop() }
        let fd = try connect(server.path, toolID: "tool-A")
        defer { close(fd) }
        XCTAssertTrue(ready.wait(timeout: .now() + 2) == .success)
        let t = try XCTUnwrap(ticket.value)
        server.answer(t, .deny, toolUseID: "tool-A")
        if mode != "write-error" {
            let data = try XCTUnwrap(Socket.readLine(fd, limit: 4096))
            let decision = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(decision["ticket"] as? Int, t)
            XCTAssertEqual(decision["tool_use_id"] as? String, "tool-A")
            XCTAssertEqual(statuses.value, [.sent], "a successful write is not delivery")
            if mode == "ack" || mode == "wrong-ack" || mode == "fragmented-ack" || mode == "delayed-ack" {
                if mode == "delayed-ack" { Thread.sleep(forTimeInterval: 1.3) }
                let receipt = HookReceipt.ack(ticket: t, toolUseID: mode == "wrong-ack" ? "tool-B" : "tool-A")
                XCTAssertTrue(Socket.write(fd, receipt))
                if mode == "fragmented-ack" {
                    XCTAssertTrue(finished.wait(timeout: .now() + 0.05) == .timedOut)
                }
                XCTAssertTrue(Socket.write(fd, Data([10])))
            }
        }
        XCTAssertTrue(finished.wait(timeout: .now() + (mode == "write-error" ? 0.5 : 4)) == .success)
        XCTAssertEqual(statuses.value, [.sent, ["ack", "fragmented-ack", "delayed-ack"].contains(mode) ? .delivered : .notDelivered])
    }

    func lateAndDuplicate() throws {
        let server = HookServer(path: HookTests().socketPath())
        let ready = DispatchSemaphore(value: 0), gone = DispatchSemaphore(value: 0)
        let disconnected = DispatchSemaphore(value: 0)
        let tickets = Box<[Int]>([]), statuses = Box<[(Int, AnswerDelivery)]>([])
        server.onEvent = { _, t in if let t { tickets.value.append(t) }; ready.signal() }
        server.onDelivery = { t, s in statuses.value.append((t, s)); if s == .notDelivered { gone.signal() } }
        server.onGone = { _ in disconnected.signal() }
        try server.start()
        defer { server.stop() }
        let old = try connect(server.path, toolID: "tool-A")
        XCTAssertTrue(ready.wait(timeout: .now() + 2) == .success)
        close(old)
        XCTAssertTrue(disconnected.wait(timeout: .now() + 2) == .success)
        let fd = try connect(server.path, toolID: "tool-B")
        defer { close(fd) }
        XCTAssertTrue(ready.wait(timeout: .now() + 2) == .success)
        let a = tickets.value[0], b = tickets.value[1]
        server.answer(a, .allow, toolUseID: "tool-A") // Late click: the old hook has gone.
        server.answer(b, .allow, toolUseID: "tool-A") // Wrong identity on a live ticket.
        // A queue barrier proves both answers were processed without sending any bytes to B.
        server.answer(-1, .pass)
        XCTAssertTrue(gone.wait(timeout: .now() + 2) == .success) // Late A was reported.
        XCTAssertTrue(gone.wait(timeout: .now() + 2) == .success) // Queue barrier.
        var byte: UInt8 = 0
        XCTAssertEqual(recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT), -1)
        XCTAssertFalse(statuses.value.contains { $0.0 == b && $0.1 == .sent })
        server.answer(b, .deny, toolUseID: "tool-B")
        server.answer(b, .allow, toolUseID: "tool-B") // Duplicate must not overwrite deny.
        let data = try XCTUnwrap(Socket.readLine(fd, limit: 4096))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["decision"] as? String, "deny")
        XCTAssertTrue(Socket.write(fd, HookReceipt.ack(ticket: b, toolUseID: "tool-B") + [10]))
    }

    func noClick() throws {
        let server = HookServer(path: HookTests().socketPath())
        let gone = DispatchSemaphore(value: 0)
        server.onGone = { _ in gone.signal() }
        try server.start()
        defer { server.stop() }
        let started = Date()
        let decision = HookClient.send(vendor: .claude, payload: HookTests().payload(), wait: 0.1,
                                       path: server.path, pathCheck: { _ in true })
        XCTAssertNil(decision, "timeout cannot manufacture an approval")
        XCTAssertNil(decision.flatMap { HookReply.helperStdout(event: nil, name: "PermissionRequest", decision: $0) })
        XCTAssertTrue(Date().timeIntervalSince(started) < 1, "receipt must not extend the hook wait")
        XCTAssertTrue(gone.wait(timeout: .now() + 2) == .success)
    }

    func stateAndIdentity() throws {
        var state = HookState()
        func event(_ id: String, name: String = "PermissionRequest", vendor: Vendor = .claude) throws -> HookEvent {
            try XCTUnwrap(HookEvent(vendor: vendor, payload: ["session_id": "s", "tool_use_id": id,
                "hook_event_name": name, "tool_name": "Bash", "tool_input": ["command": "echo hello"]]))
        }
        let a = try event("a")
        _ = state.receive(a, ticket: 1, now: 0)
        let pending = try XCTUnwrap(state.pending.first)
        XCTAssertNil(pending.secondsRemaining(now: 69.9))
        XCTAssertEqual(pending.secondsRemaining(now: 70), 30)
        XCTAssertEqual(pending.secondsRemaining(now: 99.5), 1)
        XCTAssertNil(pending.secondsRemaining(now: 100))
        XCTAssertTrue(state.send(pending))
        XCTAssertFalse(state.send(pending))
        XCTAssertEqual(state.pending.first?.delivery, .sent)
        state.delivery(1, .notDelivered)
        XCTAssertEqual(state.pending.first?.delivery, .notDelivered)
        XCTAssertFalse(state.send(pending))
        XCTAssertEqual(state.receive(try event("b", name: "PostToolUse"), ticket: nil, now: 2), [])
        XCTAssertEqual(state.pending.count, 1, "another identical command cannot resolve this tool call")
        XCTAssertEqual(state.receive(try event("a", name: "PostToolUse"), ticket: nil, now: 2), [1])
        _ = state.receive(a, ticket: 2, now: 3)
        let fresh = try XCTUnwrap(state.pending.first)
        state.delivery(2, .delivered) // Even the state layer rejects delivered before a send.
        XCTAssertEqual(state.pending.count, 1)
        XCTAssertTrue(state.send(fresh))
        state.delivery(2, .delivered)
        XCTAssertEqual(state.pending, [])
        _ = state.receive(a, ticket: 3, now: 4)
        XCTAssertTrue(state.send(try XCTUnwrap(state.pending.first)))
        state.delivery(3, .notDelivered)
        _ = state.receive(try event("b"), ticket: 4, now: 5)
        XCTAssertEqual(state.pending.map(\.ticket), [4], "new request moves the session on")
        XCTAssertTrue(state.send(try XCTUnwrap(state.pending.first)))
        state.delivery(4, .notDelivered)
        XCTAssertEqual(state.receive(try event("c", name: "PreToolUse"), ticket: nil, now: 6), [4], "the next tool moves on from an undelivered request")
        _ = state.receive(try event("d"), ticket: 5, now: 7)
        XCTAssertTrue(state.send(try XCTUnwrap(state.pending.first)))
        state.delivery(5, .notDelivered)
        state.resolve(5)
        XCTAssertEqual(state.pending, [])
        let codex = try XCTUnwrap(HookEvent(vendor: .codex, payload: ["session_id": "s", "hook_event_name": "PermissionRequest", "call_id": "cx"]))
        XCTAssertEqual(codex.toolUseID, "cx")
        XCTAssertEqual(a.toolUseID, "a")
        XCTAssertNil(HookEvent(vendor: .codex, payload: ["session_id": "s", "hook_event_name": "PermissionRequest"])?.toolUseID)
        Loc.forced = .en
        XCTAssertEqual(DeliveryText.notDelivered, "delivery unconfirmed")
        XCTAssertEqual(DeliveryText.openTerminal, "Open terminal")
        Loc.forced = .ru
        XCTAssertEqual(DeliveryText.notDelivered, "доставка не подтверждена")
        XCTAssertEqual(DeliveryText.openTerminal, "Открыть терминал")
    }
}
