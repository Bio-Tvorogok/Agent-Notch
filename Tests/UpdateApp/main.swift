import AppKit
import SwiftUI

@MainActor
final class UpdateTestDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppUpdates.shared.start()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 320), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Agent Notch Update Test"
        window.contentView = NSHostingView(rootView: Form {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")
            SettingsUpdates()
            Button("Quit") { NSApp.terminate(nil) }
        }.formStyle(.grouped))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = MainActor.assumeIsolated { UpdateTestDelegate() }
app.delegate = delegate
app.run()
