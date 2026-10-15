import AppKit
import NotchCore

/// Live agents read straight from the Claude Code and Codex session logs on this Mac, plus what the hooks report.
@MainActor
final class Store: ObservableObject {
    let settings: AppSettings
    init(settings: AppSettings? = nil) {
        self.settings = settings ?? .shared
        usage.readsCost = { [weak self] in self?.settings.rowPartShown(.cost) ?? false }
        usage.limitThreshold = { [weak self] in self?.settings.limits.warningPercent ?? 80 }
        usage.onSound = { [weak self] event in self?.play(event) }
    }

    @Published private(set) var agents: [Agent] = []
    @Published var selected: Agent.ID?
    @Published private(set) var hooks = HookState() {
        didSet {
            let first = hooks.pending.first?.ticket
            if first != hinted?.ticket { hinted = first.map { ($0, Date().timeIntervalSince1970) } }
        }
    }
    /// The request the hotkeys answer and since when it has been the one shown with them.
    private var hinted: (ticket: Int, since: Double)?
    /// When the list panel was last opened; nil while it is closed. Set by NotchController.
    var listShownAt: Double?
    /// Set by MenuWatcher when the frontmost app's menu reaches the wing.
    @Published var menuCramped = false
    var forceCramped = false
    /// Called when something new starts waiting for you.
    var onNewAsk: (() -> Void)?

    /// Announces agents that finish; NotchController shows its notices as a toast.
    let finisher = FinishNotifier()
    private var route = AnswerRoute()
    let usage = UsageModel()
    private let scanner = LogScanner()
    private let names = ProjectNames()
    private let queue = DispatchQueue(label: "agents-notch.scan", qos: .utility)
    private var polling = false
    private var pollCompletions: [() -> Void] = []
    private var timer: Timer?
    private var server: HookServer?
    private var fakeTicket = 1_000_000
    private var soundWatcher = SoundAgentWatcher()

    private func play(_ event: SoundEvent) { SoundPlayer.shared.play(event, settings: settings) }

    func visibilityChanged() {
        passHiddenRequests()
        soundWatcher.seed(shown)
    }

    /// Agents as drawn: the logs with open requests and on-screen prompts laid over.
    var shown: [Agent] { settings.visibleAgents(hooks.apply(to: agents, now: Date().timeIntervalSince1970, project: names.name(for:)), store: self) }
    var projects: [ProjectNode] { settings.projects(from: shown) }
    var layout: WingLayout { Wing.configuredLayout(projects, cramped: forceCramped || menuCramped, prefs: settings.wingDisplay) }
    /// The layout as it would be drawn with room to spare: the width MenuWatcher has to keep clear.
    var fullLayout: WingLayout { Wing.configuredLayout(projects, cramped: false, prefs: settings.wingDisplay) }

    func useFixture(_ fixture: [Agent], asks: [HookEvent] = []) {
        agents = fixture
        for e in asks {
            fakeTicket += 1
            _ = hooks.receive(e, ticket: fakeTicket, now: 0)
        }
    }

    func start() {
        usage.start()
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        startHooks()
    }

