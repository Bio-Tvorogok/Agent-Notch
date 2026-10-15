import CryptoKit
import Foundation

/// Reads Codex's per-handler trust records without changing them. Unknown TOML forms fall back to receipt evidence.
/// Identity: openai/codex codex-rs/hooks/src/engine/discovery.rs (normalized canonical JSON, SHA-256).
enum CodexHookTrust {
    static func read(installer: HookInstaller) -> Bool? {
        guard let text = try? String(contentsOf: installer.home.appendingPathComponent(".codex/config.toml"), encoding: .utf8),
              let body = try? Data(contentsOf: installer.file(.codex)),
              let object = try? JSONSerialization.jsonObject(with: body) as? Rec,
              let hooks = object["hooks"] as? Rec else { return nil }
        // Only the sections Codex writes are interpreted; inline tables and other spellings stay unknown.
        var records: [String: [String: String]] = [:]
        var current: String?
        var section = ""
        var multiline: String?
        for raw in text.components(separatedBy: .newlines) {
            if let delimiter = multiline {
                if raw.contains(delimiter) { multiline = nil }
                continue
            }
            var quoted = false, escaped = false
            let content = raw.prefix { character in
                if escaped { escaped = false; return true }
                if character == "\\", quoted { escaped = true; return true }
                if character == "\"" { quoted.toggle() }
                return character != "#" || quoted
            }
            let line = content.trimmingCharacters(in: .whitespaces)
            for delimiter in [String(repeating: "\"", count: 3), String(repeating: "'", count: 3)] {
                if line.components(separatedBy: delimiter).count % 2 == 0 { multiline = delimiter }
            }
            if multiline != nil, current == nil { continue }
            if line.hasPrefix("[") {
                current = nil
                guard line.hasSuffix("]") else { continue }
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                let prefix = "[hooks.state."
                if line.hasPrefix(prefix), line.hasSuffix("]") {
                    let quoted = String(line.dropFirst(prefix.count).dropLast())
                    guard let data = quoted.data(using: .utf8),
                          let key = try? JSONDecoder().decode(String.self, from: data) else { return nil }
                    current = key
                    records[key] = [:]
                }
            } else if !line.isEmpty {
                let pair = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard pair.count == 2 else {
                    if current != nil { return nil }
                    continue
                }
                if (section == "hooks" && pair[0] == "state") || (section.isEmpty && pair[0] == "hooks.state")
                    || section == "hooks.state" { return nil }
                if let key = current { records[key]?[pair[0]] = pair[1] }
            }
        }
        let labels = ["PermissionRequest": "permission_request", "PreToolUse": "pre_tool_use", "PostToolUse": "post_tool_use",
                      "UserPromptSubmit": "user_prompt_submit", "Stop": "stop", "SessionEnd": "session_end"]
        var found = false
        for (event, label) in labels {
            for (g, group) in (hooks[event] as? [Rec] ?? []).enumerated() {
                for (h, hook) in (group["hooks"] as? [Rec] ?? []).enumerated() {
                    guard let command = hook["command"] as? String,
                          command == "\"\(installer.helper.path)\" codex" else { continue }
                    found = true
                    let key = "\(installer.file(.codex).path):\(label):\(g):\(h)"
                    guard let record = records[key], record["enabled"] != "false",
                          let encoded = record["trusted_hash"], let data = encoded.data(using: .utf8),
                          let trusted = try? JSONDecoder().decode(String.self, from: data) else { return false }
                    var normalized: Rec = ["type": "command", "command": command, "async": hook["async"] as? Bool ?? false,
                                           "timeout": max(1, hook["timeout"] as? Int ?? (event == "SessionEnd" ? 1 : 600))]
                    if event == "SessionEnd" { normalized["timeout"] = min(normalized["timeout"] as? Int ?? 1, 3) }
                    if let status = hook["statusMessage"] as? String { normalized["statusMessage"] = status }
                    if ["PreToolUse", "PostToolUse", "UserPromptSubmit"].contains(event),
                       let limit = hook["additionalContextLimit"] as? Int, limit != 2500 { normalized["additionalContextLimit"] = limit }
                    var identity: Rec = ["event_name": label, "hooks": [normalized]]
                    if let matcher = group["matcher"] as? String, !matcher.isEmpty { identity["matcher"] = matcher }
                    guard let canonical = try? JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
                    let hash = "sha256:" + SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
                    if hash != trusted { return false }
                }
            }
        }
        return found ? true : nil
    }
}
