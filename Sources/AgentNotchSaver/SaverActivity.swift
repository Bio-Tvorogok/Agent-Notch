/// ScreenSaverEngine may mirror a live saver from an occluded host window. Retired host windows
/// lose their saver level; previews use ordinary window visibility instead.
enum SaverActivity {
    struct State {
        var missingSince: Double?
        var draw = false
        var exitHost = false
    }

    /// A missed sample starts a six-second grace period, including while the host is starting.
    /// Repeated callbacks at the same instant cannot consume the grace period.
    static func sample(_ previous: State, now: Double, running: Bool, visible: Bool, preview: Bool) -> State {
        guard running else { return State() }
        guard !preview else { return State(draw: visible) }
        guard !visible else { return State(draw: true) }
        let since = previous.missingSince ?? now
        let expired = now - since >= 6
        return State(missingSince: since, draw: !expired, exitHost: expired)
    }

    static func canDraw(running: Bool, attached: Bool, visible: Bool, occluded: Bool,
                        preview: Bool, level: Int, saverLevel: Int) -> Bool {
        running && attached && visible && (preview ? !occluded : level >= saverLevel)
    }
}
