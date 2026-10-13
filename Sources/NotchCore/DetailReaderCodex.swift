import Foundation

extension DetailState {
    mutating func codex(_ r: Rec) {
        let p = r["payload"] as? Rec ?? [:]
        let kind = p["type"] as? String ?? ""
        if r["type"] as? String == "event_msg" {
            if kind == "agent_message", let text = p["message"] as? String { message(text) }
            if kind == "exec_command_end" {
                let code = p["exit_code"] as? Int
                result(p["call_id"] as? String, ok: code.map { $0 == 0 },
                       text: p["aggregated_output"] as? String ?? p["output"] as? String)
            }
            return
        }
        guard r["type"] as? String == "response_item" else { return }
        if kind == "message", p["role"] as? String == "assistant" {
            let text = (p["content"] as? [Rec] ?? []).filter { $0["type"] as? String == "output_text" }
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
            message(text)
        }
        if kind == "agent_message" {
            if let text = Self.text(p["content"]) { message(text) }
        }
        if kind == "function_call_output" || kind == "custom_tool_call_output" {
            let output = p["output"]
            let text = Self.text(output) ?? ""
            let obj = Self.args(text)
            let id = p["call_id"] as? String
            if let session = Self.sessionKey(obj["session_id"]), let id, let i = commandIds[id] {
                sessions[session] = i
            }
            let code = obj["exit_code"] as? Int ?? (obj["metadata"] as? Rec)?["exit_code"] as? Int
                ?? text.firstMatch(#"(?:Process exited with code|exit_code["\s:]+)\s*(-?\d+)"#).flatMap(Int.init)
                ?? text.firstMatch(#"Exit code:\s*(-?\d+)"#).flatMap(Int.init)
            let errorText = obj["output"] as? String ?? text.components(separatedBy: "Output:\n").last ?? text
            result(id, ok: code.map { $0 == 0 }, text: errorText)
            return
        }
        guard kind.hasSuffix("_call") else { return }
        let rawName = p["name"] as? String ?? (kind == "local_shell_call" ? "shell" : "")
        let name = rawName.split(separator: ".").last.map(String.init) ?? rawName
        let input = p["arguments"] ?? p["input"]
        let args = Self.args(input)
        let id = p["call_id"] as? String ?? p["id"] as? String
        fileCallId = id
        fileAt = LogText.time(r["timestamp"])
        switch name {
        case "exec":
            codeCalls(input as? String ?? "", id: id, at: r["timestamp"])
        case "write_stdin":
            if let session = Self.sessionKey(args["session_id"]), let i = sessions[session], let id { commandIds[id] = i }
        case "update_plan":
            if let plan = args["plan"] as? [Rec] {
                detail.plan = plan.compactMap {
                    guard let text = $0["step"] as? String else { return nil }
                    return PlanItem(text: text, status: PlanStatus(logValue: $0["status"] as? String))
                }
            }
        case "apply_patch":
            if let patch = args["patch"] as? String ?? args["input"] as? String ?? input as? String { self.patch(patch) }
        case "exec_command", "shell", "shell_command":
            let action = p["action"] as? Rec ?? args
            let cmd = action["cmd"] as? String ?? action["command"] as? String
                ?? (action["command"] as? [String])?.joined(separator: " ")
            command(id, cmd, r["timestamp"])
        default: break
        }
    }

    mutating func patch(_ text: String) {
        var path: String?
        var added = 0, removed = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if ["*** Update File: ", "*** Add File: ", "*** Delete File: "].contains(where: { line.hasPrefix($0) }) {
                file(path, added: added, removed: removed)
                path = line.components(separatedBy: ": ").dropFirst().joined(separator: ": ")
                added = 0; removed = 0
            } else if line == "*** End Patch" {
                file(path, added: added, removed: removed); path = nil
            } else if path != nil {
                if line.hasPrefix("+") { added += 1 }
                if line.hasPrefix("-") { removed += 1 }
            }
        }
        file(path, added: added, removed: removed)
    }
}
