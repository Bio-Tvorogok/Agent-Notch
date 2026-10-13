import Foundation

extension DetailState {
    mutating func claude(_ r: Rec) {
        let blocks = (r["message"] as? Rec)?["content"] as? [Rec] ?? []
        if r["type"] as? String == "assistant" {
            let texts = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
            if !texts.isEmpty { message(texts.joined(separator: "\n")) }
        }
        for b in blocks {
            let kind = b["type"] as? String
            if kind == "tool_result" {
                let id = b["tool_use_id"] as? String
                result(id, ok: b["is_error"] as? Bool != true, text: Self.text(b["content"]))
                if let id, let task = taskCreates.removeValue(forKey: id),
                   let text = Self.text(b["content"]), let taskId = text.firstMatch(#"Task #(\d+)"#) {
                    if tasks[taskId] == nil { taskOrder.append(taskId) }
                    tasks[taskId] = task
                    if let update = pendingTaskUpdates.removeValue(forKey: taskId) { updateTask(taskId, update) }
                    detail.plan = taskOrder.compactMap { tasks[$0] }
                }
            }
            guard kind == "tool_use", let name = b["name"] as? String else { continue }
            let input = b["input"] as? Rec ?? [:]
            let id = b["id"] as? String
            fileCallId = id
            fileAt = LogText.time(r["timestamp"])
            switch name {
            case "TodoWrite":
                if let todos = input["todos"] as? [Rec] {
                    detail.plan = todos.compactMap { item in
                        guard let text = item["content"] as? String else { return nil }
                        return PlanItem(text: text, status: PlanStatus(logValue: item["status"] as? String))
                    }
                    tasks = [:]; taskOrder = []
                }
            case "TaskCreate":
                if let id, let subject = input["subject"] as? String {
                    taskCreates[id] = PlanItem(text: subject, status: .todo)
                }
            case "TaskUpdate":
                if let taskId = input["taskId"] as? String {
                    if tasks[taskId] != nil { updateTask(taskId, input) }
                    else { pendingTaskUpdates[taskId] = input }
                    detail.plan = taskOrder.compactMap { tasks[$0] }
                }
            case "Edit":
                file(input["file_path"] as? String, added: Self.lines(input["new_string"]), removed: Self.lines(input["old_string"]))
            case "MultiEdit":
                for edit in input["edits"] as? [Rec] ?? [] {
                    file(input["file_path"] as? String, added: Self.lines(edit["new_string"]), removed: Self.lines(edit["old_string"]))
                }
            case "Write":
                file(input["file_path"] as? String, added: Self.lines(input["content"]), removed: 0)
            case "NotebookEdit":
                file(input["notebook_path"] as? String, added: Self.lines(input["new_source"]), removed: 0)
            case "Bash": command(id, ToolText.full(input), r["timestamp"])
            default: break
            }
        }
    }

    mutating func updateTask(_ id: String, _ input: Rec) {
        if input["status"] as? String == "deleted" {
            tasks.removeValue(forKey: id); taskOrder.removeAll { $0 == id }; return
        }
        if let text = input["subject"] as? String { tasks[id]?.text = text }
        if let status = input["status"] as? String { tasks[id]?.status = PlanStatus(logValue: status) }
    }
}
