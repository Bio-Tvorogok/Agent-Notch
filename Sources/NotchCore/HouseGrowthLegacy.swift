import Foundation
import SQLite3

/// The growth count the old WebKit house kept in its page's localStorage (`room.growth.v1`, `{project: {n, ids}}`), read once from
/// WebKit's own database when the app first runs without the page, so a house that had grown does not start over.
public enum HouseGrowthLegacy {
    public static let key = "room.growth.v1"

    /// WebKit stores a localStorage value as a UTF-16LE blob (older files: UTF-8). Nil when it is not a JSON object.
    public static func decode(_ blob: Data) -> [String: Any]? {
        for enc in [String.Encoding.utf16LittleEndian, .utf8] {
            if let s = String(data: blob, encoding: enc), let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] { return obj }
        }
        return nil
    }

    /// The saved growth of one localstorage.sqlite3 (read from a copy, so the live file, its -wal and -shm are never touched).
    public static func read(database: URL) -> [String: Any]? {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("growth-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }
        guard (try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)) != nil else { return nil }
        let copy = tmp.appendingPathComponent("db.sqlite3")
        guard (try? fm.copyItem(at: database, to: copy)) != nil else { return nil }
        for ext in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: database.path + ext)
            if fm.fileExists(atPath: side.path) { try? fm.copyItem(at: side, to: URL(fileURLWithPath: copy.path + ext)) }
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ?", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt, 0) else { return nil }
        return decode(Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))
    }

    /// Every localStorage database WebKit made for this app under `root` (~/Library/WebKit/<bundle id>).
    public static func databases(root: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { ($0 as? URL).flatMap { $0.lastPathComponent == "localstorage.sqlite3" ? $0 : nil } }
    }

    /// The saved growth of all of them, each project's larger count winning.
    public static func readAll(root: URL) -> [String: Any] {
        var best: [String: Any] = [:]
        for db in databases(root: root) {
            for (project, raw) in read(database: db) ?? [:] {
                guard let o = raw as? [String: Any], let n = (o["n"] as? NSNumber)?.intValue else { continue }
                if n > (((best[project] as? [String: Any])?["n"] as? NSNumber)?.intValue ?? -1) { best[project] = raw }
            }
        }
        return best
    }
}
