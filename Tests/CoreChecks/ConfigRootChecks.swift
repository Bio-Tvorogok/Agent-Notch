import Foundation
import Darwin

struct ConfigRootChecks {
    private let fm = FileManager.default
    private let now = Date(timeIntervalSince1970: 1_792_065_600)

    private func fixture(_ body: (URL) throws -> Void) throws {
        let home = fm.temporaryDirectory.appendingPathComponent("notch-roots-" + UUID().uuidString)
        let keys = ["CLAUDE_CONFIG_DIR", "CODEX_HOME"]
        let saved = keys.map { ProcessInfo.processInfo.environment[$0] }
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { setenv(key, value, 1) } else { unsetenv(key) }
            }
            try? fm.removeItem(at: home)
        }
        for key in keys { unsetenv(key) }
        try body(home)
    }

    func hooks(_ vendor: Vendor) throws {
        try fixture { home in
            let key = vendor == .claude ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME"
            let name = vendor == .claude ? "settings.json" : "hooks.json"
            let fallback = vendor == .claude ? ".claude" : ".codex"
            let custom = home.appendingPathComponent("custom config/" + name)
            // Test expansion against the supplied home, never the real user's config folders.
            setenv(key, "~/custom config///", 1)
            let installer = HookInstaller(home: home)
            try installer.install(vendor)
            XCTAssertTrue(fm.fileExists(atPath: custom.path))
            XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent(fallback).path))
            XCTAssertTrue(installer.isInstalled(vendor))
            try installer.uninstall(vendor)
            XCTAssertFalse(installer.isInstalled(vendor))
            if fm.fileExists(atPath: custom.path) {
                XCTAssertFalse(try String(contentsOf: custom, encoding: .utf8).contains("notch-hook"))
            }
            unsetenv(key)
            let defaults = HookInstaller(home: home)
            try defaults.install(vendor)
            XCTAssertEqual(defaults.file(vendor).path, home.appendingPathComponent(fallback + "/" + name).path)
            XCTAssertTrue(defaults.isInstalled(vendor))
            setenv(key, "~", 1)
            let bareHome = HookInstaller(home: home)
            try bareHome.install(vendor)
            XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent(name).path))
            try bareHome.uninstall(vendor)
            setenv(key, "", 1)
            XCTAssertEqual(HookInstaller(home: home).file(vendor).path, home.appendingPathComponent(fallback + "/" + name).path)
        }
    }

    func discovery(_ vendor: Vendor) throws {
        try fixture { home in
            let key = vendor == .claude ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME"
            let fallback = vendor == .claude ? ".claude" : ".codex"
            let suffix = vendor == .claude ? "projects/p/custom.jsonl" : "sessions/2026/10/15/rollout.jsonl"
            let root = home.appendingPathComponent("custom config")
            setenv(key, root.path + "///", 1)
            let file = root.appendingPathComponent(suffix)
            let content = vendor == .claude
                ? "{\"type\":\"user\",\"sessionId\":\"custom\",\"cwd\":\"/tmp\",\"timestamp\":\"2026-10-15T12:00:00Z\",\"message\":{\"content\":\"hello\"}}\n"
                : try String(contentsOfFile: "Tests/Fixtures/codex-discovery/working.jsonl", encoding: .utf8)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: file, atomically: true, encoding: .utf8)
            try fm.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
            let id = vendor == .claude ? "custom" : "resumed"
            XCTAssertEqual(LogScanner(home: home, execRuns: { [] }).poll(now: now)?.map(\.id), [id])
            XCTAssertEqual(UsageLog.files(home: home, vendor: vendor).map { $0.resolvingSymlinksInPath().path },
                           [file.resolvingSymlinksInPath().path])
            XCTAssertEqual(JumpLog.find(id: id, vendor: vendor, home: home, near: nil)?.resolvingSymlinksInPath().path,
                           file.resolvingSymlinksInPath().path)
            XCTAssertTrue(DetailReader.read(path: file.path, vendor: vendor) != nil)
            unsetenv(key)
            XCTAssertEqual(LogScanner(home: home, execRuns: { [] }).poll(now: now)?.count, 0)
            let defaultRoot = home.appendingPathComponent(fallback)
            try fm.moveItem(at: root, to: defaultRoot)
            XCTAssertEqual(LogScanner(home: home, execRuns: { [] }).poll(now: now)?.map(\.id), [id])
        }
    }

    func claudeProjects() throws {
        try fixture { home in
            let project = home.appendingPathComponent("repo")
            let skill = project.appendingPathComponent(".claude/skills/project-skill")
            try fm.createDirectory(at: skill, withIntermediateDirectories: true)
            try "# Project skill\n".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            let root = home.appendingPathComponent("custom")
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let registry = root.appendingPathComponent(".claude.json")
            let data = try JSONSerialization.data(withJSONObject: ["projects": [project.path: [:]]])
            try data.write(to: registry)
            setenv("CLAUDE_CONFIG_DIR", "~/custom///", 1)
            XCTAssertEqual(SkillCatalog(home: home).scan().map(\.name), ["project-skill"])
            unsetenv("CLAUDE_CONFIG_DIR")
            try fm.moveItem(at: registry, to: home.appendingPathComponent(".claude.json"))
            XCTAssertEqual(SkillCatalog(home: home).scan().map(\.name), ["project-skill"])
        }
    }

    func skillsLiveAndRules() throws {
        try fixture { home in
            setenv("CLAUDE_CONFIG_DIR", "~/custom-claude/", 1)
            setenv("CODEX_HOME", "~/custom-codex/", 1)
            for dir in ["custom-claude/skills/cc", "custom-codex/skills/cx"] {
                let folder = home.appendingPathComponent(dir)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                try "# Skill\n".write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            }
            XCTAssertEqual(SkillCatalog(home: home).scan().map(\.name).sorted(), ["cc", "cx"])
            let live = home.appendingPathComponent("custom-claude/sessions/1.json")
            try fm.createDirectory(at: live.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "{\"sessionId\":\"custom\",\"status\":\"busy\",\"pid\":\(getpid())}\n".write(to: live, atomically: true, encoding: .utf8)
            XCTAssertEqual(JumpLog.live(id: "custom", home: home)["status"] as? String, "busy")
            try CodexRules.add(prefix: ["echo", "approved"], home: home)
            XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("custom-codex/rules/agents-notch.rules").path))
            XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent(".codex").path))
        }
    }
}
