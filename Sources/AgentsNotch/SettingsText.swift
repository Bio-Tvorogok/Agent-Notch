import Foundation
import SwiftUI
import NotchCore

/// Russian copy stays here until the translation pass. Plain words: no hooks, chips, effort or worktree in what people read.
enum SettingsText {
    static let window = "Настройки…"
    static let title = "Настройки"

    // Внешний вид
    static let presetHelp = "Пресет сразу настраивает строку, список, лимиты и карточку."
    static let own = "Своё"
    static let marks = "Значки агентов"
    static let markSize = "Размер"
    static let inRow = "В строке агента"
    static let order = "Порядок…"
    static let orderTitle = "Порядок в строке"
    static let cardOrderTitle = "Порядок в карточке"
    static let orderHelp = "Включите нужное и расставьте стрелками."
    static let doneButton = "Готово"
    static let card = "Карточка агента"
    static let cardHelp = "Открывается по клику на агента."
    static let cardBlocks = "Блоки…"
    static let rowHints: [RowPart: String] = [
        .model: "Например, opus или gpt-6.1",
        .activity: "Последняя команда или файл",
        .branch: "Ветка git, в которой работает агент",
        .runningTime: "Сколько агент уже работает",
        .context: "Кольцо: сколько памяти разговора занято",
        .cost: "Примерная цена сессии",
    ]

    // Список
    static let sorting = "Порядок агентов"
    static let groupProjects = "Группировать по проектам"
    static let tree = "Субагенты"
    static let treeHelp = "Помощники, которых агент запустил сам"
    static let showFinished = "Показывать завершённых"
    static let finished = "Сколько держать завершённых"
    static func minutes(_ n: Int) -> String { "\(n) мин" }
    static let titleSource = "Название агента"
    static let vendors = "Чьих агентов показывать"
    static let wing = "Рядом с чёлкой"
    static let wingContent = "Что видно"
    static let maxMarks = "Значков до счётчика"
    static let maxMarksHelp = "Если агентов больше, вместо значков появится число"
    static let grouping = "Группировать значки"
    static let separate = "Субагенты отдельными значками"

    // Запросы
    static let answer = "Отвечать прямо в чёлке"
    static let answerHelp = "Разрешить или отклонить, не переключаясь в терминал"
    static let openRequest = "Открывать список, когда агент ждёт"
    static let sounds = "Звук, когда агент ждёт"
    static let sound = "Какой звук"
    static let listen = "Послушать"
    static let keys = "Горячие клавиши"
    static let record = "Записать"
    static let recording = "Нажмите сочетание…"
    static let cancelRecord = "Esc — отмена"
    static let invalidShortcut = "Нужна клавиша с ⌃, ⌥ или ⌘; сочетания не должны повторяться."
    static let shortcutHelp = "Клавиши отвечают только на запрос, который виден в чёлке. Опасные команды — только кликом."
    static let hotKeyFailed = "Не удалось занять сочетание. Возможно, его использует другое приложение."

    // Лимиты
    static let chips = "Показывать остаток лимита"
    static let warning = "Предупреждать, когда израсходовано"
    static let windows = "Какие лимиты"
    static let limitVendors = "Для кого"

    // Подключение
    static let connected = "Подключено"
    static let notConnected = "Не подключено"
    static let connect = "Подключить"
    static let disconnect = "Отключить"
    static let connectHelp = "Без подключения агенты видны, но отвечать на запросы из чёлки нельзя."
    static let trust = "В Codex один раз наберите /hooks и отметьте notch-hook как доверенный."
    static let windowsAccess = "Доступ к окнам"
    static let windowsAccessHelp = "Нужен, чтобы «Открыть» переключал на окно агента"
    static let granted = "Разрешён"
    static let requestAccess = "Разрешить…"
    static let hidden = "Скрытые проекты"
    static let hiddenHelp = "Агенты из этих папок не показываются нигде"
    static let emptyHidden = "Пока ничего не скрыто"
    static let projectPath = "Путь к папке проекта"
    static let add = "Добавить"
    static let remove = "Убрать"
    static let operationFailed = "Не получилось изменить настройки"

