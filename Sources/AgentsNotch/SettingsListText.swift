import NotchCore

enum SettingsListText {
    static func empty(minutes: Int) -> String {
        "Нет сессий за последние \(minutes) мин. Здесь появятся агенты Claude Code и Codex."
    }
    static func allow(hint: Bool, shortcut: NotchCore.KeyboardShortcut) -> String {
        hint ? "Разрешить " + shortcut.display : "Разрешить"
    }
    static func deny(hint: Bool, shortcut: NotchCore.KeyboardShortcut) -> String {
        hint ? "Отклонить " + shortcut.display : "Отклонить"
    }
}
