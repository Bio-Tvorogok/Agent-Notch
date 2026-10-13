import Foundation

public struct ProjectSpend: Equatable, Sendable {
    public var project: String
    public var tokens: Int
    /// Conditional estimate, nil when any contributing model is unknown.
    public var usd: Double?
    /// First polls may still be catching up with large logs; never present these as a full daily total.
    public var isPartial: Bool
    public init(project: String, tokens: Int, usd: Double?, isPartial: Bool = false) {
        self.project = project; self.tokens = tokens; self.usd = usd; self.isPartial = isPartial
    }
}

public enum Spend {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var cache = SpendCache()

    /// Completeness of the last poll, including when it produced no project rows.
    public static var isComplete: Bool {
        lock.lock(); defer { lock.unlock() }
        return cache.complete
    }

    /// Serialised incremental reads, at most 32 MiB per poll and 8 MiB per file.
    /// Call again while isPartial is true. Only unfinished JSONL bytes and usage totals are retained.
    public static func today(home: URL, now: Date, project: (String?) -> String, logs: [(URL, Vendor)]? = nil) -> [ProjectSpend] {
        lock.lock(); defer { lock.unlock() }
        return cache.poll(home: home, now: now, project: project, logs: logs)
    }
}
