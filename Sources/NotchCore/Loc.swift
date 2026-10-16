import Foundation

/// UI language: English by default, Russian when the system's first preferred language is Russian.
/// No .lproj bundles: the app is built with plain swiftc, so each text enum keeps both strings side by side.
public enum Loc {
    public enum Language: String, Sendable { case en, ru }

    /// Set by checks and `--snapshot` runs; nil follows `AGENT_NOTCH_LANG`, then the system.
    nonisolated(unsafe) public static var forced: Language?

    public static let system: Language = {
        if let env = ProcessInfo.processInfo.environment["AGENT_NOTCH_LANG"], let lang = Language(rawValue: env.lowercased()) {
            return lang
        }
        return detect(Locale.preferredLanguages)
    }()

    public static func detect(_ preferred: [String]) -> Language {
        preferred.first.map { $0.lowercased().hasPrefix("ru") } == true ? .ru : .en
    }

    public static var language: Language { forced ?? system }
    public static var isRussian: Bool { language == .ru }

    /// The string for the current language.
    public static func t(_ en: String, _ ru: String) -> String { isRussian ? ru : en }
}

public enum DeliveryText {
    public static var sent: String { Loc.t("Sent…", "Отправлено…") }
    public static var notDelivered: String { Loc.t("delivery unconfirmed", "доставка не подтверждена") }
    public static var openTerminal: String { Loc.t("Open terminal", "Открыть терминал") }
    public static var dismiss: String { Loc.t("Dismiss", "Скрыть") }
    public static func countdown(_ seconds: Int) -> String {
        Loc.t("Waiting: \(seconds)s left", "Ожидание: осталось \(seconds) с")
    }
}

public enum SessionText {
    public static var interrupted: String { Loc.t("interrupted", "прервано") }
    public static func helpers(_ n: Int) -> String {
        let word: String
        let last = n % 10, tens = n % 100
        if Loc.isRussian {
            word = last == 1 && tens != 11 ? "помощника" : "помощников"
        } else { word = n == 1 ? "helper" : "helpers" }
        return Loc.t("working · waiting for \(n) \(word)", "работает · ждёт \(n) \(word)")
    }
}
