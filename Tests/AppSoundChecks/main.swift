import AppKit
import Foundation
import SwiftUI
import NotchCore

// These checks run against the app settings with an isolated suite, never the user's preferences.
@MainActor func checkSoundSettings() throws {
    let suite = "AgentsNotch.sound-checks." + UUID().uuidString
    guard let defaults = UserDefaults(suiteName: suite) else { fatalError("suite unavailable") }
    defer { defaults.removePersistentDomain(forName: suite) }
    func expect(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
    var legacy = BehaviorPrefs()
    legacy.soundName = "Ping"
    legacy.hiddenProjects = ["/hidden"]
    SettingsStorage.write(legacy, key: "behavior", in: defaults)
    defaults.set(false, forKey: "sounds")
    let settings = AppSettings(defaults: defaults)
    expect(!settings.sounds, "legacy mute was lost")
    expect(settings.soundEvents[.permissionRequested] == "Ping", "legacy sound was lost")
    expect(SoundEvent.allCases.filter { $0 != .permissionRequested }.allSatisfy { settings.soundEvents[$0].isEmpty }, "new events must start muted")
    settings.soundEvents[.agentFinished] = "Hero"
    settings.soundEvents[.permissionRequested] = ""
    settings.soundEvents.volume = 0.4
    let reloaded = AppSettings(defaults: defaults)
    expect(reloaded.soundEvents[.agentFinished] == "Hero", "finish sound didn't persist")
    expect(reloaded.soundEvents[.permissionRequested].isEmpty, "individual mute didn't persist")
    expect(reloaded.soundEvents.volume == 0.4, "volume didn't persist")
    expect(!reloaded.sounds, "global mute didn't persist")
    reloaded.applySoundPreset(.important)
    expect(!reloaded.sounds, "preset removed global mute")
    expect(reloaded.soundEvents.volume == 0.4, "preset changed volume")
    expect(reloaded.soundEvents[.agentFinished] == "Hero", "preset did not apply finish sound")
    expect(reloaded.soundPreset == .important, "applied preset was not recognized")
    let presetReloaded = AppSettings(defaults: defaults)
    expect(presetReloaded.soundPreset == .important, "preset did not survive reload")
    presetReloaded.soundEvents[.cardOpened] = "Frog"
    expect(presetReloaded.soundPreset == nil, "manual change did not become custom")
    presetReloaded.applySoundPreset(.requestsOnly)
    expect(presetReloaded.soundEvents[.cardOpened].isEmpty, "preset retained custom event")
    expect(presetReloaded.soundEvents.volume == 0.4, "switching preset changed volume")
    reloaded.resetAll()
    expect(reloaded.soundEvents[.permissionRequested] == "Glass", "reset lost the request default")
    expect(reloaded.soundEvents[.agentFinished].isEmpty, "reset enabled a new event")
    expect(reloaded.behavior.hiddenProjects == ["/hidden"], "reset lost hidden projects")
    for name in SoundPrefs.names {
        expect(NSSound(named: NSSound.Name(name)) != nil, "system sound unavailable: " + name)
    }
    reloaded.sounds = false
    expect(SoundPlayer.shared.preview("Glass", volume: 0.15), "preview rejected a sound while globally muted")
    expect(NSSound(named: NSSound.Name("Glass"))?.isPlaying == true, "preview didn't start actual playback")
    SoundPlayer.shared.stop()
    expect(NSSound(named: NSSound.Name("Glass"))?.isPlaying == false, "playback didn't stop")
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent("notch-import-" + UUID().uuidString)
    try files.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: root) }
    let libraryDirectory = root.appendingPathComponent("library")
    let source = root.appendingPathComponent("My bell.aiff")
    try files.copyItem(at: URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff"), to: source)
    let customSettings = AppSettings(defaults: defaults, soundLibraryDirectory: libraryDirectory)
    customSettings.sounds = false
    customSettings.soundEvents.volume = 0.4
    let imported = try customSettings.importSound(source)
    expect(customSettings.customSounds == [imported], "imported sound did not appear in the library")
    expect(!customSettings.sounds && customSettings.soundEvents.volume == 0.4, "import changed mute or volume")
    customSettings.soundEvents[.agentFinished] = imported.id
    expect(customSettings.soundPreset == nil, "custom file did not become a custom sound set")
    try files.removeItem(at: source)
    let customReloaded = AppSettings(defaults: defaults, soundLibraryDirectory: libraryDirectory)
    expect(customReloaded.soundEvents[.agentFinished] == imported.id, "custom assignment did not persist")
    expect(customReloaded.customSounds == [imported], "library did not survive restart")
    expect(SoundPlayer.shared.preview(imported.id, volume: 0.15, library: customReloaded.soundLibrary), "custom preview did not start actual playback")
    SoundPlayer.shared.stop()
    let invalid = root.appendingPathComponent("broken.wav")
    try Data("not audio".utf8).write(to: invalid)
    do { _ = try customReloaded.importSound(invalid); fatalError("invalid audio was imported") } catch {}
    expect(customReloaded.customSounds == [imported], "failed import changed library")
    let fixtureDirectory = URL(fileURLWithPath: "/private/tmp/notch-custom-audio-fixtures")
    for ext in ["wav", "mp3", "m4a"] {
        let fixture = fixtureDirectory.appendingPathComponent("Quiet bell." + ext)
        if files.fileExists(atPath: fixture.path) {
            let format = try customReloaded.importSound(fixture)
            expect(SoundPlayer.shared.preview(format.id, volume: 0.15, library: customReloaded.soundLibrary), "real format playback failed: " + ext)
            SoundPlayer.shared.stop()
            try customReloaded.removeCustomSound(format.id)
        }
    }
    customReloaded.applySoundPreset(.attention)
    expect(customReloaded.customSounds == [imported], "preset deleted library")
    customReloaded.resetAll()
    expect(customReloaded.customSounds == [imported], "reset deleted imported files")
    customReloaded.sounds = false
    customReloaded.soundEvents[.permissionRequested] = imported.id
    customReloaded.soundEvents[.agentFinished] = imported.id
    customReloaded.soundEvents[.agentError] = "Basso"
    try customReloaded.removeCustomSound(imported.id)
    expect(customReloaded.customSounds.isEmpty, "removed sound remained in library")
    expect(customReloaded.soundEvents[.permissionRequested].isEmpty && customReloaded.soundEvents[.agentFinished].isEmpty, "removed sound assignments were retained")
    expect(customReloaded.soundEvents[.agentError] == "Basso", "remove changed another event")
    expect(!SoundPlayer.shared.preview(imported.id, volume: 0.15, library: customReloaded.soundLibrary), "removed sound still plays")
    print("OK app sound settings: migration, mute, presets, custom edits, persistence, reset, 14 assets, actual preview playback, custom imports, restart, invalid files, removal")
}

@MainActor final class SoundSmokeCloser: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}

@MainActor func showSoundSmokeWindow() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.regular)
    Loc.forced = .ru
    let defaults = UserDefaults(suiteName: "AgentsNotch.custom-sounds-ui-checks")!
    let settings = AppSettings(defaults: defaults,
        soundLibraryDirectory: URL(fileURLWithPath: "/private/tmp/notch-custom-sounds-ui-library"))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 640),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "Sound library QA"
    window.contentView = NSHostingView(rootView: SettingsView(selection: .sounds)
        .environmentObject(settings).environment(\.colorScheme, .light))
    window.appearance = NSAppearance(named: .aqua)
    let closer = SoundSmokeCloser()
    window.delegate = closer
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    withExtendedLifetime(closer) { NSApp.run() }
}

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--ui-smoke") || Bundle.main.bundleIdentifier == "com.forichok.agents-notch.sound-qa" {
        showSoundSmokeWindow()
    } else {
        try! checkSoundSettings()
    }
}
