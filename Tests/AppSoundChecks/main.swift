import AppKit
import Foundation
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
    print("OK app sound settings: migration, mute, persistence, reset, 14 assets, actual preview playback")
}

MainActor.assumeIsolated { try! checkSoundSettings() }
