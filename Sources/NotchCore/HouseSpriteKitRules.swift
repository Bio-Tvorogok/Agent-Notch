import Foundation

/// When the SpriteKit house can draw what the user has: the islands layout, and any month (each season has its own atlas: room/atlas, room/atlas-<season>).
/// Nil when it can. Shared by the wallpaper and the screen saver.
public enum HouseSpriteKitRules {
    public static func reason(layout: String, month: Int) -> String? {
        if layout != "islands" { return "layout \(layout)" }
        return nil
    }
}
