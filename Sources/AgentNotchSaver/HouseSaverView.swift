import AppKit
import NotchCore
import ScreenSaver

/// The agents' house as a screen saver: the SpriteKit house (SaverSpriteHouse), fed from the snapshot the running app writes
/// (HouseSnapshot), polled every `poll` seconds. With "Require password immediately" it works as a live lock screen.
/// SpriteKit is the only renderer: when it cannot draw, the saver shows a plain dark frame.
///
/// Sonoma can retain views without calling stopAnimation. A real stop exits the legacy host; sustained invisibility
/// catches retained windows without reacting to presentation blips.
@objc(AgentNotchHouseView)
final class HouseSaverView: ScreenSaverView {
    static let poll: TimeInterval = 2

    /// The SpriteKit house; nil with `spriteFailed` set shows the plain dark frame.
    private var sprite: SaverSpriteHouse?
    private var spriteFailed = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let file = HouseSnapshot.url(home: HouseSnapshot.realHome)
    private var running = false
    private var activity = SaverActivity.State()

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screensaver.willstop"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        log("init \(isPreview ? "preview" : "screen") \(frame.size)")
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    deinit {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
    override func animateOneFrame() {}
    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()
    }

    override func startAnimation() {
        super.startAnimation()
        log("start")
        running = true
        activity = SaverActivity.State()
        _ = startSprite()
        timer?.invalidate()
        let t = Timer(timeInterval: Self.poll, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    override func stopAnimation() {
        super.stopAnimation()
        log("stop")
        saverWillStop()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Detachment can be temporary during display reconfiguration. The poll owns the grace period.
        if running { refresh() }
    }

    /// Called by stopAnimation or after sustained invisibility, never by a single window transition.
    private func saverWillStop() {
        log("willstop")
        tearDown()
        guard !isPreview, Bundle.main.bundleIdentifier?.contains("legacyScreenSaver") == true else { return }
        DispatchQueue.main.async {
            NSLog("agent-notch-house: exiting legacyScreenSaver after the saver stopped")
            exit(0)
        }
    }

    private var onScreen: Bool {
        SaverActivity.canDraw(running: running, attached: window != nil && !isHiddenOrHasHiddenAncestor,
                              visible: window?.isVisible == true, occluded: window?.occlusionState.contains(.visible) != true,
                              preview: isPreview, level: window?.level.rawValue ?? 0,
                              saverLevel: Int(CGWindowLevelForKey(.screenSaverWindow)))
    }

    private func tearDown() {
        running = false
        timer?.invalidate()
        timer = nil
        sprite?.setActive(false)
        sprite?.view.removeFromSuperview()
        sprite = nil
    }

    private func refresh() {
        guard running else { return }
        activity = SaverActivity.sample(activity, now: ProcessInfo.processInfo.systemUptime,
                                        running: running, visible: onScreen, preview: isPreview)
        if activity.exitHost { saverWillStop(); return }
        if sprite == nil { _ = startSprite() }
        refreshSprite(visible: activity.draw)
    }

    // MARK: SpriteKit

    private func snapshotNow() -> HouseSnapshot {
        let now = Date()
        return (try? Data(contentsOf: file)).flatMap { HouseSnapshot.decode($0, now: now) } ?? .empty(at: now)
    }

    /// Builds the SpriteKit house; false leaves the dark frame.
    private func startSprite() -> Bool {
        guard !spriteFailed, sprite == nil else { return sprite != nil }
        let snap = snapshotNow()
        guard !isPreview || bounds.width > 0,
              let atlas = Bundle(for: HouseSaverView.self).resourceURL?.appendingPathComponent("room/atlas", isDirectory: true),
              let house = SaverSpriteHouse(size: bounds.size, scale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2,
                                           atlas: atlas, snapshot: snap, onFailure: { [weak self] in MainActor.assumeIsolated { self?.spriteGaveUp() } })
        else {
            if !isPreview || bounds.width > 0 { spriteFailed = true; log("the SpriteKit house cannot draw, dark frame") }
            return false
        }
        house.view.autoresizingMask = [.width, .height]
        addSubview(house.view)
        sprite = house
        log("SpriteKit house")
        return true
    }

    private func refreshSprite(visible: Bool) {
        guard let sprite else { return }
        sprite.setActive(visible)
        guard visible else { return }
        sprite.apply(snapshotNow())
    }

    /// The atlas failed: the saver stays dark for the rest of this run.
    private func spriteGaveUp() {
        guard sprite != nil else { return }
        log("the SpriteKit house failed, dark frame")
        spriteFailed = true
        sprite?.setActive(false)
        sprite?.view.removeFromSuperview()
        sprite = nil
    }

    private func log(_ message: String) { NSLog("agent-notch-house: \(message)") }
}
