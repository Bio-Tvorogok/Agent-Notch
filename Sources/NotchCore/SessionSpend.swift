import Foundation

public struct SessionCost: Equatable, Sendable {
    public var tokens: Int
    /// Conditional estimate, nil when any reply came from a model without a known price.
    public var usd: Double?
    public init(tokens: Int, usd: Double?) { self.tokens = tokens; self.usd = usd }
}

/// Whole-log cost of one session. Keeps a read offset per log, so each call reads only appended bytes.
public final class SessionSpend: @unchecked Sendable {
    public static let shared = SessionSpend()
    private struct Entry { var file: SpendFile; var usedAt: Date }
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    /// Bytes parsed so far, for checks that a log is not read twice.
    public private(set) var bytesRead = 0

    public init() {}

    /// nil while a large log is still being read, or when it holds no usage yet.
    public func read(path: String, vendor: Vendor, now: Date = Date()) -> SessionCost? {
        lock.lock(); defer { lock.unlock() }
        // Logs nobody asked about for an hour are dropped; rows and the card ask every few seconds.
        entries = entries.filter { now.timeIntervalSince($0.value.usedAt) < 3600 }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? UInt64 else { entries.removeValue(forKey: path); return nil }
        let inode = attributes[.systemFileNumber] as? UInt64 ?? 0
        let modified = attributes[.modificationDate] as? Date ?? .distantPast
        var entry = entries[path] ?? Entry(file: SpendFile(inode: inode), usedAt: now)
        let state = entry.file
        if inode != state.inode || size < state.offset || (size == state.offset && modified != state.modified) {
            entry.file = SpendFile(inode: inode)
        }
        entry.file.modified = modified
        entry.usedAt = now
        var budget = 64 << 20
        while budget > 0 && entry.file.offset < size {
            let count = entry.file.read(URL(fileURLWithPath: path), vendor: vendor, day: .distantPast, end: .distantFuture, budget: budget)
            guard count > 0 else { break }
            budget -= count; bytesRead += count
        }
        // A write racing the read moves the end past `size`; keep the newer stamp so the next call does not start over.
        if let after = try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date {
            entry.file.modified = after
        }
        entries[path] = entry
        guard entry.file.offset >= size else { return nil }
        var cost = SessionCost(tokens: 0, usd: 0)
        for spent in entry.file.entries.values {
            cost.tokens += spent.tokens
            if let usd = spent.usd, let sum = cost.usd { cost.usd = sum + usd } else { cost.usd = nil }
        }
        return cost.tokens > 0 ? cost : nil
    }
}
