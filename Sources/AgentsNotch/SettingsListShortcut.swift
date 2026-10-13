import AppKit
import Combine

/// A nonactivating list needs a global registration to receive ⌘, from the frontmost app.
@MainActor
final class SettingsListShortcut {
    private var keys: SettingsCommandKey?
    private var recording: AnyCancellable?
    private var local: Any?

    init(panel: NSPanel) {
        recording = AppSettings.shared.$isRecordingShortcut.sink { [weak self, weak panel] active in
            self?.keys = nil
            if !active {
                self?.keys = SettingsCommandKey { [weak panel] in
                    guard panel?.isVisible == true else { return }
                    SettingsWindow.shared.show()
                }
            }
        }
        local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
            guard panel?.isVisible == true, !AppSettings.shared.isRecordingShortcut, event.keyCode == 43,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command else { return event }
            MainActor.assumeIsolated { SettingsWindow.shared.show() }
            return nil
        }
    }

    deinit { if let local { NSEvent.removeMonitor(local) } }
}
