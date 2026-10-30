import Foundation
import NotchCore

/// Settings → Services. A manifest's own labels are shown as written; these are the app's words around them.
enum ServiceText {
    struct Incomplete: LocalizedError {
        var errorDescription: String? { Loc.t("Fill in the required settings first.", "Сначала заполните обязательные настройки.") }
    }

    struct Unreadable: LocalizedError {
        let status: Int32
        var errorDescription: String? {
            Loc.t("The command did not print a list (exit code \(status)).", "Команда не вывела список (код выхода \(status)).")
        }
    }

    static var add: String { Loc.t("Add service…", "Добавить сервис…") }
    static var addTitle: String { Loc.t("Service folder", "Папка сервиса") }
    static var addHint: String { Loc.t("A folder with ops/agent-notch.json", "Папка с ops/agent-notch.json") }
    static var choose: String { Loc.t("Choose", "Выбрать") }
    static var service: String { Loc.t("Service", "Сервис") }
    static var empty: String {
        Loc.t("Agent Notch can start and set up local programs that come with an Agent Notch manifest. Add the folder of such a program; you will see what it runs before anything starts.",
              "Agent Notch умеет запускать и настраивать локальные программы с манифестом для Agent Notch. Добавьте папку такой программы: перед запуском вы увидите, какие команды она выполняет.")
    }
    static func duplicate(_ name: String, _ folder: String) -> String {
        Loc.t("«\(name)» is already added from \(folder).", "«\(name)» уже добавлен из папки \(folder).")
    }
    static var failed: String { Loc.t("Could not read the manifest", "Не удалось прочитать манифест") }

    // Approval
    static func addService(_ name: String) -> String { Loc.t("Add «\(name)»?", "Добавить «\(name)»?") }
    static func changedTitle(_ name: String) -> String { Loc.t("The manifest of «\(name)» changed", "Манифест «\(name)» изменился") }
    static var folder: String { Loc.t("Folder", "Папка") }
    static var idLabel: String { "ID" }
    static var runsIn: String { Loc.t("Runs in", "Запуск из") }
    static var added: String { Loc.t("new", "новая") }
    static var changedMark: String { Loc.t("changed", "изменена") }
    static var removed: String { Loc.t("removed", "убрана") }
    static var commands: String { Loc.t("Commands it can run", "Какие команды запускаются") }
    static func getsSettings(_ fd: Int32, needs: [String]? = nil) -> String {
        guard let needs else { return Loc.t("gets all settings on descriptor \(fd)", "получает все настройки в дескрипторе \(fd)") }
        if needs.isEmpty { return Loc.t("gets an empty settings object on descriptor \(fd)", "получает пустые настройки в дескрипторе \(fd)") }
        return Loc.t("gets on descriptor \(fd) only: ", "получает в дескрипторе \(fd) только: ") + needs.joined(separator: ", ")
    }
    static func buttonLabel(_ label: String) -> String { Loc.t("button «\(label)»", "кнопка «\(label)»") }
    static func signsIn(_ choice: String, _ field: String) -> String {
        Loc.t("«Sign in» for «\(choice)» in «\(field)»", "«Войти» для «\(choice)» в поле «\(field)»")
    }
    static var reads: String { Loc.t("Status and logs it shows", "Какие файлы читаются для состояния и логов") }
    static func fields(_ total: Int, secrets: Int) -> String {
        Loc.t("Settings: \(total), of them secrets kept in the Keychain: \(secrets).",
              "Настроек: \(total), из них секретов в связке ключей: \(secrets).")
    }
    static var approveHelp: String {
        Loc.t("Agent Notch runs only these commands, only from this folder: by your buttons, with «Start with Agent Notch» on, and the command that lists choices when you open the service's settings or after one of the service's own commands. Settings reach a command through a private pipe, never a file or environment variable. Approval covers this manifest; the programs in the folder are trusted as they are.",
              "Agent Notch запускает только эти команды и только из этой папки: по вашим кнопкам, с включённым «Запускать вместе с Agent Notch» и команду со списком вариантов, когда открываются настройки сервиса или закончилась одна из его собственных команд. Настройки попадают в команду через закрытый канал, а не через файл или переменные окружения. Подтверждается этот манифест; программам в папке приложение доверяет как есть.")
    }
    static var changedHelp: String {
        Loc.t("Nothing runs until you approve the new version.", "Пока вы не подтвердите новую версию, ничего не запускается.")
    }
    static var approve: String { Loc.t("Add", "Добавить") }
    static var approveChanged: String { Loc.t("Approve", "Подтвердить") }
    static var review: String { Loc.t("Review…", "Просмотреть…") }

    // Status
    static var running: String { Loc.t("Running", "Работает") }
    static var stopped: String { Loc.t("Stopped", "Остановлен") }
    static var since: String { Loc.t("since", "с") }
    static func row(_ key: String) -> String {
        switch key {
        case "discord": "Discord"
        case "voice": Loc.t("Voice", "Голос")
        case "brain": Loc.t("Brain", "Мозг")
        case "tts": Loc.t("Speech (TTS)", "Озвучка (TTS)")
        case "stt": Loc.t("Recognition (STT)", "Распознавание (STT)")
        default: key
        }
    }
    static var online: String { Loc.t("online", "в сети") }
    static var offline: String { Loc.t("offline", "не в сети") }
    static var noAnswer: String { Loc.t("not answering", "не отвечает") }
    static var outOfVoice: String { Loc.t("out of voice", "вне голоса") }
    static var voiceOff: String { Loc.t("off", "выключен") }
    static var ok: String { Loc.t("works", "работает") }
    static var notOk: String { Loc.t("fails", "не работает") }
    static var unknown: String { Loc.t("not checked yet", "ещё не проверено") }
    static var alive: String { Loc.t("ready", "готов") }
    static var notAlive: String { Loc.t("not responding", "не отвечает") }
    static var lastError: String { Loc.t("Last error", "Последняя ошибка") }
    static var timedOut: String { Loc.t("Stopped: the command took too long.", "Остановлено: команда работала слишком долго.") }
    static func exitCode(_ code: Int32) -> String { Loc.t("Finished with exit code \(code).", "Завершилась с кодом \(code).") }

