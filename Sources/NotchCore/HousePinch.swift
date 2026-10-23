import Foundation

/// What the pinch tap reports and when the one-time "pinch is off" hint is due. Pure, so it is checked without a window or the permission.
public enum HousePinch {
    /// The start-up line about the pinch tap. `created` is nil when no tap was tried (permission missing), `enabled` is the tap's state.
    public static func statusLine(allowed: Bool, created: Bool?, enabled: Bool = false) -> String {
        guard allowed else {
            return "agents-notch: pinch tap: Input Monitoring not granted; not created (a click on a room, a two-finger double tap, Esc and scroll still work; pinch needs Input Monitoring from Settings)"
        }
        guard let created else { return "agents-notch: pinch tap: Input Monitoring granted" }
        return created ? "agents-notch: pinch tap: Input Monitoring granted; created, enabled=\(enabled)"
                       : "agents-notch: pinch tap: Input Monitoring granted; CGEvent.tapCreate failed"
    }

    /// The hint is shown once, the first time a click has zoomed the house in while no pinch can arrive.
    public static func hintDue(tapActive: Bool, alreadyShown: Bool, zoomTarget: Double) -> Bool {
        !tapActive && !alreadyShown && zoomTarget > 1.01
    }
}
