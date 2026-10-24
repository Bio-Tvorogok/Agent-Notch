import AppKit
import Combine
import IOKit.ps
import NotchCore
import SpriteKit
import SwiftUI

/// The agents' house as the desktop wallpaper: the SpriteKit house (HouseScene2, drawn from room/atlas) in a window just above the
/// desktop picture. SpriteKit is the only renderer. The window never takes the mouse, so the desktop icons keep working; hover and
/// clicks on bare desktop are forwarded to the scene, and a click on a Clawd opens that agent's chat.
@MainActor
final class RoomWallpaper: NSObject {
    private let store: Store
    private var window: NSWindow?
    private var house: SKView?
    /// What the running SpriteKit house was built from: the screen's numbers and the project list (see skGeometry).
    private var skBuilt: [Double] = []
    private var skPrefs = RoomPrefs()
    private var skBehaviour: HouseBehaviour?
    /// The one growth count (see HouseScene2Growth.swift).
    private let growth: HouseGrowthStore = { let g = HouseGrowthStore(); g.importLegacyPage(); return g }()
    /// Set when the atlas failed to draw: the wallpaper stays off until the app restarts (there is no other renderer to fall back to).
    private var atlasBroken = false
    /// Set when the current screen cannot hold the house (too short for the Dock's inset): cleared when the screen changes.
    private var screenBlocked = false
    /// The screen geometry that was too short for the SpriteKit house: only another one is tried again.
    private var blockedGeometry: [Double]?
    /// Texture preload stalls this session; the second one turns the wallpaper off.
    private var skStalls = 0
    private var rendererSubs: Set<AnyCancellable> = []
    private var subs: Set<AnyCancellable> = []
    private var monitor: Any?
    private var pinchTap: CFMachPort?
    /// The last pinch line logged: a change (the permission granted later) is logged again.
    private var pinchLine = ""
    /// Set while the one-time hint is the card on screen; any other card or a hide clears it, so the timer never hides someone else's.
    private var hintToken: UUID?
    private var lastJSON = ""
    private var lastMove = 0.0
    private var hovering = false
    private var desktopHitTargets: Set<Int> = []
    private let tip = RoomTip()
    private let note = RoomNote()
    private var powerTimer: Timer?
    private var sentActive: Bool?
    /// The other screens' windows (see RoomScreens.swift) and where a click started.
    var extras: [CGDirectDisplayID: RoomExtraScreen] = [:]
    var settingsSubs: Set<AnyCancellable> = []
    private var pressed: (NSPoint, Double)?
    private let info = RoomInfoFeed()
    private var activity = RoomActivity()
    private var activityTimer: Timer?
    var houseAwake: Bool { activity.awake(at: CACurrentMediaTime()) }

    init(store: Store) { self.store = store }

    var isRunning: Bool { window != nil }

    func start() {
        guard window == nil, !atlasBroken else { return }
        guard let atlas = Self.atlasDirectory else { NSLog("agents-notch: room/atlas not found"); return }
        guard let screen = NSScreen.screens.first else { return }

        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        w.canHide = false
        w.isRestorable = false
        w.displaysWhenScreenProfileChanges = true
        w.ignoresMouseEvents = true
        w.isOpaque = true
        w.backgroundColor = .black
        w.hasShadow = false
        w.isReleasedWhenClosed = false

        observeRenderer()
        if startSpriteKit(in: w, atlas: atlas, screen: screen) { return }
        if skFailedOnScreen {
            screenBlocked = true; blockedGeometry = skGeometry(of: screen)
            NSLog("agents-notch: this screen cannot hold the house, trying again when the screen changes")
        } else {
            atlasBroken = true
            NSLog("agents-notch: no usable house atlas in \(atlas.path), the house stays off")
        }
    }

