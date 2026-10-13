import AppKit
import ServiceManagement
import SwiftUI
import NotchCore

struct SettingsConnection: View {
    @ObservedObject var settings: AppSettings
    @State private var claude = false
    @State private var codex = false
    @State private var accessibility = false

    var body: some View {
        Form {
            Section {
                hook(.claude, installed: claude)
                hook(.codex, installed: codex)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(SettingsText.connectHelp)
                    Text(SettingsText.trust)
                }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                LabeledContent {
                    if accessibility { status(true, SettingsText.granted) }
                    else { Button(SettingsText.requestAccess) { AppActions.shared.askAccessibility() } }
                } label: { SettingsLabel(SettingsText.windowsAccess, hint: SettingsText.windowsAccessHelp) }
            }
            SettingsHiddenProjects(settings: settings)
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func hook(_ vendor: Vendor, installed: Bool) -> some View {
        LabeledContent(vendor == .claude ? SettingsText.claudeCode : SettingsText.codex) {
            HStack(spacing: 10) {
                if installed { status(true, SettingsText.connected) }
                Button(installed ? SettingsText.disconnect : SettingsText.connect) {
                    let sender = NSMenuItem()
                    sender.tag = vendor == .claude ? 0 : 1
                    AppActions.shared.toggleHooks(sender)
                    refresh()
                }
            }
        }
    }

    private func status(_ on: Bool, _ text: String) -> some View {
        Label { Text(text).foregroundStyle(.secondary) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green) }
    }

    private func refresh() {
        let installer = HookInstaller()
        claude = installer.isInstalled(.claude)
        codex = installer.isInstalled(.codex)
        accessibility = AXIsProcessTrusted()
    }
}

struct SettingsGeneral: View {
    @ObservedObject var settings: AppSettings
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Toggle(SettingsText.login, isOn: Binding(get: { settings.general.openAtLogin }, set: { on in
                    SettingsSystem.setLogin(on, settings: settings)
                    refreshLogin()
                })).toggleStyle(.switch)
                if loginStatus == .requiresApproval { Text(SettingsText.loginApproval).font(.caption).foregroundStyle(.secondary) }
            }
            SettingsKeepAwake()
            Section {
                LabeledContent {
                    Button(SettingsText.resetButton) { confirmReset = true }
                } label: { SettingsLabel(SettingsText.resetAll, hint: SettingsText.resetAllHelp) }
            }
            Section(SettingsText.about) {
                LabeledContent("Agents Notch", value: SettingsText.version + " " +
                               (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"))
                Text(SettingsText.license)
                Text(SettingsText.github).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(SettingsText.resetConfirm, isPresented: $confirmReset) {
            Button(SettingsText.resetConfirmButton, role: .destructive) {
                settings.resetAll()
                SettingsSystem.setLogin(false, settings: settings)
                refreshLogin()
            }
            Button(SettingsText.cancel, role: .cancel) {}
        }
        .onAppear { refreshLogin() }
        .onChange(of: settings.general.openAtLogin) { _, _ in refreshLogin() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshLogin() }
    }
    private func refreshLogin() {
        loginStatus = SMAppService.mainApp.status
        settings.general.openAtLogin = loginStatus == .enabled || loginStatus == .requiresApproval
    }
}

@MainActor
enum SettingsSystem {
    static func setLogin(_ on: Bool, settings: AppSettings) {
        let service = SMAppService.mainApp
        do {
            if on && service.status != .enabled { try service.register() }
            else if !on && service.status != .notRegistered { try service.unregister() }
        } catch {
            SoundPlayer.shared.play(.operationFailed, settings: settings)
            AppActions.say(SettingsText.operationFailed, error.localizedDescription)
        }
        settings.general.openAtLogin = service.status == .enabled || service.status == .requiresApproval
    }
}
