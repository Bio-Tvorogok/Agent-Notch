import Foundation

extension UsageView {
    /// Title and status updates must not turn context publishing into a read loop.
    public static func contextSourceChanged(previous: Agent?, next: Agent) -> Bool {
        previous?.id != next.id || previous?.logPath != next.logPath || previous?.vendor != next.vendor
    }
}
