import Darwin
import Foundation

struct DeliveryFixChecks {
    // Run the real helper against a trusted app-shaped peer, with stdout either usable or broken.
    func helperStdout(_ mode: String) throws {
        let (dir, helper, _) = try SafeUninstallChecks.tools.get()
        let root = URL(fileURLWithPath: "/tmp/an06-t7-nd-" + UUID().uuidString.prefix(8))
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Test.app/Contents/MacOS/AgentsNotch")
        try FileManager.default.createDirectory(at: app.deletingLastPathComponent(), withIntermediateDirectories: true)
        let main = root.appendingPathComponent("main.swift")
        try """
        import Foundation
        import NotchCore
        let server = HookServer()
        let done = DispatchSemaphore(value: 0)
        server.onEvent = { event, ticket in
            let decision: HookDecision = \(mode == "large" ? ".allowWith(input: \"{\\\"answer\\\":\\\"\" + String(repeating: \"x\", count: 200000) + \"\\\"}\")" : ".allow")
            if let ticket { server.answer(ticket, decision, toolUseID: event.toolUseID) }
        }
        server.onDelivery = { _, status in
            if status == .delivered || status == .notDelivered {
                print(status.rawValue)
                fflush(stdout)
                done.signal()
            }
        }
        try server.start()
        print("ready")
        fflush(stdout)
        if done.wait(timeout: .now() + 6) != .success { exit(2) }
        server.stop()
        """.write(to: main, atomically: true, encoding: .utf8)
        try SafeUninstallChecks.compile(["-O", "-I", dir.path, "-L", dir.path, "-lNotchCore", "-o", app.path, main.path])
        let installer = HookInstaller(home: root)
        try installer.placeHelper(from: helper, app: app.path)
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = root.path
        env["CFFIXED_USER_HOME"] = root.path
        let peer = Process(), peerOutput = Pipe()
        peer.executableURL = app
        peer.environment = env
        peer.standardOutput = peerOutput
        try peer.run()
        defer { if peer.isRunning { peer.terminate(); peer.waitUntilExit() } }
        var ready = Data()
        while ready.last != 10 {
            let byte = peerOutput.fileHandleForReading.readData(ofLength: 1)
            guard !byte.isEmpty else { XCTFail("peer exited before listening"); throw Unwrap() }
            ready.append(byte)
        }
        XCTAssertEqual(String(decoding: ready, as: UTF8.self), "ready\n")
        let hook = Process(), input = Pipe(), output = Pipe()
        hook.executableURL = installer.helper
        hook.arguments = ["claude", "--wait"]
        hook.environment = env
        hook.standardInput = input
        hook.standardOutput = output
        if mode == "broken" { try output.fileHandleForReading.close() }
        if mode == "full" {
            let fd = output.fileHandleForWriting.fileDescriptor
            let flags = fcntl(fd, F_GETFL)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
            let bytes = [UInt8](repeating: 120, count: 4096)
            while Darwin.write(fd, bytes, bytes.count) > 0 {}
            _ = fcntl(fd, F_SETFL, flags)
        }
        let exited = DispatchSemaphore(value: 0)
        hook.terminationHandler = { _ in exited.signal() }
        try hook.run()
        try input.fileHandleForWriting.write(contentsOf: HookTests().payload())
        try input.fileHandleForWriting.close()
        let started = Date()
        if mode == "full", exited.wait(timeout: .now() + 2) != .success {
            XCTFail("a full stdout pipe blocked the helper")
            hook.terminate()
        }
        let succeeds = mode == "success" || mode == "large"
        let text = succeeds ? output.fileHandleForReading.readDataToEndOfFile() : Data()
        hook.waitUntilExit()
        XCTAssertEqual(hook.terminationStatus, 0, "hook events always exit zero")
        XCTAssertTrue(Date().timeIntervalSince(started) < 2, "stdout must not extend the hook wait")
        if succeeds {
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: text) as? [String: Any])
            let reply = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
            let decision = try XCTUnwrap(reply["decision"] as? [String: Any])
            XCTAssertEqual(decision["behavior"] as? String, "allow")
            if mode == "large" {
                XCTAssertEqual(((decision["updatedInput"] as? [String: Any])?["answer"] as? String)?.count, 200000)
            }
        }
        let result = peerOutput.fileHandleForReading.readDataToEndOfFile()
        peer.waitUntilExit()
        XCTAssertEqual(peer.terminationStatus, 0)
        XCTAssertEqual(String(decoding: result, as: UTF8.self), succeeds ? "delivered\n" : "notDelivered\n",
                       "a receipt requires successful stdout delivery")
    }

    func oversizedIdentity() throws {
        let server = HookServer(path: HookTests().socketPath())
        let events = Box<[Int?]>([])
        server.onEvent = { _, ticket in events.value.append(ticket) }
        try server.start()
        defer { server.stop() }
        for id in [String(repeating: "x", count: 5000), String(repeating: "\u{01}", count: 1000)] {
            let fd = try SecurityDeliveryChecks().connect(server.path, toolID: id)
            defer { close(fd) }
            var byte: UInt8 = 0
            XCTAssertEqual(recv(fd, &byte, 1, 0), 0, "oversized identity must fall back without a notch ticket")
        }
        XCTAssertEqual(events.value.count, 0, "no UI may promise delivery for an oversized receipt")
        XCTAssertTrue(HookReceipt.ack(ticket: Int.max, toolUseID: String(repeating: "\u{01}", count: 512)).count + 1 < 4096)
    }

    func unsentDisconnect() throws {
        let server = HookServer(path: HookTests().socketPath())
        let ready = DispatchSemaphore(value: 0), gone = DispatchSemaphore(value: 0)
        let statuses = Box<[AnswerDelivery]>([])
        server.onEvent = { _, _ in ready.signal() }
        server.onDelivery = { _, status in statuses.value.append(status) }
        server.onGone = { _ in gone.signal() }
        try server.start()
        defer { server.stop() }
        let fd = try SecurityDeliveryChecks().connect(server.path)
        XCTAssertTrue(ready.wait(timeout: .now() + 2) == .success)
        close(fd)
        XCTAssertTrue(gone.wait(timeout: .now() + 2) == .success)
        XCTAssertEqual(statuses.value, [], "Esc without an answer must not report a delivery failure or play its sound")
        var state = HookState()
        _ = state.receive(try DeliveryIdentityRegressionChecks().event("a", "PermissionRequest"), ticket: 1, now: 0)
        state.delivery(1, .notDelivered)
        XCTAssertEqual(state.pending, [], "unsent requests clear silently even on a late failure callback")
    }

    func unconfirmedExpiry() throws {
        let event = try DeliveryIdentityRegressionChecks().event("a", "PermissionRequest")
        var state = HookState()
        _ = state.receive(event, ticket: 1, now: 0)
        XCTAssertTrue(state.send(try XCTUnwrap(state.pending.first)))
        state.delivery(1, .notDelivered)
        let agent = Agent(id: "s", vendor: .claude, title: "session", state: .working, project: "test")
        XCTAssertEqual(state.apply(to: [], now: 1, project: { _ in "test" }), [], "a missing agent must not leave a synthetic red row")
        XCTAssertEqual(state.apply(to: [agent], now: 599, project: { _ in "test" }).first?.state, .error)
        XCTAssertEqual(state.apply(to: [agent], now: 600, project: { _ in "test" }).first?.state, .working,
                       "unconfirmed delivery expires after ten minutes")
        var missing = state
        XCTAssertEqual(missing.expire(agents: [], now: 1), [1])
        XCTAssertEqual(missing.pending, [])
        XCTAssertEqual(state.expire(agents: [agent], now: 599), [])
        XCTAssertEqual(state.expire(agents: [agent], now: 600), [1])
        XCTAssertEqual(state.pending, [])
    }
}
