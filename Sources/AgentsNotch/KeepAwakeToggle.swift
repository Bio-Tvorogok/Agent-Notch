import SwiftUI
import NotchCore

struct KeepAwakeToggle: View {
    @ObservedObject var model: KeepAwakeModel = .shared
    @Environment(\.theme) private var theme

    private var active: Bool { model.enabled == true }
    private var status: String {
        if model.busy { return Loc.t("Changing…", "Изменение…") }
        return model.enabled.map { $0 ? Loc.t("On", "Включён") : Loc.t("Off", "Выключен") }
            ?? Loc.t("Unknown", "Недоступен")
    }

    var body: some View {
        HStack(spacing: 4) {
            if model.busy {
                ProgressView().controlSize(.mini).frame(width: 14)
            } else {
                Image(systemName: model.enabled == nil ? "exclamationmark.triangle" : "cup.and.saucer.fill")
                    .foregroundStyle(model.enabled == true ? Ink.accent : Ink.dim)
            }
            Toggle(isOn: Binding(
                get: { model.enabled == true },
                set: { requested in Task { await model.setEnabled(requested) } }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Loc.t("Keep awake", "Без сна")).fontWeight(.semibold)
                    Text(status)
                        .font(.system(size: 8, weight: .bold, design: theme.design))
                        .foregroundStyle(active ? Ink.accent : Ink.dim)
                }
            }
            .toggleStyle(KeepAwakeSwitchStyle())
            .disabled(model.busy || model.enabled == nil)
        }
        .font(.system(size: 10, design: theme.design))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(theme.color(.accent).opacity(active ? 0.16 : 0), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(active ? theme.color(.accent).opacity(0.7) : .clear, lineWidth: 1)
        }
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

private struct KeepAwakeSwitchStyle: ToggleStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 6) {
                configuration.label
                Capsule()
                    .fill(configuration.isOn ? theme.color(.accent) : theme.color(.faint))
                    .frame(width: 32, height: 18)
                    .overlay {
                        Circle()
                            .fill(configuration.isOn ? Color(white: 0.08) : theme.color(.secondary))
                            .frame(width: 14, height: 14)
                            .offset(x: configuration.isOn ? 7 : -7)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
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