    // Общие
    static let login = "Запускать при входе в систему"
    static let loginApproval = "Подтвердите автозапуск в системных настройках."
    static let resetAll = "Сбросить все настройки"
    static let resetAllHelp = "Вернёт всё как при первом запуске, кроме подключения"
    static let resetButton = "Сбросить…"
    static let resetConfirm = "Сбросить все настройки?"
    static let resetConfirmButton = "Сбросить"
    static let cancel = "Отмена"
    static let about = "О приложении"
    static let license = "Лицензия MIT"
    static let github = "Ссылка на GitHub появится позже"
    static let version = "Версия"

    static let moveUp = "Выше"
    static let moveDown = "Ниже"
    static let claude = "Claude"
    static let codex = "Codex"
    static let claudeCode = "Claude Code"
    static let light = "Лёгкая модель"
    static let regular = "Обычная модель"

    static let names = [
        "appearance": "Внешний вид", "list": "Список", "requests": "Запросы", "limits": "Лимиты",
        "connection": "Подключение", "general": "Общие",
        "brief": "Кратко", "detailed": "Подробно", "everything": "Всё",
        "dots": "Точки", "logos": "Логотипы", "logosMono": "Логотипы цветом состояния", "letters": "Буквы",
        "small": "Мелкий", "medium": "Средний", "large": "Крупный", "always": "Всегда", "nearLimit": "Когда мало", "never": "Никогда",
        "marks": "Только значки", "counts": "Значки и числа", "projects": "Названия проектов",
        "project": "Проект", "vendor": "Агент", "session": "Имя сессии", "firstPrompt": "Первый запрос", "branch": "Ветка",
        "attention": "Сначала ждущие", "recent": "Сначала новые", "name": "По имени",
        "auto": "Авто", "expanded": "Все", "collapsed": "Свёрнуты", "hidden": "Не показывать",
        "short": "5 часов", "weekly": "Неделя",
        "allow": "Разрешить", "deny": "Отклонить", "list.key": "Открыть список",
        "statusMark": "Значок", "title": "Название", "model": "Модель", "effort": "Режим размышлений", "worktree": "Папка и ветка",
        "activity": "Что агент делает сейчас", "runningTime": "Время работы", "context": "Контекст", "cost": "Стоимость",
        "done": "Сделано", "remaining": "Осталось", "files": "Файлы", "log": "Лог", "commands": "Команды и тесты",
        "lastMessage": "Последнее сообщение", "errors": "Ошибки", "modelTime": "Модель и время", "contextCost": "Контекст и стоимость",
        "working": "Работает", "waiting": "Ждёт", "error": "Ошибка",
    ]
    static func name(_ key: String) -> String { names[key] ?? key }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance, list, requests, limits, connection, general
    var id: String { rawValue }
    var title: String { SettingsText.name(rawValue) }
    var icon: String {
        switch self {
        case .appearance: "circle.lefthalf.filled"
        case .list: "list.bullet"
        case .requests: "questionmark"
        case .limits: "gauge.with.dots.needle.33percent"
        case .connection: "powerplug.fill"
        case .general: "gearshape.fill"
        }
    }
    var tint: Color {
        switch self {
        case .appearance: Color(red: 0.04, green: 0.52, blue: 1)
        case .list: Color(red: 0.37, green: 0.36, blue: 0.9)
        case .requests: Color(red: 1, green: 0.62, blue: 0.04)
        case .limits: Color(red: 0.19, green: 0.69, blue: 0.78)
        case .connection: Color(red: 0.2, green: 0.78, blue: 0.35)
        case .general: Color(white: 0.56)
        }
    }
}
