import Foundation
import SQLite3
#if canImport(NotchCore)
import NotchCore
#endif

struct HouseGrowthLegacyChecks {
    private func makeDB(at url: URL, value: Data?) {
        var db: OpaquePointer?
        sqlite3_open(url.path, &db)
        sqlite3_exec(db, "CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB NOT NULL ON CONFLICT FAIL)", nil, nil, nil)
        if let value {
            var st: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO ItemTable VALUES (?, ?)", -1, &st, nil)
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(st, 1, HouseGrowthLegacy.key, -1, transient)
            _ = value.withUnsafeBytes { sqlite3_bind_blob(st, 2, $0.baseAddress, Int32(value.count), transient) }
            sqlite3_step(st); sqlite3_finalize(st)
        }
        sqlite3_close(db)
    }

    /// The page's saved count, as WebKit stores it (UTF-16LE), is found under the WebKit folder and the larger count wins.
    func importsWhatThePageSaved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("growth-legacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("WebsiteData/Default/x/x/LocalStorage", isDirectory: true)
        let b = root.appendingPathComponent("WebsiteData/Default/y/y/LocalStorage", isDirectory: true)
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let json16 = { (s: String) in s.data(using: .utf16LittleEndian)! }
        makeDB(at: a.appendingPathComponent("localstorage.sqlite3"), value: json16(#"{"wedding-app":{"n":7,"ids":["a","b"]},"hexhaven":{"n":1,"ids":["c"]}}"#))
        makeDB(at: b.appendingPathComponent("localstorage.sqlite3"), value: Data(#"{"hexhaven":{"n":3,"ids":["c","d","e"]}}"#.utf8))
        let all = HouseGrowthLegacy.readAll(root: root)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(((all["wedding-app"] as? [String: Any])?["n"] as? NSNumber)?.intValue ?? -1, 7)
        XCTAssertEqual(((all["hexhaven"] as? [String: Any])?["n"] as? NSNumber)?.intValue ?? -1, 3, "the larger count wins across databases")
    }

    func missingOrEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("growth-legacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(HouseGrowthLegacy.readAll(root: root).isEmpty, "no WebKit folder: nothing")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        makeDB(at: root.appendingPathComponent("localstorage.sqlite3"), value: nil)
        XCTAssertTrue(HouseGrowthLegacy.readAll(root: root).isEmpty, "a database without the key: nothing")
        XCTAssertNil(HouseGrowthLegacy.decode(Data("not json".utf8)))
    }
}
