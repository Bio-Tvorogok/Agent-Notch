import Foundation

/// Cache misses too: most sessions use a normal checkout.
enum WorktreeCache {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var entries: [String: (Date, String?)] = [:]
    static func name(cwd: String, now: Date, load: () -> String?) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let entry = entries[cwd], now >= entry.0, now.timeIntervalSince(entry.0) < 60 { return entry.1 }
        entries = entries.filter { now.timeIntervalSince($0.value.0) < 60 }
        let value = load()
        entries[cwd] = (now, value)
        return value
    }
}
