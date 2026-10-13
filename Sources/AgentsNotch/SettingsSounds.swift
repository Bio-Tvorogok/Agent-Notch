import SwiftUI
import NotchCore

struct SettingsSounds: View {
    @ObservedObject var settings: AppSettings
    @State var customizing = false
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
                Picker(Loc.t("Sound set", "Набор звуков"), selection: Binding<String>(
                    get: { settings.soundPreset?.rawValue ?? "custom" },
                    set: { if let preset = SoundPreset(rawValue: $0) { settings.applySoundPreset(preset) } })) {
                    ForEach(SoundPreset.allCases, id: \.self) { preset in
                        Text(SoundText.preset(preset)).tag(preset.rawValue)
                    }
                    if settings.soundPreset == nil { Text(Loc.t("Custom", "Свой")).tag("custom") }
                }
            } footer: {
                Text(settings.soundPreset.map(SoundText.presetHelp)
                     ?? Loc.t("Your sounds for individual events.", "Ваши звуки для отдельных событий."))
            }
            SettingsSoundLibrary(settings: settings)
            Section {
                DisclosureGroup(Loc.t("Customize by event", "Настроить по событиям"), isExpanded: $customizing) {
                    ForEach(SoundGroup.allCases, id: \.self) { group in
                        Text(SoundText.group(group))
                            .font(.headline).foregroundStyle(.secondary).padding(.top, 10)
                        ForEach(SoundEvent.allCases.filter { $0.group == group }, id: \.self) { event in
                            row(event).padding(.vertical, 3)
                                .accessibilityElement(children: .contain)
                        }
                    }
                }
            } footer: {
                Text(Loc.t("Preview works even with event sounds off.", "Прослушивание доступно и при выключенных звуках событий."))
            }
        }
    }

    private func row(_ event: SoundEvent) -> some View {
        LabeledContent(SoundText.label(event)) {
            HStack(spacing: 8) {
                Picker(SoundText.label(event), selection: Binding(
                    get: { settings.soundEvents[event] }, set: { settings.soundEvents[event] = $0 })) {
                    Text(Loc.t("No sound", "Без звука")).tag("")
                    Section(Loc.t("System sounds", "Системные звуки")) {
                        ForEach(SoundPrefs.names, id: \.self) { Text($0).tag($0) }
                    }
                    if !settings.customSounds.isEmpty {
                        Section(Loc.t("My sounds", "Свои звуки")) {
                            ForEach(settings.customSounds) { sound in Text(sound.name).tag(sound.id) }
                        }
                    }
                    let choice = settings.soundEvents[event]
                    if SoundLibrary.isCustomID(choice), !settings.customSounds.contains(where: { $0.id == choice }) {
                        Text(Loc.t("Unavailable sound", "Звук недоступен")).tag(choice).disabled(true)
                    }
                }.labelsHidden().frame(width: 130)
                Button {
                    SoundPlayer.shared.preview(settings.soundEvents[event], volume: settings.soundEvents.volume, library: settings.soundLibrary)
                } label: { Image(systemName: "play.fill") }
                .accessibilityLabel(Loc.t("Preview: ", "Послушать: ") + SoundText.label(event))
                .help(Loc.t("Preview the selected sound", "Послушать выбранный звук"))
                .disabled(settings.soundEvents[event].isEmpty || settings.soundEvents.volume == 0
                          || (SoundLibrary.isCustomID(settings.soundEvents[event]) && settings.soundLibrary.url(for: settings.soundEvents[event]) == nil))
            }
        }
    }
}

enum SoundText {
    static func preset(_ preset: SoundPreset) -> String {
        switch preset {
        case .requestsOnly: Loc.t("Permissions only", "Только разрешения")
        case .attention: Loc.t("Needs attention", "Нужно внимание")
        case .important: Loc.t("Important events", "Важные события")
        case .allEvents: Loc.t("All events", "Все события")
        }
    }
    static func presetHelp(_ preset: SoundPreset) -> String {
        switch preset {
        case .requestsOnly: Loc.t("A sound when an agent waits for permission.", "Звук, когда агент ждёт разрешения.")
        case .attention: Loc.t("Permissions, questions, plans, errors and limit warnings.", "Разрешения, вопросы, планы, ошибки и предупреждения о лимитах.")
        case .important: Loc.t("Everything that needs attention, plus task completion and restored limits.", "Всё, что требует внимания, плюс завершение задач и восстановление лимитов.")
        case .allEvents: Loc.t("Sounds for every event, including answers and app actions.", "Звуки для всех событий, включая ответы и действия в приложении.")
        }
    }

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
