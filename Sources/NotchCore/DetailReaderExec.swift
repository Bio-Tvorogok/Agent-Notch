import Foundation

extension DetailState {
    /// Exec stdout is a different format from rollout records; it has no timestamps.
    mutating func codexExec(_ r: Rec) {
        let type = r["type"] as? String
        if type == "turn.started" { execStreamError = nil; return }
        if type == "turn.failed" || type == "error" {
            if let text = Self.eventError(r) {
                if type != "turn.failed" || text != execStreamError { error(text) }
                if type == "error" { execStreamError = text }
            }
            return
        }
        guard ["item.started", "item.updated", "item.completed"].contains(type),
              let item = r["item"] as? Rec else { return }
        let id = item["id"] as? String
        let completed = type == "item.completed"
        let failed = ["failed", "declined"].contains(item["status"] as? String)
        switch item["type"] as? String {
        case "command_execution":
            if let command = item["command"] as? String { activity(id, ExecLine.unwrapShell(command), nil) }
            let code = item["exit_code"] as? Int
            result(id, ok: failed ? false : completed ? code.map { $0 == 0 } : nil,
                   text: item["aggregated_output"] as? String ?? Self.eventError(item))
        case "web_search":
            activity(id, Self.webCommand(item), nil)
            result(id, ok: failed ? false : completed ? true : nil, text: Self.eventError(item))
        case "agent_message":
            if let text = item["text"] as? String { message(text) }
        case "error":
            if completed, let text = Self.eventError(item) { error(text) }
        default: break
        }
    }

    /// Starts and completions refer to the same entry; completions also stand alone in a tail.
    mutating func activity(_ id: String?, _ text: String, _ at: Any?) {
        if let id, let i = commandIds[id], detail.commands.indices.contains(i) {
            detail.commands[i].command = text
        } else { command(id, text, at) }
    }

    static func webCommand(_ item: Rec) -> String {
        let action = item["action"] as? Rec ?? [:]
        if action["type"] as? String == "open_page" {
            return ToolText.join("web · open", action["url"] as? String)
        }
        if action["type"] as? String == "find_in_page" {
            return ToolText.join("web · find", action["pattern"] as? String)
        }
        let queries = action["queries"] as? [String]
        let query = queries?.joined(separator: ", ").nilIfEmpty
            ?? (action["query"] as? String)?.nilIfEmpty ?? (item["query"] as? String)?.nilIfEmpty
        if let query { return ToolText.join("search", query) }
        return "search"
    }

    static func eventError(_ r: Rec) -> String? {
        (r["error"] as? Rec)?["message"] as? String ?? r["error"] as? String ?? r["message"] as? String
    }
}
