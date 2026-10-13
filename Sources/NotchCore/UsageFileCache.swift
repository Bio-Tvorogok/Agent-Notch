import Foundation

/// Readers own a cache on their serial queue; unchanged files never reach the loader.
public final class FileReadCache<Value> {
    private struct Stamp: Equatable {
        let modified: Date
        let size: UInt64
        let inode: UInt64
        init?(path: String) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let modified = attributes[.modificationDate] as? Date,
                  let size = attributes[.size] as? UInt64 else { return nil }
            self.modified = modified; self.size = size
            inode = attributes[.systemFileNumber] as? UInt64 ?? 0
        }
    }
    private var entries: [String: (Stamp, Value)] = [:]
    public private(set) var readCount = 0
    public init() {}

    public func read(path: String, load: () -> Value) -> Value {
        let stamp = Stamp(path: path)
        if let stamp, let entry = entries[path], entry.0 == stamp { return entry.1 }
        readCount += 1
        let value = load()
        // A write racing the read must be picked up on the next poll.
        if let stamp, stamp == Stamp(path: path) { entries[path] = (stamp, value) }
        else { entries.removeValue(forKey: path) }
        return value
    }
    public func retain(paths: Set<String>) { entries = entries.filter { paths.contains($0.key) } }
}

public enum UsagePolling {
    public static func interval(listOpen: Bool) -> TimeInterval { listOpen ? 60 : 300 }
    public static func isDue(last: Date?, now: Date, listOpen: Bool) -> Bool {
        last.map { now.timeIntervalSince($0) >= interval(listOpen: listOpen) } ?? true
    }
}

/// Share one directory enumeration between limits and daily spend.
public enum UsageFiles {
    public static func scan(home: URL) -> [(URL, Vendor)] {
        [Vendor.claude, .codex].flatMap { vendor in UsageLog.files(home: home, vendor: vendor).map { ($0, vendor) } }
    }
}