    /// One scan now; the callback runs on the main actor after the agents are published.
    func poll(then done: (() -> Void)? = nil) {
        if let done { pollCompletions.append(done) }
        guard !polling else { return }
        polling = true
        let scanner = scanner
        let retention = Double(settings.appearance.finishedMinutes) * 60
        queue.async {
            let next = scanner.poll(finishedRetention: retention)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.polling = false
                if let next {
                    if next.sorted(by: { $0.id < $1.id }) != self.agents.sorted(by: { $0.id < $1.id }) { self.agents = next }
                    self.finisher.check(self.settings.listFilter.apply(next))
                    for event in Set(self.soundWatcher.update(self.shown)) { self.play(event) }
                }
                let completions = self.pollCompletions
                self.pollCompletions.removeAll()
                for completion in completions { completion() }
            }
        }
    }

    // MARK: hooks

    private func startHooks() {
        let server = HookServer()
        server.onEvent = { [weak self] e, ticket in
            Task { @MainActor in self?.receive(e, ticket: ticket) }
        }
        server.onGone = { [weak self] ticket in
            Task { @MainActor in
                guard let self else { return }
                if let ask = self.hooks.pending.first(where: { $0.ticket == ticket }) { self.soundWatcher.resolve(ask.event.agentKey) }
                self.hooks.resolve(ticket)
            }
        }
        do {
            try server.start()
            self.server = server
        } catch {
            NSLog("agents-notch: hook socket failed: \(error)")
            play(.operationFailed)
        }
    }

    private func receive(_ e: HookEvent, ticket: Int?) {
        let receivedTicket = ticket
        var ticket = ticket
        let now = Date().timeIntervalSince1970
        let handedBack = ticket != nil && route.isHandedBack(e, now: now)
        // A question already sent back to the agent's window must not come back through its PermissionRequest.
        if let t = ticket, handedBack { server?.answer(t, .pass); ticket = nil }
        else if ticket != nil { route.noteRouted(e, now: now) }
        if let t = ticket, settings.listFilter.shouldPass(e, project: names.name(for: e.cwd), answerFromNotch: settings.answerFromNotch,
                                                         owner: agents.first { $0.id == e.agentKey }) {
            server?.answer(t, .pass)
            ticket = nil
        }
        let wasWaiting = hooks.pending.count
        let stale = hooks.receive(e, ticket: ticket, now: Date().timeIntervalSince1970)
        for ticket in stale { server?.answer(ticket, .pass) }
        if e.name == "UserPromptSubmit" {
            soundWatcher.resume(e.agentKey)
        } else if !stale.isEmpty || ["Stop", "SessionEnd", "SubagentStop"].contains(e.name) {
            soundWatcher.resolve(e.agentKey)
        }
        if e.name == "PostToolUse", !hooks.pending.contains(where: { $0.event.agentKey == e.agentKey }) {
            soundWatcher.finishedTool(e)
        }
        let owner = agents.first { $0.id == e.agentKey }
        let visible = owner.map { settings.listFilter.includes(vendor: $0.vendor, project: $0.project, cwd: $0.cwd) }
            ?? settings.listFilter.includes(vendor: e.vendor, project: names.name(for: e.cwd), cwd: e.cwd)
        // A fresh permission handled in the agent's window still starts a new waiting event.
        // The permission after handing back a question/plan is the same request.
        if e.isPermission, ticket == nil, !handedBack, visible {
            if let event = soundWatcher.request(e, ticket: receivedTicket) { play(event) }
        }
        // A held request always has a row; a prompt shown elsewhere only matters for agents in the list.
        if hooks.pending.count > wasWaiting
            || (e.isPromptShown && settings.listFilter.includes(vendor: e.vendor, project: names.name(for: e.cwd), cwd: e.cwd)) {
            if let event = soundWatcher.request(e, ticket: receivedTicket) { play(event) }
            onNewAsk?()
        }
    }

    func pending(for agent: Agent) -> PendingAsk? {
        hooks.pending.first { $0.event.agentKey == agent.id }
    }

    /// The human's answer from the notch. `.pass` hands the question back to the agent's own window.
    func decide(_ p: PendingAsk, _ d: HookDecision) {
        guard hooks.pending.contains(where: { $0.ticket == p.ticket }) else { return }
        server?.answer(p.ticket, d)
        hooks.resolve(p.ticket)
        soundWatcher.resolve(p.event.agentKey)
        Audit.record(p.event, d)
        play(SoundEvent.decision(d, for: p.event))
    }

    /// "Всегда": allow and keep the rule. Claude gets it in the reply; for Codex the app writes the rule file and the reply is a plain allow.
    func decideAlways(_ p: PendingAsk) {
        guard hooks.pending.contains(where: { $0.ticket == p.ticket }), !p.event.needsClick, let rule = AlwaysRule.suggest(for: p.event) else { return }
        if p.event.vendor == .codex {
            if let prefix = rule.prefix {
                do { try CodexRules.add(prefix: prefix, home: FileManager.default.homeDirectoryForCurrentUser) }
                catch { NSLog("agents-notch: codex rule failed: \(error)"); play(.operationFailed); return }
            }
            server?.answer(p.ticket, .allow)
            hooks.resolve(p.ticket)
            Audit.record(p.event, .allowAlways(rule))
            soundWatcher.resolve(p.event.agentKey)
            play(.alwaysAllowed)
        } else {
            decide(p, .allowAlways(rule))
        }
    }

    /// The chosen answers of a question, sent as the allow that carries them.
    func answer(_ p: PendingAsk, _ answers: [String: String]) {
        guard let d = HookDecision.answer(p.event, answers) else { return }
        decide(p, d)
    }

    func approvePlan(_ p: PendingAsk) {
        guard let d = HookDecision.approvePlan(p.event) else { return }
        decide(p, d)
    }

    func returnPlan(_ p: PendingAsk, feedback: String) {
        decide(p, HookDecision.returnPlan(feedback: feedback))
    }

    /// The hotkeys answer only the request the open list has shown with the hint for at least half a second,
    /// so a keypress never lands on a request that just appeared or one nobody has seen. Never allows a click-only request.
    func decideByHotkey(_ d: HookDecision) -> Bool {
        let now = Date().timeIntervalSince1970
        guard let shownAt = listShownAt, let p = hooks.pending.first, let h = hinted, h.ticket == p.ticket,
              now - max(shownAt, h.since) >= 0.5, !p.event.isQuestion, !p.event.isPlan, d != .allow || !p.event.needsClick else { return false }
        decide(p, d)
        return true
    }

    // MARK: chat

    func select(_ agent: Agent) { selected = agent.id }

    func open(_ agent: Agent) {
        play(.agentOpened)
        Opener.open(agent: JumpResolver.owner(of: agent, in: shown))
    }
}

/// Every decision made in the notch, one JSON line each, in ~/Library/Application Support/AgentsNotch/decisions.jsonl.
enum Audit {
    static func record(_ e: HookEvent, _ d: HookDecision) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AgentsNotch/decisions.jsonl")
        let row: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date()), "decision": d.name,
                                  "vendor": e.vendor.rawValue, "session": e.agentKey, "tool": e.tool ?? "", "detail": e.detail ?? "",
                                  "cwd": e.cwd ?? ""]
        guard var line = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }
}
