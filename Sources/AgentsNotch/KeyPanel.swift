import AppKit
import NotchCore

/// A panel that stays non-activating (the frontmost app keeps focus) but can take keystrokes
/// while a question or plan row needs typing. A plain NSPanel with a borderless style never becomes key.
final class KeyPanel: NSPanel {
    /// Set by NotchController from the open requests; false for the wing, which has nothing to type into.
    var wantsKey = false
    override var canBecomeKey: Bool { wantsKey }
    override var canBecomeMain: Bool { false }
}

extension PendingAsk {
    /// The request has a text field: the question's own answer or the plan's comment.
    var needsTyping: Bool { event.isQuestion || event.isPlan }
}
