import Foundation
import CoreFoundation

/// Shared bounded JSONL reads keep polling independent of transcript size.
enum UsageLog {
    static let tailBytes = 4 << 20
    static func files(home: URL, vendor: Vendor) -> [URL] {
        let root = home.appendingPathComponent(vendor == .claude ? ".claude/projects" : ".codex/sessions")
        guard let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                                        options: [.skipsHiddenFiles]) else { return [] }
        return items.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }
    static func modified(_ file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
    static func records(_ data: Data) -> [Rec] {
        data.split(separator: 10).compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? Rec }
    }
    static func tail(_ path: String) -> [Rec] {
        guard let h = FileHandle(forReadingAtPath: path), let size = try? h.seekToEnd() else { return [] }
        defer { try? h.close() }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? h.seek(toOffset: start)
        guard var data = try? h.read(upToCount: tailBytes) else { return [] }
        if start > 0 {
            guard let newline = data.firstIndex(of: 10) else { return [] }
            data = Data(data.dropFirst(newline + 1))
        }
        // A writer may still be filling the last record.
        if let newline = data.lastIndex(of: 10) { data = Data(data.prefix(newline + 1)) } else { return [] }
        return records(data)
    }
    static func tokenInfo(_ record: Rec) -> Rec? {
        guard record["type"] as? String == "event_msg", let p = record["payload"] as? Rec,
              p["type"] as? String == "token_count" else { return nil }
        return p["info"] as? Rec
    }
    static func count(_ value: Any?) -> Int {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue >= 0, n.doubleValue <= 1_000_000_000_000 else { return 0 }
        return n.intValue
    }
}
