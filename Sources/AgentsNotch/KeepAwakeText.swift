import NotchCore

enum KeepAwakeText {
    static var passwordless: String { Loc.t("Passwordless switching", "Переключение без пароля") }
    static var setup: String { Loc.t("Set up", "Настроить") }
    static var remove: String { Loc.t("Remove permission", "Удалить разрешение") }
    static var permissionHelp: String {
        Loc.t("Authorize once to let this user switch Keep awake without a password. All processes running as this user can then turn sleep prevention on or off. macOS asks for an administrator password when adding or removing this permission.",
              "Одно подтверждение позволит переключать «Без сна» без пароля. Все процессы этого пользователя смогут включать и выключать запрет сна. При подключении и удалении разрешения macOS попросит пароль администратора.")
    }
    static var confirm: String { Loc.t("Allow passwordless sleep control?", "Разрешить управление сном без пароля?") }
    static var confirmHelp: String {
        Loc.t("This grants this user permanent permission to run only pmset disablesleep 0 and pmset disablesleep 1 as root. You can remove it here later.",
              "Пользователь получит постоянное разрешение выполнять от root две команды: pmset disablesleep 0 и pmset disablesleep 1. Удалить разрешение можно здесь же.")
    }

    static func error(_ error: Error?) -> String {
        switch error {
        case KeepAwakeFailure.unavailable?:
            Loc.t("Cannot verify the Mac's sleep setting. Try again after reopening the panel.", "Не удалось проверить настройку сна Mac. Попробуй открыть панель снова.")
        case KeepAwakeFailure.notApplied?:
            Loc.t("macOS did not apply the setting. The switch shows the current state.", "macOS не применила настройку. Тумблер показывает текущее состояние.")
        case KeepAwakeFailure.permissionNotApplied?:
            Loc.t("Could not verify passwordless access. If the rule is installed, you can still remove it here. Another sudo policy may require a password.", "Не удалось подтвердить доступ без пароля. Если правило установлено, его можно удалить здесь. Другая политика sudo может требовать пароль.")
        case KeepAwakeFailure.passwordlessDenied(let detail)?:
            Loc.t("The installed rule did not allow passwordless switching. Open Settings → General → Keep awake to check or remove it.", "Установленное правило не разрешило переключение без пароля. Проверь или удали его в Настройки → Общие → Без сна.") + (detail.isEmpty ? "" : "\n" + detail)
        case KeepAwakeFailure.authorization(let detail)?:
            Loc.t("macOS could not change the setting.", "macOS не смогла изменить настройку.") + (detail.isEmpty ? "" : "\n" + detail)
        default:
            error?.localizedDescription ?? ""
        }
    }
}