    /// The window ignores the mouse, so the house reads the pointer, trackpad and Esc through a global monitor and the pinch tap
    /// (startSpriteKit must call it; scripts/test-pointer-wiring.sh).
    private func startPointer() {
        guard monitor == nil else { return }
        refreshDesktopHitTargets()
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] note in
                guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == "com.apple.finder" else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refreshDesktopHitTargets() }
            }
            .store(in: &subs)
        NotificationCenter.default.publisher(for: Self.pinchPermissionChanged)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
            .sink { [weak self] _ in self?.startPinchTap() }
            .store(in: &subs)
        startPinchTap()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseUp, .smartMagnify, .scrollWheel, .keyDown]) { [weak self] e in
            let type = e.type
            // Esc on the desktop goes back to the overview; macOS only delivers keys here with Accessibility access
            if type == .keyDown {
                guard e.keyCode == 53, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return }
                MainActor.assumeIsolated {
                    (self?.house?.scene as? HouseScene2)?.resetView()
                }
                return
            }
            let scroll = type == .scrollWheel && e.hasPreciseScrollingDeltas ? (e.scrollingDeltaX, e.scrollingDeltaY) : (0, 0)
            let target = e.windowNumber
            MainActor.assumeIsolated { self?.mouse(type, scroll: scroll, target: target) }
        }
    }

    static let pinchPermissionChanged = Notification.Name("AgentsNotch.housePinchPermissionChanged")

    /// A global monitor is never sent trackpad pinches (they go to the app under the cursor, Finder on the desktop),
    /// so they are read from a listen-only event tap after Input Monitoring has already been granted.
    /// Only Settings' explicit enable action requests access. A denied tap has no polling timer.
    private func startPinchTap() {
        let allowed = CGPreflightListenEventAccess()
        guard allowed else {
            stopPinchTap()
            logPinch(HousePinch.statusLine(allowed: false, created: nil))
            return
        }
        guard pinchTap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, ref in
            guard let ref else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<RoomWallpaper>.fromOpaque(ref).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                MainActor.assumeIsolated { if let tap = me.pinchTap { CGEvent.tapEnable(tap: tap, enable: true) } }
            } else if let e = NSEvent(cgEvent: event), e.type == .magnify {
                let m = e.magnification
                MainActor.assumeIsolated { me.mouse(.magnify, magnify: m) }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: CGEventMask(1) << 29 | CGEventMask(1) << CGEventMask(NSEvent.EventType.magnify.rawValue), // pinches come as gesture events (29)
                                          callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { logPinch(HousePinch.statusLine(allowed: true, created: false)); return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        pinchTap = tap
        logPinch(HousePinch.statusLine(allowed: true, created: true, enabled: CGEvent.tapIsEnabled(tap: tap)))
    }

    private func logPinch(_ line: String) {
        guard line != pinchLine else { return }
        pinchLine = line
        NSLog("%@", line)
    }

    private func stopPinchTap() {
        if let pinchTap { CGEvent.tapEnable(tap: pinchTap, enable: false); CFMachPortInvalidate(pinchTap) }
        pinchTap = nil
    }

    // MARK: SpriteKit house

    /// The numbers the SpriteKit layout is built from: screen size, scale, and the menu bar, Dock and icon-column insets.
    private func skGeometry(of screen: NSScreen) -> [Double] {
        let icons = UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "CreateDesktop") as? Bool ?? true
        return [screen.frame.width, screen.frame.height, screen.backingScaleFactor, screen.frame.maxY - screen.visibleFrame.maxY,
                screen.visibleFrame.minY - screen.frame.minY, icons ? 120 : 0]
    }

    /// The season of the running scene's atlas (the yard art is baked into the atlas, so a new season needs a new scene).
    private var skSeason = "autumn"

    /// True when the last makeSKScene failed because of the screen, not the atlas.
    private var skFailedOnScreen = false

    /// A scene and its behaviour for this screen: the behaviour starts from the stored growth and the agents now on the desk, and the
    /// scene is laid out as the behaviour is (the projects of those agents). nil when the atlas or the screen cannot draw it.
    private func makeSKScene(screen: NSScreen, atlas: URL, prefs: RoomPrefs) -> HouseScene2? {
        skFailedOnScreen = false
        let g = skGeometry(of: screen)
        let themes = prefs.themes.filter { RoomTheme(rawValue: $0.value) != nil }.map { HouseLayout.ThemeChoice(project: $0.key, theme: $0.value) }
        let behaviour = HouseBehaviour(seed: UInt32.random(in: 1...UInt32.max), layout: HouseLayout.Style(rawValue: prefs.layout.rawValue) ?? .islands, canvas: .init(width: g[0], height: g[1], dpr: g[2]),
                                       insets: .init(top: g[3], bottom: g[4], right: g[5]), themes: themes)
        growth.seed(behaviour)
        if let rows = currentRows() { behaviour.setAgents(rows); growth.capture(from: behaviour) }
        let env = HouseSkyEnv(innerHeight: g[1], insetBottom: g[4])
        guard HousePainter.groundRaw(layout: behaviour.layout, env: env) >= 0 else {
            NSLog("agents-notch: screen too short for the SpriteKit house"); skFailedOnScreen = true; return nil
        }
        let unit = CGFloat(behaviour.layout.view.PXD / behaviour.layout.view.DPR)
        let season = HouseScene2.seasonOf(month0: Calendar.current.component(.month, from: Date()) - 1)
        guard let scene = HouseScene2.load(from: HouseScene2.atlasDir(atlas, season: season), layout: behaviour.layout, unit: unit, size: screen.frame.size) else { return nil }
        scene.setSeason(season); skSeason = season
        scene.env = env
        scene.attach(behaviour)
        if let why = scene.missingParts() { NSLog("agents-notch: the atlas has no \(why)"); return nil }
        scene.followClock = true
        scene.onFailure = { [weak self] in DispatchQueue.main.async { MainActor.assumeIsolated { self?.leave("the atlas failed to draw", screen: false) } } }
        scene.onStall = { [weak self] in DispatchQueue.main.async { MainActor.assumeIsolated {
            guard let self else { return }
            self.skStalls += 1
            if self.skStalls > 1 { self.leave("the atlas stalled twice", screen: false) } else { NSLog("agents-notch: the textures stalled, trying again"); self.restart() }
        } } }
        // the pointer: the view of the window and what the hover card and a click do (HouseScene2Pointer.swift)
        scene.installCamera(HouseCamera(layout: behaviour.layout, innerWidth: g[0], innerHeight: g[1], insets: .init(top: g[3], bottom: g[4], right: g[5])))
        scene.onTip = { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hintToken = nil
                if let t, let w = self.window { self.tip.show(t.payload, in: w.frame) } else { self.tip.hide() }
            }
        }
        scene.onEggCard = { [weak self] text, x, y in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let text, let w = self.window { self.note.show(text, x: x, y: y, in: w.frame) } else { self.note.hide() }
            }
        }
        scene.onOpen = { [weak self] id in
            MainActor.assumeIsolated { if let self, let agent = self.store.shown.first(where: { $0.id == id }) { self.store.open(agent) } }
        }
        scene.onDelivered = { [weak self, weak behaviour] in
            guard let self, let behaviour else { return }
            self.growth.capture(from: behaviour)
        }
        skBuilt = g; skPrefs = prefs; skBehaviour = behaviour
        return scene
    }

    /// The agents as the house gets them (`Self.rows`), decoded for the behaviour.
    private func currentRows() -> [HouseAgentRow]? {
        let agents = store.shown
        info.track(agents)
        return try? JSONDecoder().decode([HouseAgentRow].self, from: Data(Self.rows(agents, contexts: info.contexts).utf8))
    }

    /// The house composed from room/atlas/parts.json by HouseScene2: one room per project the agents work in, the sky by the hour;
    /// screens, Spaces and settings are followed.
    private func startSpriteKit(in w: NSWindow, atlas: URL, screen: NSScreen) -> Bool {
        let prefs = AppSettings.shared.room
        guard let scene = makeSKScene(screen: screen, atlas: atlas, prefs: prefs) else { return false }
        let view = SKView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = Self.fps
        w.contentView = view
        view.presentScene(scene)
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        window = w
        house = view
        syncPower()
        startPointer()
        syncHouseActivity(working: store.shown.contains { $0.state == .working }, changed: true)
        observeRoomSettings()
        lastJSON = Self.rows(store.shown, contexts: info.contexts)
        info.start(store: store, changed: { [weak self] in self?.skPush() }, send: { _ in })
        store.objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.skPush() }
            .store(in: &subs)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                self?.refreshDesktopHitTargets()
                guard let w = self?.window, !w.isOnActiveSpace else { return }
                w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
                w.orderFrontRegardless()
            }
            .store(in: &subs)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.fitScreen() }
            .store(in: &subs)
        NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: w)
            .merge(with: NotificationCenter.default.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main))
            .sink { [weak self] _ in self?.syncPower() }
            .store(in: &subs)
        powerTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncPower(); self?.checkRenderer() }
        }
        return true
    }

    /// The agents as the house's behaviour takes them, only when they changed .
    private func skPush() {
        let agents = store.shown
        info.track(agents)
        let json = Self.rows(agents, contexts: info.contexts)
        syncHouseActivity(working: agents.contains { $0.state == .working }, changed: json != lastJSON)
        guard json != lastJSON, let scene = house?.scene as? HouseScene2,
              let rows = try? JSONDecoder().decode([HouseAgentRow].self, from: Data(json.utf8)) else { return }
        lastJSON = json
        scene.deliver(rows)
    }

    /// The screen changed (size, scale, menu bar, Dock, icons, arrangement): the window follows and the house is laid out again.
    private func skFitScreen() {
        guard let screen = NSScreen.screens.first, let view = house, let atlas = Self.atlasDirectory else { return }
        guard skGeometry(of: screen) != skBuilt else { return }
        guard let scene = makeSKScene(screen: screen, atlas: atlas, prefs: AppSettings.shared.room) else {
            leave("the new screen cannot be drawn", screen: skFailedOnScreen); return
        }
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        tip.hide(); hovering = false; hintToken = nil // a card from the old scene would stay up
        view.presentScene(scene)
        sentActive = nil
        syncPower()
    }

    /// Theme choices are fixed when the behaviour is made, so a change lays the rooms out again.
    private func rendererSettingsChanged(_ prefs: RoomPrefs) {
        guard isRunning, house != nil, prefs.themes != skPrefs.themes || prefs.layout != skPrefs.layout else { return }
        restart()
    }

    /// The 20 s tick: the month can leave the atlas's season while the house runs.
    private func checkRenderer() {
        guard house != nil else { return }
        if HouseScene2.seasonOf(month0: Calendar.current.component(.month, from: Date()) - 1) != skSeason { restart() }
    }

    private func observeRenderer() {
        guard rendererSubs.isEmpty else { return }
        AppSettings.shared.$room
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] prefs in self?.rendererSettingsChanged(prefs) }
            .store(in: &rendererSubs)
        // the house was kept off only because the last screen was too small: another one may do
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, window == nil, screenBlocked, let screen = NSScreen.screens.first, skGeometry(of: screen) != blockedGeometry else { return }
                screenBlocked = false
                start()
            }
            .store(in: &rendererSubs)
    }

    /// The house turns off: the screen cannot hold it (tried again when the screen changes) or the atlas is at fault (for good).
    private func leave(_ why: String, screen: Bool) {
        guard house != nil else { return }
        NSLog("agents-notch: leaving the house: \(why)")
        let geometry = NSScreen.screens.first.map { skGeometry(of: $0) }
        stop()
        if screen { screenBlocked = true; blockedGeometry = geometry } else { atlasBroken = true }
    }

    private func restart() {
        stop()
        start()
    }

    func stop() {
        activityTimer?.invalidate()
        activityTimer = nil
        activity = RoomActivity()
        powerTimer?.invalidate()
        powerTimer = nil
        sentActive = nil
        screenBlocked = false
        blockedGeometry = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        stopPinchTap()
        subs.removeAll()
        removeExtras()
        info.stop()
        window?.orderOut(nil)
        window = nil
        house?.presentScene(nil)
        house = nil
        skBehaviour = nil
        tip.hide()
        lastJSON = ""
    }

    func syncPower() {
        guard let house, let w = window, let scene = house.scene as? HouseScene2 else { return }
        // covered: nothing drawn; on battery or in Low Power Mode: 30 fps at most
        scene.maxFps = Self.fps
        let visible = w.occlusionState.contains(.visible)
        if visible != sentActive { sentActive = visible; if visible { scene.wake() } else { scene.hide() } }
        extras.values.forEach { $0.sync(fps: Self.fps, awake: houseAwake) }
    }

    static var fps: Int { AppSettings.shared.room.fps(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, onBattery: onBattery) }

    private static var onBattery: Bool {
        guard let type = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPMBatteryPowerKey
    }

    private func fitScreen() {
        guard let w = window, let screen = NSScreen.screens.first else { return }
        w.setFrame(screen.frame, display: true)
        refreshDesktopHitTargets()
        syncScreens()
        skFitScreen()
    }

    // MARK: agents

    private func syncHouseActivity(working: Bool, changed: Bool) {
        let now = CACurrentMediaTime()
        activity.update(working: working, changed: changed, now: now)
        extras.values.forEach { $0.sync(awake: houseAwake) }
        activityTimer?.invalidate()
        activityTimer = nil
        if !working, activity.settleUntil > now {
            let timer = Timer(timeInterval: activity.settleUntil - now, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.syncHouseActivity(working: self.store.shown.contains { $0.state == .working }, changed: false)
                }
            }
            activityTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// The agents as the house takes them, as JSON; the screen saver gets the same rows (RoomSaverFeed.swift).
    static func rows(_ agents: [Agent], contexts: [String: Double]) -> String {
        let rows: [[String: Any]] = agents.map { a in
            var r: [String: Any] = ["id": a.id, "title": a.title, "project": a.project, "vendor": a.vendor.rawValue, "state": Self.state(a.state)]
            if let v = a.activity { r["activity"] = v }
            if let v = a.parentId { r["parentId"] = v }
            if let v = a.shortModel { r["model"] = v }
            if let v = a.ask { r["ask"] = v }
            if let v = contexts[a.id] { r["context"] = v }
            return r
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    private static func state(_ s: AgentState) -> String {
        switch s {
        case .working: "working"
        case .waiting: "waiting"
        case .error: "error"
        case .done: "done"
        }
    }

    // MARK: mouse

    /// The window ignores the mouse, so the cursor is read globally and passed on while nothing covers the desktop.
    /// Trackpad gestures over bare desktop drive the view: pinch zooms at the cursor, two fingers move, a double tap resets.
    /// `target` is the window WindowServer sends the event to (the monitor's event knows it); without one, AppKit's mouse-down hit
    /// test answers. Both skip click-through windows, which a window list scan cannot tell apart (an invisible ChatGPT sheet).
    private func mouse(_ type: NSEvent.EventType, magnify: CGFloat = 0, scroll: (CGFloat, CGFloat) = (0, 0), target: Int? = nil) {
        guard let w = window, house != nil else { return }
        let scene = house?.scene as? HouseScene2
        let now = CACurrentMediaTime()
        if type == .mouseMoved {
            guard now - lastMove > 0.04 else { return }
            lastMove = now
        }
        let p = NSEvent.mouseLocation
        let inside = w.frame.contains(p) && w.occlusionState.contains(.visible)
        let bare = inside && desktopHitTargets.contains(target ?? NSWindow.windowNumber(at: p, belowWindowWithWindowNumber: 0))
        let x = p.x - w.frame.minX, y = w.frame.maxY - p.y
        switch type {
        case .leftMouseDown:
            pressed = (p, CACurrentMediaTime())
            return
        case .leftMouseUp:
            // a click, not the end of a drag across the desktop
            let click = pressed.map { hypot($0.0.x - p.x, $0.0.y - p.y) < 6 && CACurrentMediaTime() - $0.1 < 0.6 } ?? true
            pressed = nil
            if bare, click { scene?.pointerClicked(x: Double(x), y: Double(y)); pinchHint(scene, x: x, y: y) }
            return
        case .magnify:
            if bare { scene?.zoom(1 + Double(magnify), x: Double(x), y: Double(y)) }
            else if CACurrentMediaTime() - lastPinchNote > 2 { // why a pinch did not reach the room
                lastPinchNote = CACurrentMediaTime()
                NSLog("agents-notch: pinch not passed on: \(w.frame.contains(p) ? "covered by \(coveringWindow(at: p) ?? "?")" : "outside the wallpaper")")
            }
            return
        case .smartMagnify:
            if bare { scene?.resetView() }
            return
        case .scrollWheel:
            if bare, scroll != (0, 0) { scene?.pan(dx: Double(scroll.0), dy: Double(scroll.1)) }
            return
        default: break
        }
        if bare { hovering = true; scene?.pointerMoved(x: Double(x), y: Double(y)) }
        else if hovering { hovering = false; tip.hide(); scene?.pointerLeft() }
    }

    /// Cache desktop IDs only when the windows/Space are created. AppKit's point hit test then handles
    /// exposed desktop beside any frontmost app, and Finder windows covering the house, without a list per move.
    private func refreshDesktopHitTargets() {
        guard window != nil else { return }
        let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        desktopHitTargets = Set(list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer < 0 else { return nil }
            return info[kCGWindowNumber as String] as? Int
        })
        desktopHitTargets.insert(0) // AppKit reports no mouse target on an empty desktop with icons hidden.
    }

    private var lastPinchNote: CFTimeInterval = 0
    private var pinchHinted = false

    /// Without Input Monitoring a pinch never arrives. The first time a click zooms the SpriteKit house in, a small card says what else
    /// works and where pinch is switched on (once per run; the tip panel is the app's own, nothing new is added to the desktop).
    private func pinchHint(_ scene: HouseScene2?, x: CGFloat, y: CGFloat) {
        guard let scene, let w = window,
              HousePinch.hintDue(tapActive: pinchTap != nil, alreadyShown: pinchHinted, zoomTarget: scene.houseCamera?.target.zoom ?? 1) else { return }
        pinchHinted = true
        let cause = HousePinch.cause(allowed: CGPreflightListenEventAccess())
        NSLog("agents-notch: pinch zoom is off (\(cause == .notGranted ? "no Input Monitoring" : "the event tap could not start")); showed the one-time hint")
        let token = UUID()
        hintToken = token
        tip.show(["title": Loc.t("Pinch zoom is off", "Масштаб жестом выключен"),
                  "status": Loc.t("Click a room, scroll to pan, double tap goes back", "Клик по комнате, прокрутка двигает, двойное касание возвращает"),
                  "color": "#e0a030",
                  "detail": cause == .notGranted ? Loc.t("Settings > House > Pinch zoom", "Настройки > Дом > Масштаб жестом")
                                                 : Loc.t("Input Monitoring is on, but the gesture tap did not start: restart the app", "Доступ есть, но перехват жестов не запустился: перезапустите приложение"),
                  "x": Double(x), "y": Double(y)], in: w.frame)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.hintToken == token else { return }
            self.hintToken = nil
            self.tip.hide()
        }
    }
    /// The app and title of the window over this point, if any (for the log when a gesture is not passed on).
    private func coveringWindow(at p: NSPoint) -> String? {
        guard let primary = NSScreen.screens.first else { return "no screen" }
        let point = CGPoint(x: p.x, y: primary.frame.maxY - p.y)
        let own = window.map { CGWindowID($0.windowNumber) }
        let dock = Int(CGWindowLevelForKey(.dockWindow))
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer >= 0, layer < dock,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  (info[kCGWindowNumber as String] as? CGWindowID) != own,
                  // the Dock lays a clear sheet over the screen while windows are pushed aside to show the desktop
                  (info[kCGWindowOwnerName as String] as? String) != "Dock",
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b) else { continue }
            if rect.contains(point) { return "\(info[kCGWindowOwnerName as String] as? String ?? "?") layer \(layer) \(rect)" }
        }
        return nil
    }

    // MARK: where the art lives

    /// The atlas the house is drawn from: AGENT_NOTCH_ROOM (a room/index.html path, as before) names its folder; the app bundle carries
    /// Resources/room/atlas; `swift run` finds the repo's room/atlas.
    static var atlasDirectory: URL? {
        func usable(_ d: URL) -> URL? { FileManager.default.fileExists(atPath: d.appendingPathComponent("parts.json").path) ? d : nil }
        if let p = ProcessInfo.processInfo.environment["AGENT_NOTCH_ROOM"] {
            return usable(URL(fileURLWithPath: p).deletingLastPathComponent().appendingPathComponent("atlas", isDirectory: true))
        }
        if let d = Bundle.main.resourceURL?.appendingPathComponent("room/atlas", isDirectory: true), let u = usable(d) { return u }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            if let u = usable(dir.appendingPathComponent("room/atlas", isDirectory: true)) { return u }
            dir.deleteLastPathComponent()
        }
        return nil
    }
}

