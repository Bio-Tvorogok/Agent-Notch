import AppKit
import Combine
import IOKit.ps
import NotchCore
import SpriteKit
import SwiftUI
import WebKit

/// The agents' house as the desktop wallpaper: room/index.html in a window just above the desktop picture.
/// The window never takes the mouse, so the desktop icons keep working; hover and clicks on bare desktop
/// are forwarded to the page, and a click on a Clawd opens that agent's chat.
@MainActor
final class RoomWallpaper: NSObject {
    private let store: Store
    private var window: NSWindow?
    private(set) var web: WKWebView?
    /// The SpriteKit prototype (docs/house-spritekit-port.md), only with `houseRenderer spritekit`.
    private var house: SKView?
    /// What the running SpriteKit house was built from: the screen's numbers and the project list (see skGeometry).
    private var skBuilt: [Double] = []
    private var skPrefs = RoomPrefs()
    private var skBehaviour: HouseBehaviour?
    /// The one growth count of both renderers (see HouseScene2Growth.swift).
    private let growth = HouseGrowthStore()
    /// Set when the atlas failed to draw: the page stays in charge until the app restarts.
    private var forceWeb = false
    /// Set when the current screen cannot hold the house (too short for the Dock's inset): cleared when the screen changes.
    private var screenBlocked = false
    /// The screen geometry that was too short for the SpriteKit house: only another one is tried again.
    private var blockedGeometry: [Double]?
    /// Texture preload stalls this session; the second one leaves the page in place.
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
    private var powerTimer: Timer?
    private var sentActive: Bool?
    private var sentFps = 0
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
        guard window == nil else { return }
        guard let page = Self.page else { NSLog("agents-notch: room/index.html not found"); return }
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
        if Self.wantsSpriteKit, !forceWeb {
            if let why = Self.spriteKitReason(AppSettings.shared.room) {
                NSLog("agents-notch: the SpriteKit house cannot draw this (\(why)), using the page")
            } else if startSpriteKit(in: w, page: page, screen: screen) {
                return
            } else if skFailedOnScreen {
                screenBlocked = true; blockedGeometry = skGeometry(of: screen)
                NSLog("agents-notch: this screen cannot hold the SpriteKit house, using the page until the screen changes")
            } else {
                forceWeb = true
                NSLog("agents-notch: no usable SpriteKit house atlas next to \(page.path), using the page")
            }
        }

        let config = WKWebViewConfiguration()
        config.userContentController.add(MessageProxy(self), name: "room")
        let web = WKWebView(frame: NSRect(origin: .zero, size: screen.frame.size), configuration: config)
        web.navigationDelegate = self
        if #available(macOS 13.3, *) { web.isInspectable = true }
        var url = URLComponents(url: page, resolvingAgainstBaseURL: false)
        url?.queryItems = [URLQueryItem(name: "nodemo", value: "1")]
        web.loadFileURL(url?.url ?? page, allowingReadAccessTo: page.deletingLastPathComponent())
        w.contentView = web
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        window = w
        self.web = web
        syncHouseActivity(working: store.shown.contains { $0.state == .working }, changed: true)
        observeRoomSettings()

