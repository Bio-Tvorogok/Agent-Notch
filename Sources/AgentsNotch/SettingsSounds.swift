import SwiftUI
import NotchCore

struct SettingsSounds: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Form {
            Section {
                Toggle("Звуки событий", isOn: $settings.sounds).toggleStyle(.switch)
                LabeledContent("Громкость") {
                    HStack {
                        Slider(value: $settings.soundEvents.volume, in: 0...1).frame(width: 150)
                        Text("\(Int((settings.soundEvents.volume * 100).rounded())) %")
                            .monospacedDigit().frame(width: 46, alignment: .trailing)
                    }
                }
            } footer: {
                Text("Для каждого события выберите звук или «Без звука». Прослушивание доступно и при выключенных звуках событий.")
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
                    Text("Без звука").tag("")
                    ForEach(SoundPrefs.names, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 130)
                Button {
                    SoundPlayer.shared.preview(settings.soundEvents[event], volume: settings.soundEvents.volume)
                } label: { Image(systemName: "play.fill") }
                .accessibilityLabel("Послушать: " + SoundText.label(event))
                .help("Послушать выбранный звук")
                .disabled(settings.soundEvents[event].isEmpty || settings.soundEvents.volume == 0)
            }
        }
    }
}

enum SoundText {
    static func group(_ group: SoundGroup) -> String {
        switch group { case .agents: "События агентов"; case .answers: "Ответы агенту"; case .interface: "Действия в приложении"; case .limits: "Лимиты" }
    }
    static func label(_ event: SoundEvent) -> String {
        switch event {
        case .agentAppeared: "Появился новый агент"
        case .agentStarted: "Агент начал новую задачу"
        case .agentResumed: "Агент продолжил работу"
        case .permissionRequested: "Агент ждёт разрешения"
        case .questionAsked: "Агент задаёт вопрос"
        case .planProposed: "Агент предлагает план"
        case .agentFinished: "Агент завершил работу"
        case .agentError: "Ошибка у агента"
        case .allowed: "Действие разрешено"
        case .alwaysAllowed: "Выбрано «Разрешать всегда»"
        case .denied: "Действие отклонено"
        case .answerSent: "Ответ отправлен"
        case .planAccepted: "План принят"
        case .planReturned: "План возвращён с комментарием"
        case .handedBack: "Запрос передан в окно агента"
        case .listOpened: "Список открыт"
        case .listClosed: "Список закрыт"
        case .cardOpened: "Карточка агента открыта"
        case .cardClosed: "Карточка агента закрыта"
        case .cardTabChanged: "Выбрана другая вкладка карточки"
        case .agentOpened: "Переход в окно агента"
        case .settingsOpened: "Настройки открыты"
        case .settingsClosed: "Настройки закрыты"
        case .settingsSectionChanged: "Выбран другой раздел настроек"
        case .settingsChanged: "Настройка изменена"
        case .settingsReset: "Настройки сброшены"
        case .connected: "Агент подключён"
        case .disconnected: "Агент отключён"
        case .operationFailed: "Не получилось выполнить действие"
        case .limitWarning: "Достигнут порог предупреждения"
        case .limitExhausted: "Лимит исчерпан"
        case .limitRestored: "Лимит снова доступен"
        }
    }
}
