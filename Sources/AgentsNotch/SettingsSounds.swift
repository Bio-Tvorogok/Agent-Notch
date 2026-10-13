import SwiftUI
import NotchCore

struct SettingsSounds: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Form {
            Section {
                Toggle(Loc.t("Event sounds", "Звуки событий"), isOn: $settings.sounds).toggleStyle(.switch)
                LabeledContent(Loc.t("Volume", "Громкость")) {
                    HStack {
                        Slider(value: $settings.soundEvents.volume, in: 0...1).frame(width: 150)
                        Text("\(Int((settings.soundEvents.volume * 100).rounded())) %")
                            .monospacedDigit().frame(width: 46, alignment: .trailing)
                    }
                }
            } footer: {
                Text(Loc.t("Pick a sound for each event, or “No sound”. Preview works even with event sounds off.", "Для каждого события выберите звук или «Без звука». Прослушивание доступно и при выключенных звуках событий."))
            }
            ForEach(SoundGroup.allCases, id: \.self) { group in
                Section(SoundText.group(group)) {
                    ForEach(SoundEvent.allCases.filter { $0.group == group }, id: \.self) { event in
                        row(event)
                    }
                }
            }
        }
    }

    private func row(_ event: SoundEvent) -> some View {
        LabeledContent(SoundText.label(event)) {
            HStack(spacing: 8) {
                Picker(SoundText.label(event), selection: Binding(
                    get: { settings.soundEvents[event] }, set: { settings.soundEvents[event] = $0 })) {
                    Text(Loc.t("No sound", "Без звука")).tag("")
                    ForEach(SoundPrefs.names, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 130)
                Button {
                    SoundPlayer.shared.preview(settings.soundEvents[event], volume: settings.soundEvents.volume)
                } label: { Image(systemName: "play.fill") }
                .accessibilityLabel(Loc.t("Preview: ", "Послушать: ") + SoundText.label(event))
                .help(Loc.t("Preview the selected sound", "Послушать выбранный звук"))
                .disabled(settings.soundEvents[event].isEmpty || settings.soundEvents.volume == 0)
            }
        }
    }
}

enum SoundText {
    static func group(_ group: SoundGroup) -> String {
        switch group { case .agents: Loc.t("Agent events", "События агентов"); case .answers: Loc.t("Answers to agents", "Ответы агенту"); case .interface: Loc.t("App actions", "Действия в приложении"); case .limits: Loc.t("Limits", "Лимиты") }
    }
    static func label(_ event: SoundEvent) -> String {
        switch event {
        case .agentAppeared: Loc.t("A new agent appeared", "Появился новый агент")
        case .agentStarted: Loc.t("An agent started a new task", "Агент начал новую задачу")
        case .agentResumed: Loc.t("An agent resumed work", "Агент продолжил работу")
        case .permissionRequested: Loc.t("An agent is waiting for permission", "Агент ждёт разрешения")
        case .questionAsked: Loc.t("An agent asks a question", "Агент задаёт вопрос")
        case .planProposed: Loc.t("An agent proposes a plan", "Агент предлагает план")
        case .agentFinished: Loc.t("An agent finished", "Агент завершил работу")
        case .agentError: Loc.t("An agent hit an error", "Ошибка у агента")
        case .allowed: Loc.t("Action allowed", "Действие разрешено")
        case .alwaysAllowed: Loc.t("“Always” chosen", "Выбрано «Разрешать всегда»")
        case .denied: Loc.t("Action denied", "Действие отклонено")
        case .answerSent: Loc.t("Answer sent", "Ответ отправлен")
        case .planAccepted: Loc.t("Plan accepted", "План принят")
        case .planReturned: Loc.t("Plan sent back with a comment", "План возвращён с комментарием")
        case .handedBack: Loc.t("Request handed to the agent window", "Запрос передан в окно агента")
        case .listOpened: Loc.t("List opened", "Список открыт")
        case .listClosed: Loc.t("List closed", "Список закрыт")
        case .cardOpened: Loc.t("Agent card opened", "Карточка агента открыта")
        case .cardClosed: Loc.t("Agent card closed", "Карточка агента закрыта")
        case .cardTabChanged: Loc.t("Card tab switched", "Выбрана другая вкладка карточки")
        case .agentOpened: Loc.t("Jumped to the agent window", "Переход в окно агента")
        case .settingsOpened: Loc.t("Settings opened", "Настройки открыты")
        case .settingsClosed: Loc.t("Settings closed", "Настройки закрыты")
        case .settingsSectionChanged: Loc.t("Settings section switched", "Выбран другой раздел настроек")
        case .settingsChanged: Loc.t("A setting changed", "Настройка изменена")
        case .settingsReset: Loc.t("Settings reset", "Настройки сброшены")
        case .connected: Loc.t("Hooks installed", "Хуки установлены")
        case .disconnected: Loc.t("Hooks removed", "Хуки удалены")
        case .operationFailed: Loc.t("An action failed", "Не получилось выполнить действие")
        case .limitWarning: Loc.t("Warning threshold reached", "Достигнут порог предупреждения")
        case .limitExhausted: Loc.t("Limit used up", "Лимит исчерпан")
        case .limitRestored: Loc.t("Limit available again", "Лимит снова доступен")
        }
    }
}
