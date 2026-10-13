import AppKit
import NotchCore

/// One queue keeps bursts of events from playing over each other.
@MainActor
final class SoundPlayer: NSObject, NSSoundDelegate {
    static let shared = SoundPlayer()
    private struct Clip { let name: String; let volume: Float }
    private var queued: [Clip] = []
    private var current: NSSound?

    func play(_ event: SoundEvent, settings: AppSettings? = nil) {
        let settings = settings ?? .shared
        guard settings.sounds else { return }
        enqueue(settings.soundEvents[event], volume: settings.soundEvents.volume)
    }

    /// Listening is deliberate: it works even when automatic sounds are switched off.
    @discardableResult func preview(_ name: String, volume: Double) -> Bool {
        stop()
        return enqueue(name, volume: volume)
    }

    func stop() {
        queued.removeAll()
        current?.delegate = nil
        current?.stop()
        current = nil
    }

    @discardableResult private func enqueue(_ name: String, volume: Double) -> Bool {
        guard !name.isEmpty, SoundPrefs.names.contains(name), volume > 0 else { return false }
        queued.append(Clip(name: name, volume: Float(volume)))
        next()
        return true
    }

    private func next() {
        guard current == nil, !queued.isEmpty else { return }
        let clip = queued.removeFirst()
        guard let sound = NSSound(named: NSSound.Name(clip.name)) else { next(); return }
        current = sound
        sound.volume = clip.volume
        sound.delegate = self
        if !sound.play() { current = nil; next() }
    }

    nonisolated func sound(_ sound: NSSound, didFinishPlaying finished: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.current === sound else { return }
            self.current = nil
            self.next()
        }
    }
}
