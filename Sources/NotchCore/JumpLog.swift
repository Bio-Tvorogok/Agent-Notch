import Foundation

/// Reads only routing metadata; bounded reads keep a large transcript out of memory.
enum JumpLog {
    static func read(_ url: URL?, vendor: Vendor) -> [String: Any] {
        guard let url, let handle = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? handle.close() }
        var buffer = Data()
        var result: [String: Any] = [:]
        var total = 0
        while total < 2 << 20, let chunk = try? handle.read(upToCount: 64 << 10), !chunk.isEmpty {
            total += chunk.count
            buffer.append(chunk)
            while let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<end])
                buffer.removeSubrange(...end)
                if let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                    if vendor == .codex {
                        return record["type"] as? String == "session_meta" ? record["payload"] as? [String: Any] ?? [:] : [:]
                    }
                    for key in ["entrypoint", "cwd", "sessionId"] {
                        if let value = record[key] as? String { result[key] = value }
                    }
                    if result["entrypoint"] != nil { return result }
                }
                if vendor == .codex { return [:] }
            }
        }
        if let record = try? JSONSerialization.jsonObject(with: buffer) as? [String: Any] {
            if vendor == .codex {
                return record["type"] as? String == "session_meta" ? record["payload"] as? [String: Any] ?? [:] : [:]
            }
            return record
        }
        return result
    }

    static func find(id: String, vendor: Vendor, home: URL, near: URL?) -> URL? {
        guard !id.isEmpty, !id.contains("/"), !id.contains("\0"), id != ".", id != ".." else { return nil }
        let root = ConfigRoots(home: home).logs(vendor)
        if vendor == .claude, var directory = near?.deletingLastPathComponent() {
            while directory.path.hasPrefix(root.path + "/") {
                let candidate = directory.appendingPathComponent(id + ".jsonl")
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
                directory.deleteLastPathComponent()
            }
        }
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles]) else { return nil }
        for case let file as URL in files where file.pathExtension == "jsonl" {
            if vendor == .claude {
                if file.deletingPathExtension().lastPathComponent == id { return file }
            } else {
                let meta = read(file, vendor: .codex)
                if (meta["id"] as? String ?? meta["session_id"] as? String) == id { return file }
            }
        }
        return nil
    }

    static func live(id: String, home: URL) -> [String: Any] {
        let dir = ConfigRoots(home: home).root(.claude).appendingPathComponent("sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var matches: [[String: Any]] = []
        for file in files.sorted(by: { $0.path < $1.path }) where file.pathExtension == "json" {
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            let data = try? handle.read(upToCount: (64 << 10) + 1)
            try? handle.close()
            guard let data, data.count <= 64 << 10,
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  record["sessionId"] as? String == id else { continue }
            matches.append(record)
        }
        // Prefer a live writer when old status files for the same transcript remain.
        return matches.first(where: { pid($0["pid"]).map { ClaudeLive.isRunning($0) } ?? false }) ?? matches.first ?? [:]
    }

    static func pid(_ value: Any?) -> Int32? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let pid = Int32(number.stringValue), pid > 1 else { return nil }
        return pid
    }

    static func parent(_ meta: [String: Any]) -> String? {
        let sub = (meta["source"] as? [String: Any])?["subagent"] as? [String: Any]
        let spawn = sub?["thread_spawn"] as? [String: Any]
        return meta["parent_thread_id"] as? String ?? spawn?["parent_thread_id"] as? String
    }
}
