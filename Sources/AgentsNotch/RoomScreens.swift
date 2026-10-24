import AppKit
import Combine
import NotchCore
import SpriteKit

/// The house settings reaching a running wallpaper, and the windows on the other screens.
extension RoomWallpaper {
    /// Called from start(): layout and rooms go to the page, the frame rate to every window, the screens get their windows.
    func observeRoomSettings() {
        settingsSubs.removeAll()
        AppSettings.shared.$room
            .removeDuplicates()
            .receive(on: RunLoop.main) // after the change is stored, so syncPower reads the new frame rate
            .sink { [weak self] prefs in
                self?.pushRoomConfig(prefs)
                self?.syncPower()
                self?.syncScreens()
            }
            .store(in: &settingsSubs)
    }

    /// `room.configure({layout, themes})`: the page re-lays out and rebuilds only the rooms whose theme changed.
    func pushRoomConfig(_ prefs: RoomPrefs? = nil) {
        let prefs = prefs ?? AppSettings.shared.room
        web?.evaluateJavaScript("window.room && room.configure && room.configure(\(prefs.pageConfig)); true")
    }

    /// One window on every screen but the main one when «Все экраны» is on; follows screens coming, going and moving.
    func syncScreens() {
        guard isRunning, let page = Self.page else { removeExtras(keepSettings: true); return }
        let others = AppSettings.shared.room.screens == .all ? Array(NSScreen.screens.dropFirst()) : []
        var keep: Set<CGDirectDisplayID> = []
        for screen in others {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            keep.insert(id)
            if let extra = extras[id] { extra.place(on: screen) } else if let extra = RoomExtraScreen(screen: screen, page: page, fps: Self.fps, awake: houseAwake) {
                extra.onGiveUp = { [weak self] in self?.extras[id] = nil }
                extras[id] = extra
            }
        }
        for (id, extra) in extras where !keep.contains(id) { extra.close(); extras[id] = nil }
    }

    func removeExtras(keepSettings: Bool = false) {
        extras.values.forEach { $0.close() }
        extras.removeAll()
        if !keepSettings { settingsSubs.removeAll() }
    }
}

/// A screen next to the main one: the sky, the city and a few floating islands drawn by SpriteKit (HouseScene2.extraScreen) from the atlas.
/// It stops drawing whenever its own screen is covered. When the atlas cannot be drawn on a screen it gets no window (the desktop picture shows).
@MainActor
final class RoomExtraScreen: NSObject {
    private let window: NSWindow
    private let view: SKView
    private let page: URL
    private var subs: Set<AnyCancellable> = []
    private var fps: Int
    private var sentActive: Bool?
    private var awake: Bool

    private static func atlasDir(_ page: URL) -> URL { page.deletingLastPathComponent().appendingPathComponent("atlas") }

    /// The scene of an extra screen, nil when this atlas or screen cannot draw it.
    private static func makeScene(for screen: NSScreen, page: URL, onGiveUp: @escaping () -> Void) -> HouseScene2? {
        let size = screen.frame.size, dpr = Double(screen.backingScaleFactor)
        let layout = HouseLayout.extraScreen(canvas: .init(width: Double(size.width), height: Double(size.height), dpr: dpr))
        let env = HouseSkyEnv(innerHeight: Double(size.height), insetBottom: 0)
        guard HousePainter.groundRaw(layout: layout, env: env) >= 0,
              let scene = HouseScene2.load(from: atlasDir(page), layout: layout, unit: CGFloat(layout.view.PXD / layout.view.DPR), size: size),
              scene.parts.islets?.isEmpty == false else { return nil }
        scene.extraScreen = true
        scene.env = env
        scene.followClock = true
        let giveUp: () -> Void = { DispatchQueue.main.async { MainActor.assumeIsolated { onGiveUp() } } }
        scene.onFailure = giveUp
        scene.onStall = giveUp
        return scene
    }

    init?(screen: NSScreen, page: URL, fps: Int, awake: Bool) {
        self.page = page
        self.fps = fps
        self.awake = awake
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        w.canHide = false
        w.isRestorable = false
        w.ignoresMouseEvents = true
        w.isOpaque = true
        w.backgroundColor = .black
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        let view = SKView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.ignoresSiblingOrder = true
        view.autoresizingMask = [.width, .height]
        window = w
        self.view = view
        super.init()
        guard let scene = Self.makeScene(for: screen, page: page, onGiveUp: { [weak self] in self?.giveUp() }) else { return nil }
        view.preferredFramesPerSecond = fps
        w.contentView = view
        view.presentScene(scene)
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: w)
            .sink { [weak self] _ in self?.syncPower() }
            .store(in: &subs)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                guard let w = self?.window, !w.isOnActiveSpace else { return }
                w.orderFrontRegardless()
            }
            .store(in: &subs)
        syncPower()
    }

    /// The atlas failed or stalled on this screen: its window goes away (the next syncScreens makes it again, from a fresh scene).
    var onGiveUp: (() -> Void)?
    private func giveUp() {
        NSLog("agents-notch: an extra screen leaves the SpriteKit house")
        close()
        onGiveUp?()
    }

    func place(on screen: NSScreen) {
        guard window.frame != screen.frame else { return }
        window.setFrame(screen.frame, display: true)
        // a new canvas: the layout is made again for the new size
        guard let scene = Self.makeScene(for: screen, page: page, onGiveUp: { [weak self] in self?.giveUp() }) else { giveUp(); return }
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        view.presentScene(scene)
        sentActive = nil
        syncPower()
    }

    func sync(fps: Int, awake: Bool) {
        self.fps = fps
        self.awake = awake
        syncPower()
    }

    /// Swift's agent snapshot changed; this screen also checks its own visibility.
    func sync(awake: Bool) {
        self.awake = awake
        syncPower()
    }

    private func syncPower() {
        guard let scene = view.scene as? HouseScene2 else { return }
        scene.maxFps = fps
        let animate = RoomActivity.isActive(visible: window.occlusionState.contains(.visible), awake: awake)
        if animate != sentActive { sentActive = animate; if animate { scene.wake() } else { scene.hide() } }
    }

    func close() {
        subs.removeAll()
        view.presentScene(nil)
        view.isPaused = true
        window.orderOut(nil)
        window.contentView = nil
    }
}
