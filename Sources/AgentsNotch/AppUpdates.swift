import AppKit
import Combine
import Sparkle
import NotchCore

/// One updater for both entry points. Sparkle owns persistence, scheduling and installation.
@MainActor
final class AppUpdates: NSObject, ObservableObject, NSMenuItemValidation {
    static let shared = AppUpdates()
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticChecks = true
    @Published private(set) var errorMessage: String?
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []

    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        do {
            try updater.start()
            // The product only checks in the background; downloading always requires a click.
            updater.automaticallyDownloadsUpdates = false
            updater.updateCheckInterval = 86400
            automaticChecks = updater.automaticallyChecksForUpdates
            canCheckForUpdates = updater.canCheckForUpdates
            observations = [
                updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
                    MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
                },
                updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] updater, _ in
                    MainActor.assumeIsolated { self?.automaticChecks = updater.automaticallyChecksForUpdates }
                }
            ]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard let updater = controller?.updater, errorMessage == nil else { return }
        updater.automaticallyChecksForUpdates = enabled
        automaticChecks = updater.automaticallyChecksForUpdates
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
    static var automatic: String { Loc.t("Automatically check for updates", "Проверять обновления автоматически") }
    static var help: String { Loc.t("Checks once a day. Updates are downloaded and installed after you choose Update.",
                                   "Проверка раз в сутки. Загрузка и установка — после нажатия «Обновить».") }
}
