import Foundation

public enum JumpTarget: Equatable {
    case claudeApp(URL), codexApp(URL)
    case terminal(pid: Int32?, cwd: String?)
    case editor(bundleId: String, cwd: String?)
    case folder(String)
}

/// Resolves the owning session without launching anything or changing its logs.
public enum JumpResolver {
    /// The agent «Открыть» should show: a run with no chat of its own (an ephemeral `codex exec`) opens whoever started it.
    public static func owner(of agent: Agent, in agents: [Agent]) -> Agent {
        var current = agent
        var seen: Set<String> = [agent.id]
        while current.chatId == nil, let parent = current.parentId, seen.insert(parent).inserted,
              let next = agents.first(where: { $0.id == parent }) { current = next }
        return current
    }

    public static func resolve(agent: Agent, home: URL) -> [JumpTarget] {
        var id = agent.parentId ?? agent.chatId ?? agent.id
        var path = agent.logPath.map { URL(fileURLWithPath: $0) }
        if agent.parentId != nil { path = JumpLog.find(id: id, vendor: agent.vendor, home: home, near: path) }
        var meta = JumpLog.read(path, vendor: agent.vendor)
        // Codex workers can themselves have workers; open the outermost known owner.
        var seen: Set<String> = [id]
        while agent.vendor == .codex, let parent = JumpLog.parent(meta), seen.count < 32, seen.insert(parent).inserted {
            id = parent
            path = JumpLog.find(id: id, vendor: .codex, home: home, near: path)
            meta = JumpLog.read(path, vendor: .codex)
        }
        if agent.parentId == nil && seen.count == 1, let thread = meta["id"] as? String ?? meta["session_id"] as? String { id = thread }
        let live = agent.vendor == .claude ? JumpLog.live(id: id, home: home) : [:]
        let cwd = absolute(meta["cwd"] as? String) ?? absolute(live["cwd"] as? String) ?? absolute(agent.cwd)
        let pid = JumpLog.pid(live["pid"])
        let origin = live["entrypoint"] as? String ?? meta[agent.vendor == .claude ? "entrypoint" : "originator"] as? String
        var targets: [JumpTarget] = []
        if agent.vendor == .claude {
            if origin == "claude-desktop" {
                if let host = live["hostSessionId"] as? String,
                   host.range(of: "^local_[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil {
                    appendClaude(host: "code", path: "/continue", session: host, to: &targets)
                } else if UUID(uuidString: id) != nil {
                    appendClaude(host: "resume", path: "", session: id, to: &targets)
                }
            } else {
                if pid != nil { targets.append(.terminal(pid: pid, cwd: cwd)) }
                if origin == "claude-vscode" { targets.append(.editor(bundleId: "com.microsoft.VSCode", cwd: cwd)) }
                if pid == nil { targets.append(.terminal(pid: nil, cwd: cwd)) }
                if UUID(uuidString: id) != nil { appendClaude(host: "resume", path: "", session: id, to: &targets) }
            }
            appendClaude(host: "code", path: "/needs-input", session: nil, to: &targets)
        } else if origin == "Codex Desktop" {
            var parts = URLComponents()
            parts.scheme = "codex"; parts.host = "threads"
            // Encode the id as one path component, including any slash in malformed metadata.
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
            if !id.isEmpty, let escaped = id.addingPercentEncoding(withAllowedCharacters: allowed) {
                parts.percentEncodedPath = "/" + escaped
                if let url = parts.url { targets.append(.codexApp(url)) }
            }
        } else {
            if origin == "codex_vscode" { targets.append(.editor(bundleId: "com.microsoft.VSCode", cwd: cwd)) }
            targets.append(.terminal(pid: nil, cwd: cwd))
        }
        targets.append(.folder(cwd ?? home.path))
        return targets
    }

    private static func absolute(_ path: String?) -> String? {
        guard let path, path.hasPrefix("/"), !path.contains("\0") else { return nil }
        return path
    }

    private static func appendClaude(host: String, path: String, session: String?, to targets: inout [JumpTarget]) {
        var parts = URLComponents()
        parts.scheme = "claude"; parts.host = host; parts.path = path
        if let session { parts.queryItems = [URLQueryItem(name: "session", value: session)] }
        if let url = parts.url { targets.append(.claudeApp(url)) }
    }
}
