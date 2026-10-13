import Foundation

/// Desktop Claude persists utilization history, not reset times or plan names.
/// The installed app maps five_hour → fh and seven_day → sd, with epoch milliseconds in t.
enum ClaudeLimits {
    private static let historyCache = FileReadCache<Rec?>()
    static func read(home: URL, now: Date) -> VendorLimits? {
        let root = home.appendingPathComponent("Library/Application Support")
        let directories = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var newest: VendorLimits?
        for directory in directories where directory.lastPathComponent == "Claude" || directory.lastPathComponent.hasPrefix("Claude-") {
            let file = directory.appendingPathComponent("plan-usage-history.json")
            let history = historyCache.read(path: file.path) {
                guard let handle = FileHandle(forReadingAtPath: file.path) else { return nil }
                defer { try? handle.close() }
                guard let data = try? handle.read(upToCount: (1 << 20) + 1), data.count <= 1 << 20 else { return nil }
                return try? JSONSerialization.jsonObject(with: data) as? Rec
            }
            guard let history,
                  let version = history["version"] as? Int, [1, 2].contains(version),
                  let samples = history["samples"] as? [Rec] else { continue }
            for sample in samples {
                guard let milliseconds = sample["t"] as? Double, milliseconds.isFinite, milliseconds > 0 else { continue }
                let updated = Date(timeIntervalSince1970: milliseconds / 1000)
                guard updated <= now, newest.map({ updated > $0.updatedAt }) ?? true else { continue }
                let usage = version == 2 ? sample["u"] as? Rec ?? [:] : sample
                let windows = [("fh", 300), ("sd", 10080)].compactMap { key, minutes -> LimitWindow? in
                    guard now.timeIntervalSince(updated) < Double(minutes * 60),
                          let percent = usage[key] as? Double, percent.isFinite, percent >= 0 else { return nil }
                    return LimitWindow(label: LimitLabels.label(minutes), usedPercent: percent)
                }
                if ["fh", "sd"].contains(where: { usage[$0] as? Double != nil }) {
                    newest = VendorLimits(vendor: .claude, windows: windows, updatedAt: updated)
                }
            }
        }
        return newest
    }
}
