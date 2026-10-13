import Foundation
import Darwin

/// The hook schema has no reviewer field. A matching turn context is the only local evidence we accept.
/// The transcript is not a stable hook interface: missing or changed records keep normal permission routing.
enum CodexApprovalContext {
    static func isAutomatic(payload: Rec) -> Bool {
        guard let session = payload["session_id"] as? String, !session.isEmpty,
              let turn = payload["turn_id"] as? String, !turn.isEmpty,
              let path = payload["transcript_path"] as? String, path.hasPrefix("/") else { return false }
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return false }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            try? handle.close()
            return false
        }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(),
              (try? handle.seek(toOffset: 0)) != nil,
              let header = try? handle.read(upToCount: 64 << 10),
              let first = header.split(separator: 10).first,
              let meta = record(Data(first)), meta["type"] as? String == "session_meta",
              let identity = meta["payload"] as? Rec, identity["id"] as? String == session else { return false }
        let budget: UInt64 = 8 << 20
        let offset = size > budget ? size - budget : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.read(upToCount: Int(size - offset)), data.last == 10 else { return false }
        var lines = data.split(separator: 10, omittingEmptySubsequences: false)
        if offset > 0 { lines = Array(lines.dropFirst()) }
        // A partial final write is not evidence. Only complete records can select the reviewer.
        lines = Array(lines.dropLast())
        var latest: Rec?
        for line in lines {
            guard let row = record(Data(line)) else { return false }
            guard row["type"] as? String == "turn_context" else { continue }
            latest = row["payload"] as? Rec
        }
        return latest?["turn_id"] as? String == turn && latest?["approvals_reviewer"] as? String == "auto_review"
    }

    private static func record(_ data: Data) -> Rec? {
        try? JSONSerialization.jsonObject(with: data) as? Rec
    }
}
