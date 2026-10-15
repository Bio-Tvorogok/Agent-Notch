import AppKit
import ServiceManagement
import SwiftUI
import NotchCore

struct SettingsConnection: View {
    @ObservedObject var settings: AppSettings
    var installer = HookInstaller()
    @State private var reports: [Vendor: ConnectionReport] = [:]
    @State private var results: [Vendor: Bool] = [:]
    @State private var testing: Set<Vendor> = []
    @State private var accessibility = false
    @State private var refreshing = false
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                hook(.claude)
                hook(.codex)
            } footer: {
                Text(SettingsText.connectHelp).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent {
                    if accessibility { status(SettingsText.granted) }
                    else { Button(SettingsText.requestAccess) { AppActions.shared.askAccessibility() } }
                } label: { SettingsLabel(SettingsText.windowsAccess, hint: SettingsText.windowsAccessHelp) }
            }
            SettingsHiddenProjects(settings: settings)
        }
        .onAppear { refresh() }
        .onReceive(timer) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func hook(_ vendor: Vendor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(vendor == .claude ? SettingsText.claudeCode : SettingsText.codex).fontWeight(.medium)
                Spacer()
                Button(reports[vendor]?.configWritten == true ? SettingsText.disconnect : SettingsText.connect) {
                    let sender = NSMenuItem()
                    sender.tag = vendor == .claude ? 0 : 1
                    AppActions.shared.toggleHooks(sender)
                    results[vendor] = nil
                    refresh()
                }
            }
            if let report = reports[vendor] {
                Text(report.status).foregroundStyle(report.missing == nil ? Color.green : Color.orange)
                Text(report.hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(report.steps.enumerated()), id: \.offset) { _, step in
                    HStack {
                        Text(step.0)
                        Spacer()
                        Text(step.1 ? Loc.t("Yes", "Да") : Loc.t("No", "Нет"))
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(Loc.t("Test request", "Тестовый запрос")) { test(vendor) }
                    .disabled(testing.contains(vendor))
                if testing.contains(vendor) { ProgressView().controlSize(.small) }
                if let result = results[vendor] {
                    Text(result ? Loc.t("Pass — helper reached the app", "Успех — помощник связался с приложением")
                         : Loc.t("Fail — reconnect and keep the app open", "Ошибка — переподключите и откройте приложение"))
                        .font(.caption).foregroundStyle(result ? Color.green : Color.orange)
                }
            }
        }.padding(.vertical, 4)
    }

    private func test(_ vendor: Vendor) {
        testing.insert(vendor)
        results[vendor] = nil
        let installer = installer
        Task {
            let passed = await Task.detached { ConnectionReport.testRequest(vendor, installer: installer) }.value
            results[vendor] = passed
            testing.remove(vendor)
            refresh()
        }
    }

    private func status(_ text: String) -> some View {
        Label { Text(text).foregroundStyle(.secondary) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green) }
    }

    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        accessibility = AXIsProcessTrusted()
        let installer = installer
        Task {
            reports = await Task.detached {
                Dictionary(uniqueKeysWithValues: [Vendor.claude, .codex].map { ($0, ConnectionReport.read($0, installer: installer)) })
            }.value
            refreshing = false
        }
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
