import Darwin
import Foundation

/// Claude's async hooks carry message text, but no turn id or event timestamp.
/// The newest matching row in a bounded tail orders a Stop against a later prompt.
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
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size > 0 else { return nil }
        let count = min(Int(info.st_size), 256 << 10)
        let offset = UInt64(info.st_size) - UInt64(count)
        do { try handle.seek(toOffset: offset) } catch { return nil }
        guard let data = try? handle.read(upToCount: count) else { return nil }
        let lines = data.split(separator: 10, omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated().reversed() {
            // The first slice may start inside a row; a partial final row simply fails JSON parsing.
            if offset > 0 && index == 0 { continue }
            guard let row = try? JSONSerialization.jsonObject(with: Data(line)) as? Rec else { continue }
            if let id = row["sessionId"] as? String, id != session { continue }
            guard row["type"] as? String == (stop ? "assistant" : "user"),
                  row["isSidechain"] as? Bool != true, row["isMeta"] as? Bool != true,
                  let message = row["message"] as? Rec else { continue }
            let content = message["content"]
            let body = content as? String ?? (content as? [Rec])?.compactMap { block in
                block["type"] as? String == "text" ? block["text"] as? String : nil
            }.joined(separator: "\n")
            guard body == text else { continue }
            return LogText.time(row["timestamp"])
        }
        return nil
    }
}
