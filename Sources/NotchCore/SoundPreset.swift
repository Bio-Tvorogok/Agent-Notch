import Foundation

public enum SoundPreset: String, CaseIterable, Sendable {
    case requestsOnly, attention, important, allEvents

    public func apply(to prefs: SoundPrefs) -> SoundPrefs {
        var next = prefs
        for event in SoundEvent.allCases { next[event] = sound(for: event) }
        return next
    }

    public static func matching(_ prefs: SoundPrefs) -> SoundPreset? {
        allCases.first { preset in
            SoundEvent.allCases.allSatisfy { prefs[$0] == preset.sound(for: $0) }
        }
    }

    private func sound(for event: SoundEvent) -> String {
        if self == .requestsOnly { return event == .permissionRequested ? "Glass" : "" }
        switch event {
        case .permissionRequested, .questionAsked, .planProposed: return "Glass"
        case .agentError, .operationFailed, .limitExhausted: return "Basso"
        case .limitWarning: return "Sosumi"
        case .agentFinished: return self == .attention ? "" : "Hero"
        case .limitRestored: return self == .attention ? "" : "Ping"
        default: break
        }
        guard self == .allEvents else { return "" }
        switch event {
        case .denied, .planReturned: return "Basso"
        case .allowed, .alwaysAllowed, .answerSent, .planAccepted: return "Pop"
        case .agentAppeared, .agentStarted, .agentResumed, .connected: return "Ping"
        default: return "Tink"
        }
    }
}
