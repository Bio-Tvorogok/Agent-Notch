import Combine
import Foundation
import NotchCore

/// One serial reader avoids overlapping tail reads and keeps disk work off the UI thread.
@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var limits: [VendorLimits] = []
    @Published private(set) var spend: [ProjectSpend] = []
    @Published private(set) var spendComplete = false
    @Published private(set) var contexts: [String: ContextUsage] = [:]
    /// Whole-session cost per agent id, read incrementally alongside the context fill.
    @Published private(set) var costs: [String: SessionCost] = [:]
    @Published private(set) var now = Date()
    @Published var selectedVendor: Vendor?
    /// A future card can replace inline selection through this hook.
    var onSelectLimits: ((Vendor) -> Void)?

    private let home: URL
    private let queue = DispatchQueue(label: "agents-notch.usage", qos: .utility)
    private var limitsTimer: Timer?
    private var contextTimer: Timer?
    private var visible: [String: Agent] = [:]
    private var visibility: [String: () -> Bool] = [:]
    private var readingLimits = false
    private var readingContext = false
    private var lastLimitsPoll: Date?
    var listIsVisible: () -> Bool = { false }
    /// The first cost read parses a whole log, so it runs only while the row shows the cost.
    var readsCost: () -> Bool = { false }
    private let contextCache = FileReadCache<ContextUsage?>()
    private var isFixture = false

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    func start() {
        guard limitsTimer == nil else { return }
        pollLimits()
        limitsTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollLimits() }
        }
        contextTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollContexts() }
        }
        pollContexts()
    }

    func selectLimits(_ vendor: Vendor) {
        if let onSelectLimits { onSelectLimits(vendor); return }
        selectedVendor = selectedVendor == vendor ? nil : vendor
    }

    func show(_ agent: Agent, isVisible: (() -> Bool)? = nil) {
        let changed = UsageView.contextSourceChanged(previous: visible[agent.id], next: agent)
        visible[agent.id] = agent
        if let isVisible { visibility[agent.id] = isVisible }
        // Batch rows mounted by the same SwiftUI update into one read.
        if changed { DispatchQueue.main.async { [weak self] in self?.pollContexts() } }
    }
    func hide(_ id: String) {
        visible.removeValue(forKey: id); visibility.removeValue(forKey: id); contexts.removeValue(forKey: id)
        // A fixture is never polled again, so its made-up costs must survive a switch turned off and on.
        if !isFixture { costs.removeValue(forKey: id) }
    }

    func useFixture(limits: [VendorLimits], spend: [ProjectSpend], contexts: [String: ContextUsage],
                    costs: [String: SessionCost] = [:], now: Date) {
        self.limits = limits; self.spend = spend; self.contexts = contexts; self.costs = costs; self.now = now
        isFixture = true
        spendComplete = true
    }

    private func pollLimits() {
        let now = Date()
        guard !readingLimits, UsagePolling.isDue(last: lastLimitsPoll, now: now, listOpen: listIsVisible()) else { return }
        readingLimits = true
        lastLimitsPoll = now
        let home = home
        queue.async { [weak self] in
            let logs = UsageFiles.scan(home: home)
            let limits = LimitsReader.read(home: home, now: now, codexFiles: logs.filter { $0.1 == .codex }.map { $0.0 })
            let names = ProjectNames()
            let spend = Spend.today(home: home, now: now, project: names.name(for:), logs: logs)
            let complete = Spend.isComplete
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.limits = limits; self.spend = spend; self.spendComplete = complete; self.now = now
                self.readingLimits = false
            }
        }
    }

    private func pollContexts() {
        guard contextTimer != nil, !readingContext, !visible.isEmpty else { return }
        readingContext = true
        let agents = visible.values.filter { visibility[$0.id]?() ?? false }
        guard !agents.isEmpty else { readingContext = false; return }
        let cache = contextCache, readsCost = readsCost()
        queue.async { [weak self] in
            cache.retain(paths: Set(agents.compactMap(\.logPath)))
            var values: [String: ContextUsage] = [:], spent: [String: SessionCost] = [:]
            for agent in agents {
                guard let path = agent.logPath else { continue }
                if let value = cache.read(path: path, load: { ContextFill.read(path: path, vendor: agent.vendor) }) {
                    values[agent.id] = value
                }
                if readsCost, let cost = SessionSpend.shared.read(path: path, vendor: agent.vendor) { spent[agent.id] = cost }
            }
            let result = values, costs = spent
            Task { @MainActor [weak self] in
                guard let self else { return }
                for agent in agents where self.visible[agent.id]?.logPath == agent.logPath && self.visible[agent.id] != nil {
                    if self.contexts[agent.id] != result[agent.id] { self.contexts[agent.id] = result[agent.id] }
                    if self.costs[agent.id] != costs[agent.id] { self.costs[agent.id] = costs[agent.id] }
                }
                self.readingContext = false
            }
        }
    }
}
