import Foundation

struct SafeUninstallChecks {
    static let tools: Result<(URL, URL, URL), Error> = Result {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("notch-safe-tools-" + UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let core = try fm.contentsOfDirectory(atPath: "Sources/NotchCore").filter { $0.hasSuffix(".swift") }
            .map { "Sources/NotchCore/" + $0 }
        try compile(["-O", "-parse-as-library", "-module-name", "NotchCore", "-emit-module",
                     "-emit-module-path", dir.appendingPathComponent("NotchCore.swiftmodule").path,
                     "-emit-library", "-static", "-o", dir.appendingPathComponent("libNotchCore.a").path] + core)
        let link = ["-O", "-I", dir.path, "-L", dir.path, "-lNotchCore"]
        let helper = dir.appendingPathComponent("notch-hook")
        try compile(link + ["-o", helper.path, "Sources/NotchHook/main.swift"])
        // Compile the actual audit writer without the AppKit store and its UI dependencies.
        let store = try String(contentsOfFile: "Sources/AgentsNotch/Store.swift", encoding: .utf8)
        let start = try XCTUnwrap(store.range(of: "enum Audit {"))
        let audit = dir.appendingPathComponent("Audit.swift")
        try ("import Foundation\nimport NotchCore\n" + store[start.lowerBound...]).write(to: audit, atomically: true, encoding: .utf8)
        let main = dir.appendingPathComponent("main.swift")
        try """
        import Foundation
        import NotchCore
        var event = HookEvent(vendor: .claude, payload: ["session_id": "audit-check", "hook_event_name": "PermissionRequest",
            "tool_name": "Bash", "tool_input": ["command": String(repeating: "x", count: Int(CommandLine.arguments[1])!)]])!
        event.detail = String(repeating: "x", count: Int(CommandLine.arguments[1])!)
        Audit.record(event, .allow)
        """.write(to: main, atomically: true, encoding: .utf8)
        let writer = dir.appendingPathComponent("audit-writer")
        try compile(link + ["-o", writer.path, audit.path, main.path])
        return (dir, helper, writer)
    }

    static func compile(_ args: [String]) throws {
        let result = try process(URL(fileURLWithPath: "/usr/bin/xcrun"), ["swiftc"] + args)
        guard result.0 == 0 else { throw NSError(domain: result.1, code: Int(result.0)) }
    }

    static func process(_ executable: URL, _ args: [String], home: URL? = nil) throws -> (Int32, String) {
        let p = Process(), output = Pipe()
        p.executableURL = executable
        p.arguments = args
        p.standardOutput = output
        p.standardError = output
        if let home {
            var env = ProcessInfo.processInfo.environment
            env["HOME"] = home.path
            env["CFFIXED_USER_HOME"] = home.path
            p.environment = env
        }
        p.standardInput = FileHandle.nullDevice
        try p.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func fixture(_ body: (URL, URL, URL) throws -> Void) throws {
        let (_, helper, writer) = try Self.tools.get()
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("notch-safe-home-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home, helper, writer)
    }

    func vendorFailures(_ flag: String) throws {
        try fixture { home, helper, _ in
            let inst = HookInstaller(home: home)
            for broken in [Vendor.claude, .codex] {
                let other: Vendor = broken == .claude ? .codex : .claude
                for v in [Vendor.claude, .codex] {
                    try FileManager.default.createDirectory(at: inst.file(v).deletingLastPathComponent(), withIntermediateDirectories: true)
                    try "{}".write(to: inst.file(v), atomically: true, encoding: .utf8)
                    if flag == "--uninstall-hooks" { try inst.install(v) }
                }
                let invalid = "{broken"
                try invalid.write(to: inst.file(broken), atomically: true, encoding: .utf8)
                let (status, message) = try Self.process(helper, [flag], home: home)
                XCTAssertEqual(status, 1)
                XCTAssertTrue(message.contains("\(broken.rawValue):"))
                XCTAssertTrue(message.contains(inst.file(broken).path))
                XCTAssertTrue(message.contains("unchanged"))
                XCTAssertEqual(try String(contentsOf: inst.file(broken), encoding: .utf8), invalid)
                XCTAssertEqual(inst.isInstalled(other), flag == "--install-hooks")
            }
        }
    }

    func jsoncIsPreserved() throws {
        try fixture { home, helper, _ in
            let inst = HookInstaller(home: home)
            let samples = ["{\n// keep my comment\n\"hooks\": {}\n}", "{\"hooks\": {},}", "{ /* keep */ \"hooks\": {} }"]
            for flag in ["--install-hooks", "--uninstall-hooks"] {
                for text in samples {
                    for v in [Vendor.claude, .codex] {
                        try FileManager.default.createDirectory(at: inst.file(v).deletingLastPathComponent(), withIntermediateDirectories: true)
                        try text.write(to: inst.file(v), atomically: true, encoding: .utf8)
                    }
                    let (status, message) = try Self.process(helper, [flag], home: home)
                    XCTAssertEqual(status, 1)
                    XCTAssertTrue(message.contains("comments") && message.contains("trailing commas"))
                    for v in [Vendor.claude, .codex] {
                        XCTAssertEqual(try String(contentsOf: inst.file(v), encoding: .utf8), text)
                        XCTAssertFalse(FileManager.default.fileExists(atPath: inst.file(v).appendingPathExtension("agents-notch-backup").path))
                    }
                }
            }
        }
    }

    func invalidRootsArePreserved() throws {
        try fixture { home, helper, _ in
            let inst = HookInstaller(home: home)
            for text in ["[]", "null", "42", "\"settings\""] {
                for v in [Vendor.claude, .codex] {
                    try FileManager.default.createDirectory(at: inst.file(v).deletingLastPathComponent(), withIntermediateDirectories: true)
                    try text.write(to: inst.file(v), atomically: true, encoding: .utf8)
                }
                let (status, message) = try Self.process(helper, ["--install-hooks"], home: home)
                XCTAssertEqual(status, 1)
                XCTAssertTrue(message.contains("object"))
                for v in [Vendor.claude, .codex] {
                    XCTAssertEqual(try String(contentsOf: inst.file(v), encoding: .utf8), text)
                }
            }
        }
    }

    func auditRotates() throws {
        try fixture { home, _, writer in
            let fm = FileManager.default
            let url = home.appendingPathComponent("Library/Application Support/AgentsNotch/decisions.jsonl")
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            for _ in 0..<7 { XCTAssertEqual(try Self.process(writer, ["600000"], home: home).0, 0) }
            for file in [url, url.appendingPathExtension("1")] {
                let data = try Data(contentsOf: file)
                XCTAssertTrue(data.count <= 1_048_576)
                XCTAssertEqual(data.last, 0x0A)
                for line in data.split(separator: 0x0A) {
                    let row = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
                    XCTAssertEqual(row?["decision"] as? String, "allow")
                }
            }
            XCTAssertFalse(fm.fileExists(atPath: url.appendingPathExtension("2").path))
            let before = try Data(contentsOf: url)
            XCTAssertEqual(try Self.process(writer, ["2000000"], home: home).0, 0)
            XCTAssertEqual(try Data(contentsOf: url), before, "an oversized row must not grow the log or discard retained rows")
        }
    }
}