        store.objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.push() }
            .store(in: &subs)
        info.start(store: store, changed: { [weak self] in self?.push() }, send: { [weak self] js in self?.web?.evaluateJavaScript(js) })
        // A desktop-level window doesn't always follow to a new Space; bring it along when it got left behind.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                self?.refreshDesktopHitTargets()
                guard let w = self?.window, !w.isOnActiveSpace else { return }
                w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
                w.orderFrontRegardless()
            }
            .store(in: &subs)
        // Battery: nothing is drawn while the desktop is covered, and fewer frames are drawn on battery.
        NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: w)
            .sink { [weak self] _ in self?.syncPower() }
            .store(in: &subs)
        NotificationCenter.default.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncPower() }
            .store(in: &subs)
        powerTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncPower() }
        }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.fitScreen() }
            .store(in: &subs)
        startPointer()
    }

    /// The window ignores the mouse, so both renderers read the pointer, trackpad and Esc through a global monitor and the pinch tap
    /// (the SpriteKit path once returned before this, so nothing answered the pointer there; scripts/test-pointer-wiring.sh).
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
                    self?.web?.evaluateJavaScript("room.resetView()")
                    (self?.house?.scene as? HouseScene2)?.resetView()
                }
                return
            }
            let scroll = type == .scrollWheel && e.hasPreciseScrollingDeltas ? (e.scrollingDeltaX, e.scrollingDeltaY) : (0, 0)
            MainActor.assumeIsolated { self?.mouse(type, scroll: scroll) }
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

    /// `houseRenderer spritekit` in the defaults, or HOUSE_RENDERER=spritekit in the environment (for a trial run, nothing is stored).
    static var wantsSpriteKit: Bool {
        ProcessInfo.processInfo.environment["HOUSE_RENDERER"] == "spritekit" || UserDefaults.standard.string(forKey: "houseRenderer") == "spritekit"
    }

    /// Why parts.json cannot draw the user's house, nil when it can: it has the islands layout, any season and clear weather
    /// (the app never sets another weather) of the page's atlas. Custom themes are only the five rooms the atlas has.
    static func spriteKitReason(_ prefs: RoomPrefs, date: Date = Date()) -> String? {
        HouseSpriteKitRules.reason(layout: prefs.layout.rawValue, month: Calendar.current.component(.month, from: date))
    }

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
    private func makeSKScene(screen: NSScreen, page: URL, prefs: RoomPrefs) -> HouseScene2? {
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
        let atlas = HouseScene2.atlasDir(page.deletingLastPathComponent().appendingPathComponent("atlas"), season: season)
        guard let scene = HouseScene2.load(from: atlas, layout: behaviour.layout, unit: unit, size: screen.frame.size) else { return nil }
        scene.setSeason(season); skSeason = season
        scene.env = env
        scene.attach(behaviour)
        if let why = scene.missingParts() { NSLog("agents-notch: the atlas has no \(why)"); return nil }
        scene.followClock = true
        scene.onFailure = { [weak self] in DispatchQueue.main.async { MainActor.assumeIsolated { self?.fallBackToPage("the atlas failed to draw") } } }
        scene.onStall = { [weak self] in DispatchQueue.main.async { MainActor.assumeIsolated {
            guard let self else { return }
            self.skStalls += 1
            self.fallBackToPage(self.skStalls > 1 ? "the atlas stalled twice" : "the textures stalled, trying again")
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

    /// The agents as the page gets them (`Self.rows`), decoded for the behaviour.
    private func currentRows() -> [HouseAgentRow]? {
        let agents = store.shown
        info.track(agents)
        return try? JSONDecoder().decode([HouseAgentRow].self, from: Data(Self.rows(agents, contexts: info.contexts).utf8))
    }

    /// The house composed from room/atlas/parts.json by HouseScene2 (stage 1c): one room per project the agents work in,
    /// the sky by the hour. No agents or clicks yet (stage 2b); screens, Spaces and settings are followed like the page's.
    private func startSpriteKit(in w: NSWindow, page: URL, screen: NSScreen) -> Bool {
        let prefs = AppSettings.shared.room
        guard let scene = makeSKScene(screen: screen, page: page, prefs: prefs) else { return false }
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

    /// The agents as the house's behaviour takes them, only when they changed (the page's push()).
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
        guard let screen = NSScreen.screens.first, let view = house, let page = Self.page else { return }
        guard skGeometry(of: screen) != skBuilt else { return }
        guard let scene = makeSKScene(screen: screen, page: page, prefs: AppSettings.shared.room) else { fallBackToPage("the new screen cannot be drawn", screen: true); return }
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        tip.hide(); hovering = false; hintToken = nil // a card from the old scene would stay up
        view.presentScene(scene)
        sentActive = nil
        syncPower()
    }

    /// Settings or the date moved the user's house out of (or back into) what the atlas draws: the renderer follows, the
    /// other changes (theme choices) only lay the rooms out again.
    private func rendererSettingsChanged(_ prefs: RoomPrefs) {
        guard isRunning else { return }
        if Self.wantsSpriteKit, !forceWeb, Self.spriteKitReason(prefs) == nil {
            if house == nil { restart(); return }
            if prefs.themes != skPrefs.themes || prefs.layout != skPrefs.layout { restart() } // the behaviour's themes are fixed when it is made
        } else if house != nil {
            fallBackToPage(Self.spriteKitReason(prefs) ?? "the renderer was turned off")
        }
    }

    /// The 20 s tick: the month can leave the atlas's season while the house runs.
    private func checkRenderer() {
        guard house != nil else { return }
        if let why = Self.spriteKitReason(AppSettings.shared.room) { fallBackToPage(why); return }
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
    }

    /// The SpriteKit house gives way to the page (for good when the atlas itself is at fault).
    private func fallBackToPage(_ why: String, screen: Bool = false) {
        guard house != nil else { return }
        NSLog("agents-notch: leaving the SpriteKit house: \(why)")
        if screen { screenBlocked = true; blockedGeometry = NSScreen.screens.first.map { skGeometry(of: $0) } } else if why.contains("atlas") { forceWeb = true }
        restart()
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
        sentFps = 0
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        stopPinchTap()
        subs.removeAll()
        removeExtras()
        info.stop()
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "room")
        window?.orderOut(nil)
        window = nil
        house?.presentScene(nil)
        house = nil
        skBehaviour = nil
        tip.hide()
        web = nil
        lastJSON = ""
    }

    func syncPower() {
        if let house, let w = window, let scene = house.scene as? HouseScene2 {
            // covered: nothing drawn; on battery or in Low Power Mode: 30 fps at most
            scene.maxFps = Self.fps
            let visible = w.occlusionState.contains(.visible)
            if visible != sentActive { sentActive = visible; if visible { scene.wake() } else { scene.hide() } }
            extras.values.forEach { $0.sync(fps: Self.fps, awake: houseAwake) }
            return
        }
        guard let w = window, let web else { return }
        let visible = w.occlusionState.contains(.visible)
        if visible != sentActive { sentActive = visible; web.evaluateJavaScript("room.setActive(\(visible))") }
        let fps = Self.fps
        if fps != sentFps { sentFps = fps; web.evaluateJavaScript("room.setFps(\(fps))") }
        extras.values.forEach { $0.sync(fps: fps, awake: houseAwake) }
        syncInsets()
    }

    /// The menu bar and the Dock cover part of the wallpaper; the page keeps the house and the city's street clear of them,
    /// and the islands clear of the column of desktop icons on the right (unless Finder hides the desktop).
    private var sentInsets: (CGFloat, CGFloat, CGFloat)?
    private func syncInsets() {
        guard let screen = NSScreen.screens.first, let web else { return }
        let top = screen.frame.maxY - screen.visibleFrame.maxY, bottom = screen.visibleFrame.minY - screen.frame.minY
        let icons = UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "CreateDesktop") as? Bool ?? true
        let right: CGFloat = icons ? 120 : 0
        if let s = sentInsets, s == (top, bottom, right) { return }
        sentInsets = (top, bottom, right)
        web.evaluateJavaScript("room.setInsets({top: \(top), bottom: \(bottom), right: \(right)})")
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
        syncInsets()
        skFitScreen()
        // the page was kept only because the last screen was too small: this one may do
        if house == nil, screenBlocked, Self.wantsSpriteKit, !forceWeb, skGeometry(of: screen) != blockedGeometry { screenBlocked = false; restart() }
    }

    // MARK: agents

    /// The agents as the page wants them; only changes are sent.
    private func push() {
        let agents = store.shown
        info.track(agents)
        let json = Self.rows(agents, contexts: info.contexts)
        syncHouseActivity(working: agents.contains { $0.state == .working }, changed: json != lastJSON)
        guard json != lastJSON else { return }
        lastJSON = json
        web?.evaluateJavaScript("window.room && room.setAgents(\(json)); true") { _, error in
            if let error { NSLog("agents-notch: room update failed: \(error)") }
        }
    }

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

    /// The agents as `room.setAgents(...)` takes them, as JSON; the screen saver gets the same rows (RoomSaverFeed.swift).
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

    fileprivate func received(_ body: Any) {
        guard let msg = body as? [String: Any] else { return }
        if msg.keys.contains("growth") { growth.merge(page: msg["growth"]); return }
        if let error = msg["jsError"] as? String { NSLog("agents-notch: room page error: \(error.prefix(400))"); return }
        if msg.keys.contains("tip") {
            if let t = msg["tip"] as? [String: Any], let w = window { tip.show(t, in: w.frame) } else { tip.hide() }
            return
        }
        guard let id = msg["open"] as? String,
              let agent = store.shown.first(where: { $0.id == id }) else { return }
        store.open(agent)
    }

    // MARK: mouse

    /// The window ignores the mouse, so the cursor is read globally and passed on while nothing covers the desktop.
    /// Trackpad gestures over bare desktop drive the view: pinch zooms at the cursor, two fingers move, a double tap resets.
    private func mouse(_ type: NSEvent.EventType, magnify: CGFloat = 0, scroll: (CGFloat, CGFloat) = (0, 0)) {
        guard let w = window, web != nil || house != nil else { return }
        let scene = house?.scene as? HouseScene2
        let now = CACurrentMediaTime()
        if type == .mouseMoved {
            guard now - lastMove > 0.04 else { return }
            lastMove = now
        }
        let p = NSEvent.mouseLocation
        // WindowServer queries belong to clicks and gestures, never the high-rate pointer stream.
        let inside = w.frame.contains(p) && w.occlusionState.contains(.visible)
        let bare = inside && (type == .mouseMoved
            ? desktopHitTargets.contains(NSWindow.windowNumber(at: p, belowWindowWithWindowNumber: 0))
            : desktopIsBare(at: p))
        let x = p.x - w.frame.minX, y = w.frame.maxY - p.y
        switch type {
        case .leftMouseDown:
            pressed = (p, CACurrentMediaTime())
            return
        case .leftMouseUp:
            // a click, not the end of a drag across the desktop
            let click = pressed.map { hypot($0.0.x - p.x, $0.0.y - p.y) < 6 && CACurrentMediaTime() - $0.1 < 0.6 } ?? true
            pressed = nil
            if bare, click { if let web { web.evaluateJavaScript("room.click(\(x), \(y))") } else { scene?.pointerClicked(x: Double(x), y: Double(y)); pinchHint(scene, x: x, y: y) } }
            return
        case .magnify:
            if bare { if let web { web.evaluateJavaScript("room.zoom(\(1 + magnify), \(x), \(y))") } else { scene?.zoom(1 + Double(magnify), x: Double(x), y: Double(y)) } }
            else if CACurrentMediaTime() - lastPinchNote > 2 { // why a pinch did not reach the room
                lastPinchNote = CACurrentMediaTime()
                NSLog("agents-notch: pinch not passed on: \(w.frame.contains(p) ? "covered by \(coveringWindow(at: p) ?? "?")" : "outside the wallpaper")")
            }
            return
        case .smartMagnify:
            if bare { if let web { web.evaluateJavaScript("room.resetView()") } else { scene?.resetView() } }
            return
        case .scrollWheel:
            if bare, scroll != (0, 0) { if let web { web.evaluateJavaScript("room.pan(\(scroll.0), \(scroll.1))") } else { scene?.pan(dx: Double(scroll.0), dy: Double(scroll.1)) } }
            return
        default: break
        }
        if bare { hovering = true; if let web { web.evaluateJavaScript("room.pointer(\(x), \(y))") } else { scene?.pointerMoved(x: Double(x), y: Double(y)) } }
        else if hovering { hovering = false; tip.hide(); if let web { web.evaluateJavaScript("room.leave()") } else { scene?.pointerLeft() } }
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
    /// True when no app window is over this point, so the cursor is over the wallpaper itself.
    private func desktopIsBare(at p: NSPoint) -> Bool { coveringWindow(at: p) == nil }

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

    // MARK: the page

    /// AGENT_NOTCH_ROOM overrides; the app bundle carries Resources/room; `swift run` finds the repo's room/.
    static var page: URL? {
        if let p = ProcessInfo.processInfo.environment["AGENT_NOTCH_ROOM"] { return URL(fileURLWithPath: p) }
        if let u = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "room") { return u }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            let c = dir.appendingPathComponent("room/index.html")
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir.deleteLastPathComponent()
        }
        return nil
    }
}

extension RoomWallpaper: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            lastJSON = ""
            sentActive = nil
            sentFps = 0
            sentInsets = nil
            pushRoomConfig()
            web?.evaluateJavaScript("window.room && room.setGrowth && room.setGrowth(\(growth.pageJSON)); true")
            push()
            info.resend(store: store)
            syncPower()
        }
    }
}

/// WKUserContentController keeps its handlers alive; this keeps it from keeping the wallpaper alive.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: RoomWallpaper?
    init(_ owner: RoomWallpaper) { self.owner = owner }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated { owner?.received(body) }
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

