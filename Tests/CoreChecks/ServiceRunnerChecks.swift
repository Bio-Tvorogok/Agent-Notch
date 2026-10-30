import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

/// The settings descriptor, the environment and approval.
extension ServiceChecks {
    func run(_ m: ServiceManifest, _ args: [String], config: Bool = false, settings: Data? = nil, timeout: Int? = nil,
             environment: [String: String]? = nil) throws -> ServiceRunner.Result {
        let command = ServiceManifest.Command(name: "x", run: ["ops/svc"] + args, label: nil, config: config, json: false,
                                              timeout: TimeInterval(timeout ?? 20), executable: m.root + "/ops/svc")
        return try ServiceRunner.run(command, of: m, settings: settings,
                                     environment: environment ?? ServiceEnvironment.make(path: "/usr/bin:/bin"))
    }

    func out(_ r: ServiceRunner.Result) -> String { String(decoding: r.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }

    func settingsDescriptor() throws {
        let m = try load(try folder(try manifest()))
        let payload = Data(#"{"TOKEN":"fd3-only-s3cret","OWNER":"1234"}"#.utf8)
        let start = try XCTUnwrap(m.command("start"))
        let read = try ServiceRunner.run(start, of: m, settings: payload, environment: ServiceEnvironment.make(path: "/usr/bin:/bin"))
        XCTAssertTrue(read.ok)
        XCTAssertEqual(read.stdout, payload, "the child reads the settings from descriptor 3")
        XCTAssertEqual(out(try run(m, ["fd3"], config: false, settings: payload)), "closed", "no descriptor 3 without config")
        XCTAssertEqual(out(try run(m, ["fd3"], config: true, settings: payload)), "open")

        // An app descriptor without close-on-exec still does not reach the child.
        let null = open("/dev/null", O_RDONLY)
        let leak = fcntl(null, F_DUPFD, 20)
        close(null)
        defer { close(leak) }
        XCTAssertEqual(fcntl(leak, F_GETFD) & FD_CLOEXEC, 0)
        XCTAssertEqual(out(try run(m, ["fd", "\(leak)"], config: true, settings: payload)), "clean")

        var env = ServiceEnvironment.make(path: "/usr/bin:/bin", from: ["HOME": home, "CLAUDECODE": "1", "ANTHROPIC_API_KEY": "sk-x", "LANG": "ru_RU.UTF-8"])
        XCTAssertEqual(Set(env.keys), ["HOME", "LANG", "PATH"])
        env["X_SEEN"] = "yes"
        let printed = out(try run(m, ["env"], config: true, settings: payload, environment: env))
        XCTAssertTrue(printed.contains("X_SEEN=yes"))
        XCTAssertTrue(!printed.contains("fd3-only-s3cret"), "settings are in neither the environment nor the arguments")
        XCTAssertEqual(out(try run(m, ["pwd"])), m.root)
        XCTAssertEqual(out(try run(m, ["stdin"])), "eof", "stdin is /dev/null")

        let failed = try run(m, ["exit", "2"])
        XCTAssertEqual(failed.status, 2)
        XCTAssertEqual(String(decoding: failed.stderr, as: UTF8.self), "said 2\n")

        let began = Date()
        let slow = try run(m, ["sleep"], timeout: 1)
        XCTAssertTrue(slow.timedOut && !slow.ok)
        XCTAssertTrue(Date().timeIntervalSince(began) < 8, "a stuck command is stopped")

        let daemonStart = Date()
        let daemon = try run(m, ["daemon"])
        XCTAssertEqual(out(daemon), "hi")
        XCTAssertTrue(Date().timeIntervalSince(daemonStart) < 5, "a background child holding stdout does not hold the app")

        XCTAssertEqual(try run(m, ["flood"]).stdout.count, ServiceRunner.outputLimit)
        do { _ = try run(m, ["read"], config: true, settings: Data(repeating: 65, count: 9000)); XCTFail("oversized settings") }
        catch { XCTAssertEqual(error as? ServiceRunner.Failure, .settingsTooLarge) }
    }

    func approval() throws {
        let root = try folder(try manifest())
        let m = try load(root)
        var entry = ServiceEntry(manifest: m)
        XCTAssertEqual(try ServiceRunner.approved(entry, home: home), m)
        try (try manifest { $0["name"] = "Changed" }).write(toFile: root + "/ops/agent-notch.json", atomically: true, encoding: .utf8)
        chmod(root + "/ops/agent-notch.json", 0o644)
        do { _ = try ServiceRunner.approved(entry, home: home); XCTFail("ran a changed manifest") }
        catch { XCTAssertEqual(error as? ServiceRunner.Failure, .notApproved) }
        entry.approved = try load(root).fingerprint
        XCTAssertEqual(try ServiceRunner.approved(entry, home: home).name, "Changed")

        // The program swapped for a link after approval.
        let outside = try folder(try manifest())
        try FileManager.default.removeItem(atPath: root + "/ops/svc")
        try FileManager.default.createSymbolicLink(atPath: root + "/ops/svc", withDestinationPath: outside + "/ops/svc")
        do { _ = try run(m, ["pwd"]); XCTFail("followed a swapped program") }
        catch { XCTAssertEqual(error as? ServiceRunner.Failure, .moved) }
    }

    func loginPath() throws {
        XCTAssertTrue(ServiceEnvironment.loginShell().hasPrefix("/"))
        // A home without dotfiles: only the system profile runs, which always puts /usr/bin on PATH.
        let path = try XCTUnwrap(ServiceEnvironment.loginPath(home: home, environment: ["HOME": home, "USER": NSUserName()]))
        XCTAssertTrue(path.split(separator: ":").contains("/usr/bin"), path)
    }
}
