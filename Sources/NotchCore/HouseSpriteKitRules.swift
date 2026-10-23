import Foundation

/// When the SpriteKit house can draw what the user has: a layout the atlas has (islands, steps, towers), and a month in the atlas's autumn (the page's getMonth() 8...10).
/// Nil when it can. Shared by the wallpaper and the screen saver.
public enum HouseSpriteKitRules {
    public static func reason(layout: String, month: Int) -> String? {
        if HouseLayout.Style(rawValue: layout) == nil { return "layout \(layout)" }
        if !(9...11).contains(month) { return "month \(month) is not in the atlas's season" }
        return nil
    }
}
