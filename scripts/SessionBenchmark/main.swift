import Darwin
import Foundation

// Compiled with the production scanner sources. Both modes use the same snapshots and instrumentation.
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let scanner = LogScanner(home: root, execRuns: {
    // Exercise production process inspection while keeping reads inside this fixture.
    ExecRun.running().filter { $0.log.hasPrefix(root.path + "/") }
})
var snapshots = 0
var latencies: [Double] = []
var seen: Set<String> = []
var initialCount = 0
func publish(_ agents: [Agent]?) {
    guard let agents else { return }
    snapshots += 1
    if initialCount == 0 { initialCount = agents.filter { $0.state == .working }.count }
    for agent in agents {
        guard agent.title.hasPrefix("bench:"), seen.insert(agent.title).inserted,
              let written = Double(agent.title.dropFirst(6)) else { continue }
        latencies.append((Date().timeIntervalSince1970 - written) * 1000)
    }
}
#if EVENT_SCANNER
let processes = ProcessWatcher {
    DispatchQueue.main.async { publish(scanner.poll(changes: .processes)) }
}
let watcher = FileWatcher(paths: scanner.watchPaths) { changes in
    DispatchQueue.main.async { publish(scanner.poll(changes: changes)) }
}
publish(scanner.poll(changes: .full))
let safety = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in publish(scanner.poll(changes: .full)) }
let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in publish(scanner.poll(changes: .paths([]))) }
#else
publish(scanner.poll())
let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in publish(scanner.poll()) }
#endif
print("READY \(initialCount)")
fflush(stdout)
// Sample inside the process: sandboxed runs may not inspect another process with ps.
DispatchQueue.global().async {
    while let command = readLine() {
        DispatchQueue.main.async {
            if command == "sample" {
                var usage = rusage()
                getrusage(RUSAGE_SELF, &usage)
                let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) +
                    Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
                let data = try! JSONSerialization.data(withJSONObject: ["cpu": cpu, "rss": Double(usage.ru_maxrss)])
                print(String(decoding: data, as: UTF8.self))
            } else if command == "stop" {
                let sorted = latencies.sorted()
                let maximum: Double = sorted.last ?? -1
                var result: [String: Any] = ["live_sessions": initialCount, "snapshots": snapshots,
                    "observed_appends": sorted.count,
                    "latency_p50_ms": sorted.isEmpty ? -1 : sorted[sorted.count / 2],
                    "latency_p95_ms": sorted.isEmpty ? -1 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))],
                    "latency_max_ms": maximum]
                result["visible_process_count"] = Proc.all().count
                #if EVENT_SCANNER
                result["event_stream_started"] = watcher.isWatching
                #else
                result["event_stream_started"] = NSNull()
                #endif
                let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                print(String(decoding: data, as: UTF8.self))
                fflush(stdout)
                exit(0)
            }
            fflush(stdout)
        }
    }
}
RunLoop.main.run()
