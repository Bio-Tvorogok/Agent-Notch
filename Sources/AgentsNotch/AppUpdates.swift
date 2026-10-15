import AppKit
import Combine
import Sparkle
import NotchCore

/// Both entry points use the same manual update session.
@MainActor
final class AppUpdates: NSObject, ObservableObject, NSMenuItemValidation {
    static let shared = AppUpdates()
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var errorMessage: String?
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []

    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        // Override preferences from builds that allowed background checks before starting.
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
        do {
            try updater.start()
            canCheckForUpdates = updater.canCheckForUpdates
            observations = [
                updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
                    MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
                }
            ]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @objc func checkForUpdates(_ sender: Any? = nil) {
        guard canCheckForUpdates else { return }
        controller?.checkForUpdates(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { canCheckForUpdates }
}

enum UpdateText {
    static var title: String { Loc.t("Updates", "Обновления") }
    static var check: String { Loc.t("Check for Updates…", "Проверить обновления…") }
    static var help: String { Loc.t("Updates are checked only when you press this button. Downloading and installing require your confirmation.",
                                   "Обновления проверяются только по этой кнопке. Загрузка и установка — с вашим подтверждением.") }
}
