import SwiftUI
import NotchCore

struct KeepAwakeToggle: View {
    @ObservedObject var model: KeepAwakeModel = .shared
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            if model.busy {
                ProgressView().controlSize(.mini).frame(width: 14)
            } else {
                Image(systemName: model.enabled == nil ? "exclamationmark.triangle" : "cup.and.saucer.fill")
                    .foregroundStyle(model.enabled == true ? Ink.accent : Ink.dim)
            }
            Toggle(Loc.t("Keep awake", "Без сна"), isOn: Binding(
                get: { model.enabled == true },
                set: { requested in Task { await model.setEnabled(requested) } }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(theme.color(.accent))
            .disabled(model.busy || model.enabled == nil)
        }
        .font(.system(size: 10, design: theme.design))
        .fixedSize()
        .help(model.enabled == nil
              ? Loc.t("Cannot read the Mac's sleep setting.", "Не удалось прочитать настройку сна Mac.")
              : Loc.t("Keep the Mac running with the lid closed. Stays on until you switch it off, even after quitting the app. For passwordless switching, open Settings → General → Keep awake.",
                      "Mac продолжает работать с закрытой крышкой. Режим действует до выключения тумблера, даже после выхода из приложения. Работа без пароля: Настройки → Общие → Без сна."))
        .accessibilityLabel(Loc.t("Keep the Mac awake with the lid closed", "Работа Mac с закрытой крышкой"))
        .accessibilityValue(model.enabled.map { $0 ? Loc.t("On", "Включено") : Loc.t("Off", "Выключено") }
                            ?? Loc.t("Unknown", "Неизвестно"))
        .onAppear { model.refresh() }
        .alert(Loc.t("Could not change sleep mode", "Не удалось изменить режим сна"), isPresented: Binding(
            get: { model.error != nil }, set: { if !$0 { model.error = nil } }
        )) {
            Button("OK") { model.error = nil }
        } message: {
            Text(KeepAwakeText.error(model.error))
        }
    }

}

struct PanelHeader: View {
    let usage: UsageModel

    var body: some View {
        HStack(spacing: 8) {
            LimitChips(usage: usage)
            Spacer(minLength: 4)
            KeepAwakeToggle()
        }
    }
}
