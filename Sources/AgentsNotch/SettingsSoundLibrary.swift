import AppKit
import SwiftUI
import UniformTypeIdentifiers
import NotchCore

struct SettingsSoundLibrary: View {
    @ObservedObject var settings: AppSettings
    @State private var error: String?
    @State private var removing: CustomSound?

    var body: some View {
        Section {
            HStack {
                Text(Loc.t("My sounds", "Свои звуки"))
                Spacer()
                Button(Loc.t("Add files…", "Добавить файлы…"), systemImage: "plus") { importFiles() }
            }
            if settings.customSounds.isEmpty {
                Text(Loc.t("Add an audio file to use it for any event.", "Добавьте аудиофайл, чтобы выбрать его для любого события."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(settings.customSounds) { sound in
                HStack(spacing: 8) {
                    Text(sound.name).lineLimit(1).help(sound.name)
                    Spacer()
                    Button {
                        if !SoundPlayer.shared.preview(sound.id, volume: settings.soundEvents.volume, library: settings.soundLibrary) {
                            error = Loc.t("Could not play this sound. The file may be missing or unreadable.", "Не удалось воспроизвести звук. Возможно, файл удалён или недоступен.")
                        }
                    } label: { Image(systemName: "play.fill") }
                    .accessibilityLabel(Loc.t("Preview: ", "Послушать: ") + sound.name)
                    .disabled(settings.soundEvents.volume == 0)
                    Button { removing = sound } label: { Image(systemName: "trash") }
                        .accessibilityLabel(Loc.t("Remove: ", "Удалить: ") + sound.name)
                        .help(Loc.t("Remove from the sound library", "Удалить из библиотеки звуков"))
                }
            }
        } header: {
            Text(Loc.t("Sound library", "Библиотека звуков"))
        } footer: {
            Text(Loc.t("Files are copied into the app's library. Choose them under “Customize by event”.",
                       "Файлы копируются в библиотеку приложения. Выберите их в разделе «Настроить по событиям»."))
        }
        .alert(Loc.t("Could not use the sound", "Не удалось использовать звук"), isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(Loc.t("OK", "ОК")) { error = nil }
            } message: { Text(error ?? "") }
        .confirmationDialog(Loc.t("Remove this sound from the library?", "Удалить этот звук из библиотеки?"),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { sound in
            Button(Loc.t("Remove", "Удалить"), role: .destructive) {
                do { try settings.removeCustomSound(sound.id) }
                catch { self.error = error.localizedDescription }
                removing = nil
            }
        } message: { sound in
            Text(sound.name + "\n" + Loc.t("The library copy will be removed. Events using it will have no sound.",
                       "Копия в библиотеке будет удалена. События с этим звуком станут беззвучными."))
        }
    }

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio]
        panel.prompt = Loc.t("Add", "Добавить")
        guard panel.runModal() == .OK else { return }
        var failed: [String] = []
        for url in panel.urls {
            do { try settings.importSound(url) }
            catch { failed.append(url.lastPathComponent + ": " + error.localizedDescription) }
        }
        if !failed.isEmpty { error = failed.joined(separator: "\n") }
    }
}
