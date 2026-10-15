import Foundation

/// User-wide Claude Code and Codex configuration folders.
struct ConfigRoots {
    let home: URL
    let environment: [String: String]

    init(home: URL, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.home = home
        self.environment = environment
    }

    func root(_ vendor: Vendor) -> URL {
        // Finder/launchd may not inherit shell variables; use the process environment without sourcing shell files.
        let key = vendor == .claude ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME"
        guard let value = environment[key], !value.isEmpty else {
            return home.appendingPathComponent(vendor == .claude ? ".claude" : ".codex")
        }
        if value == "~" { return home }
        if value.hasPrefix("~/") {
            return home.appendingPathComponent(String(value.dropFirst(2))).standardizedFileURL
        }
        return URL(fileURLWithPath: (value as NSString).expandingTildeInPath).standardizedFileURL
    }

    var claudeState: URL {
        let configured = environment["CLAUDE_CONFIG_DIR"].map { !$0.isEmpty } ?? false
        return (configured ? root(.claude) : home).appendingPathComponent(".claude.json")
    }

    func logs(_ vendor: Vendor) -> URL {
        root(vendor).appendingPathComponent(vendor == .claude ? "projects" : "sessions")
    }
}
