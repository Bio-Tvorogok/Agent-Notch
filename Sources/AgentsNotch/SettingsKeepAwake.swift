import AppKit
import SwiftUI
import NotchCore

struct SettingsKeepAwake: View {
    @ObservedObject private var model = KeepAwakeModel.shared
    @State private var confirmPermission = false

    var body: some View {
        Section(Loc.t("Keep awake", "Без сна")) {
            LabeledContent(KeepAwakeText.passwordless) {
                HStack(spacing: 8) {
                    if model.permissionInstalled {
                        Button(Loc.t("Check access", "Проверить доступ")) { Task { await model.checkPasswordless() } }
                        Button(KeepAwakeText.remove) { Task { await model.configurePasswordless(false) } }
                    } else {
                        Button(KeepAwakeText.setup) { confirmPermission = true }
                    }
                }.disabled(model.busy)
            }
            .accessibilityElement(children: .contain)
            if model.permissionInstalled {
                Text(model.passwordless.map {
                    $0 ? Loc.t("Last check: current sleep setting accepted without a password.", "Последняя проверка: текущий режим подтверждён без пароля.")
                       : Loc.t("Passwordless access is unavailable. The installed rule can still be removed.", "Доступ без пароля недоступен. Установленное правило можно удалить.")
                } ?? Loc.t("Permission installed. Use Check access to verify it without changing the sleep mode.", "Правило установлено. «Проверить доступ» проверит его, сохранив текущий режим сна."))
                .font(.caption).foregroundStyle(model.passwordless == false ? Color.red : Color.secondary)
            }
            if model.busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(Loc.t("Waiting for macOS…", "Ожидаем macOS…")).foregroundStyle(.secondary)
                }
            }
            Text(KeepAwakeText.permissionHelp).font(.caption).foregroundStyle(.secondary)
            Text(Loc.t("The panel's Keep awake switch controls sleep mode. The mode stays on until you switch it off, including after quitting the app.",
                       "Тумблер «Без сна» в панели управляет режимом сна. Режим действует до ручного выключения, даже после выхода из приложения."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog(KeepAwakeText.confirm, isPresented: $confirmPermission, titleVisibility: .visible) {
            Button(Loc.t("Allow", "Разрешить")) { Task { await model.configurePasswordless(true) } }
            Button(SettingsText.cancel, role: .cancel) {}
        } message: {
            Text(KeepAwakeText.confirmHelp)
        }
        .alert(Loc.t("Could not change the permission", "Не удалось изменить разрешение"), isPresented: Binding(
            get: { model.permissionError != nil }, set: { if !$0 { model.permissionError = nil } }
        )) {
            Button("OK") { model.permissionError = nil }
        } message: {
            Text(KeepAwakeText.error(model.permissionError))
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }
}