    // Commands
    /// A manifest may name its own commands, not relabel the ones whose meaning the app knows: «stop» stays «Stop».
    static func command(_ command: ServiceManifest.Command) -> String {
        if let label = command.label, !["start", "stop", "restart", "status"].contains(command.name) { return label }
        return switch command.name {
        case "start": Loc.t("Start", "Запустить")
        case "stop": Loc.t("Stop", "Остановить")
        case "restart": Loc.t("Restart", "Перезапустить")
        case "status": Loc.t("Status", "Состояние")
        case "check-pc": Loc.t("Check PC", "Проверить ПК")
        default: command.name
        }
    }
    /// Arguments as a shell would need them, for reading only: nothing is run through a shell.
    static func commandLine(_ run: [String]) -> String {
        run.map { arg in
            arg.isEmpty || arg.contains(where: { " \"'\\$`".contains($0) }) ? "'" + arg.replacingOccurrences(of: "'", with: #"'\''"#) + "'" : arg
        }.joined(separator: " ")
    }

    // Check
    static var check: String { Loc.t("Check", "Проверка") }
    static var checkOk: String { Loc.t("Ready", "Готово") }
    static var checkFailed: String { Loc.t("Not ready", "Не готово") }
    static func health(_ ms: Int) -> String { Loc.t("answers in \(ms) ms", "отвечает за \(ms) мс") }
    static func latency(_ ms: Int) -> String {
        let seconds = (Double(ms) / 1000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: Loc.isRussian ? "ru_RU" : "en_US")))
        return Loc.t("test phrase in \(seconds) s", "пробная фраза за \(seconds) с")
    }

    // Settings form
    static var settings: String { Loc.t("Settings", "Настройки") }
    static var savedSecret: String { Loc.t("In the Keychain", "В связке ключей") }
    static var pasteSecret: String { Loc.t("Paste here", "Вставьте сюда") }
    static var replace: String { Loc.t("Replace…", "Заменить…") }
    static var delete: String { Loc.t("Delete", "Удалить") }
    static var save: String { Loc.t("Save", "Сохранить") }
    static func problem(_ problem: ServiceValues.Problem) -> String {
        switch problem {
        case .required: Loc.t("Required", "Обязательное поле")
        case .pattern: Loc.t("Wrong format", "Неверный формат")
        case .choice: Loc.t("Choose an available option", "Выберите доступный вариант")
        }
    }
    static var signInButton: String { Loc.t("Sign in", "Войти") }
    static var otherCommands: String { Loc.t("Commands", "Команды") }
    static var looking: String { Loc.t("Looking…", "Ищем…") }
    static var refresh: String { Loc.t("Refresh", "Обновить") }
    static var notSignedIn: String { Loc.t("not signed in", "вход не выполнен") }
    static var noChoice: String {
        Loc.t("Nothing to choose: none is installed and signed in. Sign in to one in Terminal, then press Refresh.",
              "Выбрать не из чего: нет установленного варианта со входом. Войдите в один из них в Терминале и нажмите «Обновить».")
    }
    static func login(_ name: String, _ command: String, _ folder: String) -> String {
        Loc.t("\(name): in Terminal, in \(folder), run \(command)", "\(name): в Терминале, в папке \(folder), выполните \(command)")
    }
    static func signIn(_ name: String) -> String {
        Loc.t("\(name): run it in Terminal once and sign in", "\(name): запустите его в Терминале и войдите")
    }
    static var formHelp: String {
        Loc.t("Secrets are kept in the macOS Keychain and are not shown again. Commands get the settings through a private pipe, not files or environment variables.",
              "Секреты хранятся в связке ключей macOS и больше не показываются. Команды получают настройки через закрытый канал, а не через файлы или переменные окружения.")
    }

    // Logs
    static var logs: String { Loc.t("Logs", "Логи") }
    static var noLog: String { Loc.t("The log is empty or not created yet.", "Лог пуст или ещё не создан.") }
    static var reveal: String { Loc.t("Show in Finder", "Показать в Finder") }
    static var masked: String { Loc.t("Tokens and keys are hidden.", "Токены и ключи скрыты.") }

    // Options
    static var launchWithApp: String { Loc.t("Start with Agent Notch", "Запускать вместе с Agent Notch") }
    static var launchHelp: String {
        Loc.t("Runs «Start» when Agent Notch opens, if the settings are complete", "Выполняет «Запустить» при открытии Agent Notch, если настройки заполнены")
    }
    static var remove: String { Loc.t("Remove service…", "Удалить сервис…") }
    static func removeConfirm(_ name: String) -> String { Loc.t("Remove «\(name)»?", "Удалить «\(name)»?") }
    static var removeHelp: String {
        Loc.t("Its secrets are deleted from the Keychain. The service's own files and a running service stay as they are.",
              "Его секреты удалятся из связки ключей. Файлы самого сервиса и запущенный сервис останутся как есть.")
    }
    static var removeButton: String { Loc.t("Remove", "Удалить") }
}
