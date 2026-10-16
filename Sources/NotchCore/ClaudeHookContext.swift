import Darwin
import Foundation

/// Claude's async hooks carry message text, but no turn id or event timestamp.
/// Only an unambiguous transcript match can order a Stop against a later prompt.
enum ClaudeHookContext {
    static func time(payload: Rec) -> Double? {
        let stop = payload["hook_event_name"] as? String == "Stop"
        guard stop || payload["hook_event_name"] as? String == "UserPromptSubmit",
              let text = payload[stop ? "last_assistant_message" : "prompt"] as? String, !text.isEmpty,
              let session = payload["session_id"] as? String,
              let path = payload["transcript_path"] as? String, path.hasPrefix("/") else { return nil }
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        // A tail alone cannot establish uniqueness: the same answer may occur in an older turn.
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size > 0, info.st_size <= 8 << 20,
              let data = try? handle.read(upToCount: Int(info.st_size)), data.last == 10 else { return nil }
        var matched: Double?
        for line in data.split(separator: 10) {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line)) as? Rec else { return nil }
            if let id = row["sessionId"] as? String, id != session { continue }
            guard row["type"] as? String == (stop ? "assistant" : "user"),
                  row["isSidechain"] as? Bool != true, row["isMeta"] as? Bool != true,
                  let message = row["message"] as? Rec else { continue }
            let content = message["content"]
            let body = content as? String ?? (content as? [Rec])?.compactMap { block in
                block["type"] as? String == "text" ? block["text"] as? String : nil
            }.joined(separator: "\n")
            guard body == text else { continue }
            guard matched == nil, let at = LogText.time(row["timestamp"]) else { return nil }
            matched = at
        }
        return matched
    }
}
