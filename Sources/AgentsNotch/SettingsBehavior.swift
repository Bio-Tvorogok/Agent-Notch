import AppKit
import SwiftUI

struct SettingsRequests: View {
    @ObservedObject var settings: AppSettings
    private let sounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.answerFromNotch) { SettingsLabel(SettingsText.answer, hint: SettingsText.answerHelp) }
                    .toggleStyle(.switch)
                Toggle(SettingsText.openRequest, isOn: $settings.behavior.openOnRequest).toggleStyle(.switch)
            }
            Section {
                Toggle(SettingsText.sounds, isOn: $settings.sounds).toggleStyle(.switch)
                LabeledContent(SettingsText.sound) {
                    HStack {
                        Picker(SettingsText.sound, selection: $settings.behavior.soundName) {
                            ForEach(sounds, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().frame(width: 140)
                        Button(SettingsText.listen) { NSSound(named: NSSound.Name(settings.behavior.soundName))?.play() }
                    }
                }.disabled(!settings.sounds)
            }
            SettingsShortcuts(settings: settings)
        }
    }
}

/// Hidden projects belong to «Подключение»: they decide what the app reads at all.
struct SettingsHiddenProjects: View {
    @ObservedObject var settings: AppSettings
    @State private var project = ""

    var body: some View {
        Section {
            if settings.behavior.hiddenProjects.isEmpty {
                Text(SettingsText.emptyHidden).foregroundStyle(.secondary)
            }
            ForEach(settings.behavior.hiddenProjects, id: \.self) { path in
                HStack {
                    Text(path).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Button(SettingsText.remove) { settings.behavior.hiddenProjects.removeAll { $0 == path } }
                }
            }
            HStack {
                TextField(SettingsText.projectPath, text: $project, prompt: Text(SettingsText.projectPath)).labelsHidden()
                Button(SettingsText.add) {
                    let path = project.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !path.isEmpty, !settings.behavior.hiddenProjects.contains(path) { settings.behavior.hiddenProjects.append(path) }
                    project = ""
                }.disabled(project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            SettingsLabel(SettingsText.hidden, hint: SettingsText.hiddenHelp)
        }
    }
}
