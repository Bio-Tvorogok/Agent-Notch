import Foundation

/// Extra screens follow Swift's agent snapshot, independent of whether the main WebView can send messages.
struct RoomActivity {
    private(set) var working = false
    private(set) var settleUntil: TimeInterval = 0

    mutating func update(working: Bool, changed: Bool, now: TimeInterval) {
        self.working = working
        if changed { settleUntil = now + 12 }
    }

    func awake(at now: TimeInterval) -> Bool { working || now < settleUntil }
    static func isActive(visible: Bool, awake: Bool) -> Bool { visible && awake }
}