/// The hover card for a Clawd. It is its own window just above the desktop icons, so folders never cover it,
/// and still below every app window.
@MainActor
private final class RoomTip {
    private let panel: NSPanel = {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        p.ignoresMouseEvents = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        return p
    }()

    /// `t` comes from the page: title, status, color, detail and the cursor (x, y) in page points.
    func show(_ t: [String: Any], in frame: NSRect) {
        let view = RoomTipView(title: t["title"] as? String ?? "", status: t["status"] as? String ?? "",
                               color: Color(hex: t["color"] as? String ?? "#aaaaaa"), detail: t["detail"] as? String ?? "")
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        panel.contentView = host
        let x = (t["x"] as? Double ?? 0), y = (t["y"] as? Double ?? 0)
        var origin = NSPoint(x: frame.minX + x + 16, y: frame.maxY - y - 16 - size.height)
        origin.x = min(origin.x, frame.maxX - size.width - 8)
        if origin.y < frame.minY + 8 { origin.y = frame.maxY - y + 16 }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}

/// The mailbox's tip of the day: its own small panel, so it never replaces an agent's hover card (the page's eggCard).
@MainActor
private final class RoomNote {
    private let panel: NSPanel = {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        p.ignoresMouseEvents = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        return p
    }()
    private let host = NSHostingView(rootView: RoomNoteView(text: ""))
    private var shown: (String, Int, Int)?

