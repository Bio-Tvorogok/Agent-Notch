import Foundation
import NotchCore

@main struct DatePerformanceChecks {
    static func main() throws {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let samples = ["2026-10-14T06:24:04.123Z", "2026-10-14T06:24:05Z", "2026-10-14T06:24:06.456Z"]
        func measure(_ parse: (String) -> Double?) -> (seconds: Double, total: Double) {
            var total = 0.0
            let start = ProcessInfo.processInfo.systemUptime
            for i in 0..<20_000 { total += parse(samples[i % samples.count]) ?? 0 }
            return (ProcessInfo.processInfo.systemUptime - start, total)
        }
        let reference = measure { (fractional.date(from: $0) ?? plain.date(from: $0))?.timeIntervalSince1970 }
        guard reference.total > 0 else { print("FAIL timestamp reference did not parse"); exit(1) }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("date-performance-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".claude/projects/p/thread.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let records = (0..<20_000).map { "{\"type\":\"system\",\"timestamp\":\"\(samples[$0 % samples.count])\"}\n" }.joined()
        try records.write(to: file, atomically: false, encoding: .utf8)
        let now = Date(timeIntervalSince1970: 1_791_959_047)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
        let start = ProcessInfo.processInfo.systemUptime
        let agents = LogScanner(home: home, execRuns: { [] }).poll(now: now)!
        let seconds = ProcessInfo.processInfo.systemUptime - start
        guard agents.count == 1, agents[0].state == .working,
              abs(agents[0].startedAt - 1_791_959_044.123) < 0.000001 else { print("FAIL scanner timestamp result changed"); exit(1) }
        print(String(format: "20k timestamps: legacy formatter %.1f ms, complete JSONL scan %.1f ms", reference.seconds * 1000, seconds * 1000))
        guard seconds < reference.seconds / 3 else { print("FAIL timestamp parsing still dominates log polling"); exit(1) }
        print("OK complete timestamp-heavy scan is at least three times faster than the old date parsing alone")
    }
}
