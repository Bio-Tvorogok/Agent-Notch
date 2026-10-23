import WebKit

/// RoomScreens.swift still pushes the room config to "the page" of the main wallpaper, which no longer exists: the wallpaper is
/// SpriteKit only. This keeps it compiling and is deleted together with RoomScreens (docs/house-drop-webkit.md, #10-11).
extension RoomWallpaper {
    var web: WKWebView? { nil }
}