    /// (x, y) is the mailbox's letter in window points: the card's bottom sits 10 px above it, its top stays below 70 and its middle within 125 px of the sides.
    func show(_ text: String, x: Double, y: Double, in frame: NSRect) {
        let key = (text, Int(x.rounded()), Int(y.rounded()))
        if let s = shown, s == key, panel.isVisible { return }
        shown = key
        if panel.contentView !== host { panel.contentView = host }
        host.rootView = RoomNoteView(text: text)
        let size = host.fittingSize
        let cx = min(max(x, 125), max(125, frame.width - 125)), top = max(70, y)
        let origin = NSPoint(x: frame.minX + cx - size.width / 2, y: frame.maxY - top + 10)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { shown = nil; if panel.isVisible { panel.orderOut(nil) } }
}

private struct RoomNoteView: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("✉ Совет дня").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: "#c0563a"))
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(Color(hex: "#2a1f2e")).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .frame(maxWidth: 230, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#fffaf0")))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "#2a1f2e"), lineWidth: 2))
        .fixedSize()
        .padding(.trailing, 3).padding(.bottom, 3)
    }
}

private struct RoomTipView: View {
    let title: String, status: String, color: Color, detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(status).lineLimit(1)
            }.font(.system(size: 12)).opacity(0.75)
            if !detail.isEmpty { Text(detail).font(.system(size: 12, design: .monospaced)).opacity(0.75).lineLimit(1) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: 360, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.07, green: 0.06, blue: 0.11).opacity(0.94)))
        .fixedSize()
    }
}

private extension Color {
    init(hex: String) {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0xaaaaaa
        self.init(red: Double(v >> 16 & 0xff) / 255, green: Double(v >> 8 & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

