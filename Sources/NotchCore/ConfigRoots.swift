import Darwin
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

    /// Foundation can preserve /tmp while directory enumeration and FSEvents return /private/tmp.
    /// Resolve the existing prefix with the filesystem so all scanner keys use the same spelling.
    static func physical(_ url: URL) -> URL {
        var cursor = url
        var suffix: [String] = []
        while true {
            if let path = realpath(cursor.path, nil) {
                let root = URL(fileURLWithPath: String(cString: path))
                free(path)
                return suffix.reversed().reduce(root) { $0.appendingPathComponent($1) }
            }
            if cursor.path == "/" { return url }
            suffix.append(cursor.lastPathComponent)
            cursor.deleteLastPathComponent()
        }
    }

    var claudeState: URL {
        let configured = environment["CLAUDE_CONFIG_DIR"].map { !$0.isEmpty } ?? false
        return (configured ? root(.claude) : home).appendingPathComponent(".claude.json")
    }

    func logs(_ vendor: Vendor) -> URL {
        root(vendor).appendingPathComponent(vendor == .claude ? "projects" : "sessions")
    }
}
