/// ScreenSaverEngine may mirror a live saver from an occluded host window. Retired host windows
/// lose their saver level; previews use ordinary window visibility instead.
enum SaverActivity {
    static func canDraw(running: Bool, attached: Bool, visible: Bool, occluded: Bool,
                        preview: Bool, level: Int, saverLevel: Int) -> Bool {
        running && attached && visible && (preview ? !occluded : level >= saverLevel)
    }
}
