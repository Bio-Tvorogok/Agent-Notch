import Foundation

public enum SoundGroup: String, CaseIterable, Sendable { case agents, answers, interface, limits }

public enum SoundEvent: String, Codable, CaseIterable, Sendable {
    case agentAppeared, agentStarted, agentResumed, permissionRequested, questionAsked, planProposed, agentFinished, agentError
    case allowed, alwaysAllowed, denied, answerSent, planAccepted, planReturned, handedBack
    case listOpened, listClosed, cardOpened, cardClosed, cardTabChanged, agentOpened
    case settingsOpened, settingsClosed, settingsSectionChanged, settingsChanged, settingsReset, connected, disconnected, operationFailed
    case limitWarning, limitExhausted, limitRestored

    public var group: SoundGroup {
        switch self {
        case .agentAppeared, .agentStarted, .agentResumed, .permissionRequested, .questionAsked, .planProposed, .agentFinished, .agentError: .agents
        case .allowed, .alwaysAllowed, .denied, .answerSent, .planAccepted, .planReturned, .handedBack: .answers
        case .limitWarning, .limitExhausted, .limitRestored: .limits
        default: .interface
        }
    }

    public static func request(_ event: HookEvent) -> Self {
        if event.isQuestion || event.tool == "AskUserQuestion" || ["elicitation_dialog", "agent_needs_input"].contains(event.notificationType ?? "") { return .questionAsked }
        if event.isPlan || event.tool == "ExitPlanMode" { return .planProposed }
        return .permissionRequested
    }

    public static func decision(_ decision: HookDecision, for event: HookEvent) -> Self {
        switch decision {
        case .allow: .allowed
        case .allowAlways: .alwaysAllowed
        case .deny: .denied
        case .pass: .handedBack
        case .allowWith: event.isPlan ? .planAccepted : .answerSent
        case .denyWith: event.isPlan ? .planReturned : .denied
        }
    }
}

/// Empty names mute individual events. The legacy request sound is the only enabled default.
public struct SoundPrefs: Codable, Equatable, Sendable {
    public static let names = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
    private var choices: [String: String]
    public var volume: Double {
        didSet { volume = Self.clamp(volume) }
    }

    public init(legacyName: String = "Glass") {
        choices = [SoundEvent.permissionRequested.rawValue: Self.validName(legacyName)]
        volume = 1
    }

    public subscript(_ event: SoundEvent) -> String {
        get { Self.validName(choices[event.rawValue] ?? "") }
        set { choices[event.rawValue] = Self.validName(newValue) }
    }

    private enum CodingKeys: String, CodingKey { case choices, volume }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        choices = try c.decodeIfPresent([String: String].self, forKey: .choices) ?? [:]
        volume = Self.clamp(try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1)
    }
    private static func validName(_ name: String) -> String { names.contains(name) ? name : "" }
    private static func clamp(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 1 }
}

/// Polls and hooks share this watcher, so one waiting state never sounds twice.
public struct SoundAgentWatcher: Sendable {
    private var states: [String: AgentState] = [:]
    private var requests: [String: SoundEvent] = [:]
    private var requestHooks: [String: HookEvent] = [:]
    private var requestTickets: [String: Int] = [:]
    private var answered = Set<String>()
    private var initialized = false
    public init() {}

    public mutating func request(_ event: HookEvent, ticket: Int? = nil) -> SoundEvent? {
        if event.isPromptShown, answered.contains(event.agentKey) { return nil }
        let kind = SoundEvent.request(event)
        if event.waitsForAnswer {
            if let ticket, requestTickets[event.agentKey] == ticket { return nil }
            let previous = requestHooks[event.agentKey]
            let freshTicket = ticket != nil && requestTickets[event.agentKey] != ticket
            if let previous, previous.waitsForAnswer,
               freshTicket || !Self.sameTool(previous, event) {
                requests[event.agentKey] = nil
            }
            requestHooks[event.agentKey] = event
            requestTickets[event.agentKey] = ticket
        }
        guard requests[event.agentKey] == nil else { return nil }
        answered.remove(event.agentKey)
        requests[event.agentKey] = kind
        if !event.waitsForAnswer { requestHooks[event.agentKey] = event }
        return kind
    }

    /// Native answers have no pending ticket; their matching command completion ends the request.
    public mutating func finishedTool(_ event: HookEvent) {
        guard event.name == "PostToolUse", let request = requestHooks[event.agentKey],
              request.waitsForAnswer, Self.sameTool(request, event) else { return }
        resolve(event.agentKey)
    }

    private static func sameTool(_ a: HookEvent, _ b: HookEvent) -> Bool { a.tool == b.tool && a.full == b.full }

    public mutating func resolve(_ id: String) {
        if requests[id] != nil || states[id] == .waiting { answered.insert(id) }
        forgetRequest(id)
    }

    /// A new user message starts a new turn; late-log suppression belongs to the old one.
    public mutating func resume(_ id: String) {
        answered.remove(id)
        forgetRequest(id)
    }

    private mutating func forgetRequest(_ id: String) {
        requests[id] = nil
        requestHooks[id] = nil
        requestTickets[id] = nil
    }

    public mutating func update(_ agents: [Agent]) -> [SoundEvent] {
        defer { initialized = true }
        var result: [SoundEvent] = []
        for agent in agents {
            let previous = states.updateValue(agent.state, forKey: agent.id)
            if agent.state != .waiting, previous == .waiting { answered.remove(agent.id) }
            guard initialized else { continue }
            if previous == nil, agent.state.isLive { result.append(.agentAppeared) }
            guard previous != agent.state else { continue }
            switch agent.state {
            case .waiting:
                if requests[agent.id] == nil, !answered.contains(agent.id) {
                    let ask = agent.ask ?? ""
                    // Parsers and Hook word the plan ask differently in Russian.
                    let event: SoundEvent = ask == Loc.t("question", "вопрос") || ask.hasPrefix(Loc.t("question:", "вопрос:")) || ask == Loc.t("needs an answer", "нужен ответ") ? .questionAsked
                        : ask == Loc.t("approve plan", "согласовать план") || ask == Loc.t("approve plan", "принять план") ? .planProposed : .permissionRequested
                    result.append(event)
                    requests[agent.id] = event
                }
            case .working:
                if previous == .waiting || previous == .error { result.append(.agentResumed) }
                else if previous == .done { result.append(.agentStarted) }
                forgetRequest(agent.id)
            case .error:
                result.append(.agentError)
                forgetRequest(agent.id)
            case .done:
                if previous != nil { result.append(.agentFinished) }
                forgetRequest(agent.id)
            }
        }
        return result
    }

    /// Changes to visibility aren't agent events.
    public mutating func seed(_ agents: [Agent]) {
        for agent in agents { states[agent.id] = agent.state }
        initialized = true
    }
}

public struct SoundLimitWatcher: Sendable {
    private var levels: [String: Int] = [:]
    public init() {}

    public mutating func update(_ limits: [VendorLimits], threshold: Int) -> [SoundEvent] {
        var result: [SoundEvent] = []
        for vendor in limits {
            for window in vendor.windows where window.usedPercent.isFinite {
                let key = vendor.vendor.rawValue + ":" + window.label
                let level = window.usedPercent >= 100 ? 2 : window.usedPercent >= Double(threshold) ? 1 : 0
                let previous = levels.updateValue(level, forKey: key)
                guard let previous, previous != level else { continue }
                if level == 2 { result.append(.limitExhausted) }
                else if previous == 2 { result.append(.limitRestored) }
                else if level == 1 { result.append(.limitWarning) }
            }
        }
        return result
    }
}
