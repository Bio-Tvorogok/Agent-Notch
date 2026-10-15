import SwiftUI

struct SettingsUpdates: View {
    @ObservedObject private var updates = AppUpdates.shared

    var body: some View {
        Section {
            Toggle(UpdateText.automatic, isOn: Binding(get: { updates.automaticChecks }, set: { updates.setAutomaticChecks($0) }))
                .toggleStyle(.switch)
                .disabled(updates.errorMessage != nil)
            Button(UpdateText.check) { updates.checkForUpdates() }
                .disabled(!updates.canCheckForUpdates)
            if let error = updates.errorMessage {
                Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        } header: {
            Text(UpdateText.title)
        } footer: {
            Text(UpdateText.help)
        }
    }
}
