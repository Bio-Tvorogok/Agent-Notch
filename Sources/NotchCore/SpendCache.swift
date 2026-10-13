import Foundation

struct SpendEntry {
    var cwd: String?
    var tokens: Int
    var usd: Double?
    var updatedAt: Double = 0

    func isNewer(than other: Self) -> Bool {
        updatedAt > other.updatedAt || (updatedAt == other.updatedAt && tokens >= other.tokens)
    }
}

struct SpendFile {
    var offset: UInt64 = 0
    var inode: UInt64 = 0
    var modified = Date.distantPast
    var partial = Data()
    var dropping = false
    var skipped = false
    var cwd: String?
    var model: String?
    var previous = TokenAmounts()
    var entries: [String: SpendEntry] = [:]

    mutating func apply(_ record: Rec, vendor: Vendor, day: Date, end: Date, key: String) {
        let payload = record["payload"] as? Rec ?? [:]
        cwd = (vendor == .claude ? record["cwd"] : payload["cwd"]) as? String ?? cwd
        if record["type"] as? String == "turn_context" { model = payload["model"] as? String ?? model }
        let date = LogText.time(record["timestamp"]).map { Date(timeIntervalSince1970: $0) }
        let today = date.map { $0 >= day && $0 < end } ?? false
        if vendor == .claude {
            guard record["type"] as? String == "assistant", let message = record["message"] as? Rec,
                  let usage = message["usage"] as? Rec, today else { return }
            let amount = TokenAmounts.claude(usage)
            guard amount.total > 0 else { return }
            let id = message["id"] as? String ?? record["uuid"] as? String ?? key
            let entry = SpendEntry(cwd: cwd, tokens: amount.total,
                                   usd: SpendPrices.usd(amount, model: message["model"] as? String),
                                   updatedAt: date?.timeIntervalSince1970 ?? 0)
            let key = "claude:" + id
            if entries[key].map({ entry.isNewer(than: $0) }) ?? true { entries[key] = entry }
        } else {
            guard let info = UsageLog.tokenInfo(record), let usage = info["total_token_usage"] as? Rec else { return }
            let total = TokenAmounts.codex(usage)
            let baseline = total.total < previous.total ? TokenAmounts() : previous
            // Cached tokens are a subset of input, not an additional cumulative counter.
            let input = max(0, total.input + total.cached - baseline.input - baseline.cached)
            let cached = min(input, max(0, total.cached - baseline.cached))
            let delta = TokenAmounts(input: input - cached, cached: cached, output: max(0, total.output - baseline.output))
            previous = total
            guard today, delta.total > 0 else { return }
            entries[key] = SpendEntry(cwd: cwd, tokens: delta.total, usd: SpendPrices.usd(delta, model: model))
        }
    }

    mutating func read(_ file: URL, vendor: Vendor, day: Date, end: Date, budget: Int) -> Int {
        guard let handle = FileHandle(forReadingAtPath: file.path) else { return 0 }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.read(upToCount: min(budget, 8 << 20)), !data.isEmpty else { return 0 }
        let start = offset; offset += UInt64(data.count)
        let pieces = data.split(separator: 10, omittingEmptySubsequences: false)
        for (index, piece) in pieces.enumerated() {
            if !dropping {
                if partial.count + piece.count <= UsageLog.tailBytes { partial.append(contentsOf: piece) }
                else { partial.removeAll(keepingCapacity: true); dropping = true; skipped = true }
            }
            guard index < pieces.count - 1 else { break }
            if !dropping, let record = try? JSONSerialization.jsonObject(with: partial) as? Rec {
                apply(record, vendor: vendor, day: day, end: end, key: file.path + ":\(start):\(index)")
            }
            partial.removeAll(keepingCapacity: true); dropping = false
        }
        return data.count
    }
}

struct SpendCache {
    var homePath = ""
    var day = Date.distantPast
    var files: [String: SpendFile] = [:]
    var cursor = 0
    var complete = false

    mutating func poll(home: URL, now: Date, project: (String?) -> String, logs inventory: [(URL, Vendor)]? = nil) -> [ProjectSpend] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        if homePath != home.path || day != start { self = SpendCache(homePath: home.path, day: start) }
        let logs = (inventory ?? UsageFiles.scan(home: home)).filter { UsageLog.modified($0.0) >= start }
            .sorted { $0.0.path < $1.0.path }
        let paths = Set(logs.map { $0.0.path })
        files = files.filter { paths.contains($0.key) }
        var budget = 32 << 20
        var incomplete = false
        for index in logs.indices {
            let (url, vendor) = logs[(index + cursor) % logs.count]
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? UInt64 else { continue }
            let inode = attributes[.systemFileNumber] as? UInt64 ?? 0
            let modified = attributes[.modificationDate] as? Date ?? .distantPast
            var state = files[url.path] ?? SpendFile()
            if inode != state.inode || size < state.offset || (size == state.offset && modified != state.modified) {
                state = SpendFile(inode: inode)
            }
            state.modified = modified
            if budget > 0 && state.offset < size { budget -= state.read(url, vendor: vendor, day: start, end: end, budget: budget) }
            incomplete = incomplete || state.offset < size || state.skipped
            files[url.path] = state
        }
        complete = !incomplete
        cursor = logs.isEmpty ? 0 : (cursor + 1) % logs.count
        // Message IDs deduplicate Claude's repeated content blocks and copied sidechain records.
        var entries: [String: SpendEntry] = [:]
        for path in files.keys.sorted() {
            for (key, entry) in files[path]?.entries ?? [:] {
                if entries[key].map({ entry.isNewer(than: $0) }) ?? true { entries[key] = entry }
            }
        }
        var totals: [String: ProjectSpend] = [:]
        for entry in entries.values {
            let name = project(entry.cwd)
            var row = totals[name] ?? ProjectSpend(project: name, tokens: 0, usd: 0, isPartial: incomplete)
            row.tokens += entry.tokens
            if let cost = entry.usd, let subtotal = row.usd { row.usd = subtotal + cost } else { row.usd = nil }
            totals[name] = row
        }
        return totals.values.sorted { $0.project < $1.project }
    }
}
