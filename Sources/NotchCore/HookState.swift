import Foundation

public enum AnswerDelivery: String, Sendable, Equatable {
    case waiting, sent, delivered, notDelivered
}

/// A permission request, retained until receipt or dismissal.
public struct PendingAsk: Identifiable, Equatable, Sendable {
    public let ticket: Int
    public let event: HookEvent
    public let at: Double
    public var delivery: AnswerDelivery = .waiting
    public var id: Int { ticket }
    public var toolUseID: String? { event.toolUseID }

    /// Only the last 30 seconds of the existing 100-second hook wait are shown.
    public func secondsRemaining(now: Double) -> Int? {
        let left = at + Double(HookInstaller.wait) - now
        guard delivery == .waiting, left > 0, left <= 30 else { return nil }
        return Int(ceil(left))
    }
}

/// What the hooks have said on top of the logs: open permission requests and prompts on screen in the agent's own window.
public struct HookState: Sendable, Equatable {
    public private(set) var pending: [PendingAsk] = []
    /// Agent key → what its own window asks right now, and since when.
    private(set) var shown: [String: Shown] = [:]

    struct Shown: Sendable, Equatable {
        var text: String
        var at: Double
    }

    public init() {}

    /// Takes one event. Returns the tickets that went stale: the agent moved on without our answer, so they get `.pass`.
    public mutating func receive(_ e: HookEvent, ticket: Int?, now: Double) -> [Int] {
        if let ticket {
            let stale = pending.filter { $0.event.agentKey == e.agentKey && $0.delivery == .notDelivered }
            pending.removeAll { p in stale.contains { $0.ticket == p.ticket } }
            pending.append(PendingAsk(ticket: ticket, event: e, at: now))
            return stale.map(\.ticket)
        }
        if e.isPromptShown {
            shown[e.agentKey] = Shown(text: LogText.clip(e.message, 60) ?? Loc.t("approval", "подтверждение"), at: now)
            return []
        }
        shown[e.agentKey] = nil
        let ended = ["Stop", "UserPromptSubmit", "SessionEnd", "SubagentStop"].contains(e.name)
        let stale = pending.filter { p in
            if e.name == "SessionEnd", p.event.sessionId == e.sessionId { return true }
            guard p.event.agentKey == e.agentKey else { return false }
            let nextTool = p.delivery == .notDelivered && e.name == "PreToolUse"
                && (e.toolUseID == nil || e.toolUseID != p.toolUseID)
            let sameTool = p.toolUseID != nil || e.toolUseID != nil
                ? p.toolUseID != nil && p.toolUseID == e.toolUseID
                : p.event.tool == e.tool && p.event.detail == e.detail
            return ended || nextTool || (e.name == "PostToolUse" && sameTool)
        }
        if e.name == "SessionEnd" { shown = shown.filter { !$0.key.hasPrefix(e.sessionId) } }
        pending.removeAll { p in stale.contains { $0.ticket == p.ticket } }
        return stale.map(\.ticket)
    }

    /// Rejects a stale UI value or a duplicate click before it can reach the socket.
    @discardableResult
    public mutating func send(_ ask: PendingAsk) -> Bool {
        guard let i = pending.firstIndex(where: { $0.ticket == ask.ticket && $0.toolUseID == ask.toolUseID }),
              pending[i].delivery == .waiting else { return false }
        pending[i].delivery = .sent
        return true
    }

    public mutating func delivery(_ ticket: Int, _ status: AnswerDelivery) {
        guard let i = pending.firstIndex(where: { $0.ticket == ticket }) else { return }
        if status == .delivered {
            guard pending[i].delivery == .sent else { return }
            pending.remove(at: i)
        } else if status == .notDelivered || (status == .sent && pending[i].delivery == .waiting) {
            pending[i].delivery = status
        }
    }

    public mutating func resolve(_ ticket: Int) {
        pending.removeAll { $0.ticket == ticket }
    }

    /// The agents with hook knowledge laid over: open requests and shown prompts make them wait.
    /// A request from a session the logs do not show yet becomes its own row.
    public func apply(to agents: [Agent], now: Double, project: (String?) -> String) -> [Agent] {
        var out = agents.map { a -> Agent in
            var a = a
            if let p = pending.first(where: { $0.event.agentKey == a.id }) {
                a.state = p.delivery == .notDelivered ? .error : .waiting
                a.ask = p.event.askLine
            } else if let s = shown[a.id], now - s.at < 3600 {
                a.state = .waiting
                a.ask = s.text
            }
            return a
        }
        var known = Set(agents.map(\.id))
        for p in pending where !known.contains(p.event.agentKey) {
            let e = p.event
            known.insert(e.agentKey)
            out.append(Agent(id: e.agentKey, vendor: e.vendor, title: Loc.t("new session", "новая сессия"),
                             state: p.delivery == .notDelivered ? .error : .waiting,
                             project: project(e.cwd), parentId: e.agentId == nil ? nil : e.sessionId,
                             ask: e.askLine, startedAt: p.at, cwd: e.cwd, chatId: e.sessionId))
        }
        return out
    }
}
