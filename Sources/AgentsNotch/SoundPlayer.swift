import AppKit
import NotchCore

/// One queue keeps bursts of events from playing over each other.
@MainActor
final class SoundPlayer: NSObject, NSSoundDelegate {
    static let shared = SoundPlayer()
    private struct Clip { let sound: NSSound; let volume: Float }
    private var queued: [Clip] = []
    private var current: NSSound?

    func play(_ event: SoundEvent, settings: AppSettings? = nil) {
        let settings = settings ?? .shared
        guard settings.sounds else { return }
        enqueue(settings.soundEvents[event], volume: settings.soundEvents.volume, library: settings.soundLibrary)
    }

    /// Listening is deliberate: it works even when automatic sounds are switched off.
    @discardableResult func preview(_ name: String, volume: Double, library: SoundLibrary? = nil) -> Bool {
        stop()
        return enqueue(name, volume: volume, library: library ?? AppSettings.shared.soundLibrary)
    }

    func stop() {
        queued.removeAll()
        current?.delegate = nil
        current?.stop()
        current = nil
    }

    @discardableResult private func enqueue(_ name: String, volume: Double, library: SoundLibrary) -> Bool {
        guard !name.isEmpty, volume.isFinite, volume > 0 else { return false }
        let sound: NSSound?
        if SoundPrefs.names.contains(name) {
            sound = NSSound(named: NSSound.Name(name))
        } else {
            sound = library.url(for: name).flatMap { NSSound(contentsOf: $0, byReference: false) }
        }
        guard let sound else { return false }
        queued.append(Clip(sound: sound, volume: Float(min(1, volume))))
        return next()
    }

    @discardableResult private func next() -> Bool {
        if current != nil { return true }
        guard !queued.isEmpty else { return false }
        let clip = queued.removeFirst()
        let sound = clip.sound
        current = sound
        sound.volume = clip.volume
        sound.delegate = self
        if sound.play() { return true }
        sound.delegate = nil
        current = nil
        return next()
    }

    nonisolated func sound(_ sound: NSSound, didFinishPlaying finished: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.current === sound else { return }
            self.current = nil
            self.next()
        }
    }
}
