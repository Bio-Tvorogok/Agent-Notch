import Foundation

struct SecurityHookChecks {
    func gitGlobals() {
        for command in ["git -C /repo reset --hard", "git -c x=y push --force", "git --git-dir=/repo/.git clean -fd",
                        "git --work-tree=/repo reset --hard", "git --no-pager push -f", "git -C '/my repo' -c x=y reset --hard",
                        "git --git-dir /repo/.git --work-tree /repo clean -fd", "git --no-optional-locks reset --hard",
                        "git --literal-pathspecs clean -fd", "git -Crepo reset --hard", "git -cx=y push --force", "git --exec-path=/tmp reset --hard",
                        "git --exec-path=/tmp push --force", "git --exec-path=/tmp clean -fd",
                        "git -c safe.directory='/my repo' reset --hard", "git -C /my\\ repo reset --hard",
                        "git --config-env=key=ENV --namespace=name push --force"] {
            let event = HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: "s", tool: "Bash", full: command)
            XCTAssertTrue(event.isRisky, command)
            XCTAssertTrue(event.needsClick, command)
        }
        // Text inside a -c value still runs: the original command is scanned too.
        for command in ["git -c alias.wipe='!rm -rf /tmp/test' wipe", #"git -c core.pager="sudo less" log"#] {
            XCTAssertTrue(HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: "s", tool: "Bash", full: command).isRisky, command)
        }
        for command in ["git -C /repo status", "git -c x=y push", "git --git-dir=/repo/.git clean -n"] {
            XCTAssertFalse(HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: "s", tool: "Bash", full: command).isRisky)
        }
    }

    /// Only the app the helper was placed by may answer: another bundle with the same layout is refused.
    func pinnedServer() throws {
        let real = "/Applications/AgentsNotch.app/Contents/MacOS/AgentsNotch"
        XCTAssertTrue(HookClient.isTrusted(real, pinned: real))
        XCTAssertFalse(HookClient.isTrusted("/tmp/Other.app/Contents/MacOS/AgentsNotch", pinned: real))
        XCTAssertFalse(HookClient.isTrusted(real, pinned: nil))
        XCTAssertFalse(HookClient.isTrusted("/tmp/notch-hook", pinned: "/tmp/notch-hook"))
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("pin-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = HookInstaller(home: home)
        let bundled = home.appendingPathComponent("bundled-hook")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: bundled)
        try installer.placeHelper(from: bundled, app: real)
        XCTAssertEqual(HookClient.pinnedApp(helper: installer.helper.path), real)
        let mode = try FileManager.default.attributesOfItem(atPath: installer.appPin.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    func exactOwnership() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("security-hooks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = HookInstaller(home: home)
        let commands = ["echo \"\(installer.helper.path)\" claude", "\"\(installer.helper.path)\" claude --custom",
                        "\"\(installer.helper.path)\" codex && echo user", "echo mentions \(installer.helper.path)"]
        for vendor in [Vendor.claude, .codex] {
            let file = installer.file(vendor)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let own = "\"\(installer.helper.path)\" \(vendor.rawValue)"
            let hooks = (commands + [own, own + " --wait"]).map { ["type": "command", "command": $0] }
            let json: [String: Any] = ["hooks": ["Stop": [["hooks": hooks]]]]
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            try installer.uninstall(vendor)
            let out = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            let groups = try XCTUnwrap((out["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
            let kept = groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }.compactMap { $0["command"] as? String }
            XCTAssertEqual(kept, commands)
            XCTAssertFalse(installer.isInstalled(vendor))
            try installer.install(vendor)
            try installer.uninstall(vendor)
            let remaining = try String(contentsOf: file, encoding: .utf8)
            for command in commands {
                XCTAssertTrue(remaining.contains(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")))
            }
        }
    }
}
