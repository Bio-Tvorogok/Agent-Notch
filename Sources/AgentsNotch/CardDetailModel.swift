import Combine
import Foundation
import NotchCore

@MainActor
final class CardDetailModel: ObservableObject {
    @Published private(set) var agent: Agent?
    @Published private(set) var detail: AgentDetail?
    @Published private(set) var loading = false
    @Published private(set) var context: ContextUsage?
    @Published private(set) var cost: SessionCost?
    /// Context and cost are read only while the card shows «Контекст и стоимость».
    var readsUsage: () -> Bool = { false }
    private let queue = DispatchQueue(label: "agents-notch.card-detail", qos: .utility)
    private var timer: Timer?
    private var generation = UUID()
    private var reading = false
    private var cache = FileReadCache<AgentDetail?>()
    private var contextCache = FileReadCache<ContextUsage?>()

    func show(_ agent: Agent) {
        close()
        self.agent = agent
        loading = true
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        generation = UUID()
        reading = false
        agent = nil
        detail = nil
        context = nil
        cost = nil
        loading = false
        cache = FileReadCache<AgentDetail?>()
        contextCache = FileReadCache<ContextUsage?>()
    }

    func update(_ agent: Agent) {
        guard let previous = self.agent, previous.id == agent.id, previous != agent else { return }
        if previous.logPath != agent.logPath || previous.vendor != agent.vendor || previous.parentId != agent.parentId {
            show(agent)
        } else { self.agent = agent }
    }

    private func refresh() {
        guard let agent, !reading else { return }
        let generation = generation, cache = cache, contextCache = contextCache, readsUsage = readsUsage()
        reading = true
        queue.async {
            let detail = agent.logPath.flatMap {
                let path = $0
                return cache.read(path: path) {
                    DetailReader.read(path: path, vendor: agent.vendor, agentId: agent.parentId == nil ? nil : agent.id)
                }
            }
            let context = readsUsage ? agent.logPath.flatMap { path in
                contextCache.read(path: path) { ContextFill.read(path: path, vendor: agent.vendor) }
            } : nil
            let cost = readsUsage ? agent.logPath.flatMap { SessionSpend.shared.read(path: $0, vendor: agent.vendor) } : nil
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.detail = detail
                if self.context != context { self.context = context }
                if self.cost != cost { self.cost = cost }
                self.loading = false
                self.reading = false
            }
        }
    }
}
