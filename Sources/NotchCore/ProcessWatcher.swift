import Foundation

/// Exec stdout can live outside the config roots. Kernel fork/exec notices discover those runs
/// without a process-discovery polling timer; the 30s safety scan repairs missed registrations.
public final class ProcessWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "agents-notch.process-events", qos: .utility)
    private var sources: [Int32: DispatchSourceProcess] = [:]
    private var scheduled = false
    private var names: [Int32: String] = [:]
    private var candidates: Set<Int32> = []
    private var executed: Set<Int32> = []
    private let receive: @Sendable () -> Void

    public init(receive: @escaping @Sendable () -> Void) {
        self.receive = receive
        repair()
    }

    public func repair() {
        queue.async { [weak self] in
            self?.names.removeAll()
            _ = self?.refresh()
            self?.receive()
        }
    }

    private func refresh() -> Bool {
        // Reconcile after registering parents: a child may fork during the first enumeration.
        for _ in 0..<2 {
            let pids = Set(Proc.all())
            names = names.filter { pids.contains($0.key) }
            for pid in pids where names[pid] == nil { names[pid] = Proc.name(pid) }
            for pid in Array(sources.keys) where !pids.contains(pid) {
                sources.removeValue(forKey: pid)?.cancel()
            }
            for pid in pids where sources[pid] == nil {
                let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: [.fork, .exec, .exit], queue: queue)
                source.setEventHandler { [weak self] in
                    guard let self else { return }
                    let data = self.sources[pid]?.data ?? []
                    if data.contains(.exec) {
                        self.names.removeValue(forKey: pid)
                        self.executed.insert(pid)
                    }
                    if data.contains(.exit) {
                        self.names.removeValue(forKey: pid)
                        self.sources.removeValue(forKey: pid)?.cancel()
                    }
                    self.changed()
                }
                sources[pid] = source
                source.resume()
            }
        }
        let next = Set(names.filter { ["codex", "node"].contains($0.value) }.keys)
        let relevant = next != candidates || !executed.intersection(next.union(candidates)).isEmpty
        candidates = next
        executed.removeAll()
        return relevant
    }

    private func changed() {
        guard !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.scheduled = false
            if self.refresh() { self.receive() }
        }
    }

    deinit { for source in sources.values { source.cancel() } }
}
