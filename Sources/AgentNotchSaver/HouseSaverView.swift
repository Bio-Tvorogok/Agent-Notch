import AppKit
import NotchCore
import ScreenSaver
import WebKit

/// The agents' house as a screen saver: room/index.html in a WKWebView, fed from the snapshot the running app writes
/// (HouseSnapshot), polled every `poll` seconds. With "Require password immediately" it works as a live lock screen.
///
/// Sonoma can retain views without calling stopAnimation. A real stop releases WebKit and exits the legacy
/// host; sustained invisibility catches retained windows without reacting to presentation blips. Hidden pages keep WebKit's throttling.
@objc(AgentNotchHouseView)
final class HouseSaverView: ScreenSaverView {
    static let poll: TimeInterval = 2

    private var web: WKWebView?
    private var timer: Timer?
    private var loaded = false
    private var shown: HouseSnapshot?
    private var observers: [NSObjectProtocol] = []
    private let file = HouseSnapshot.url(home: HouseSnapshot.realHome)
    private var running = false
    private var activity = SaverActivity.State()
    private var sentActive: Bool?

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
        if web == nil { makeWeb() } else if !loaded { reload() }
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
        sentActive = nil
        timer?.invalidate()
        timer = nil
        guard let web else { return }
        if loaded { send("room.setActive(false)") }
        Self.occlusionDetection(web, enabled: true)
        web.navigationDelegate = nil
        web.stopLoading()
        web.removeFromSuperview()
        self.web = nil
        loaded = false
        shown = nil
    }

    // MARK: the page

    private func makeWeb() {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        let web = WKWebView(frame: bounds, configuration: config)
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        addSubview(web)
        self.web = web
        reload()
    }

    private func reload() {
        guard let web else { return }
        loaded = false
        sentActive = nil
        shown = nil
        guard let page = Bundle(for: HouseSaverView.self).url(forResource: "index", withExtension: "html", subdirectory: "room") else {
            log("room/index.html is missing from the bundle")
            return
        }
        var url = URLComponents(url: page, resolvingAgainstBaseURL: false)
        url?.queryItems = [URLQueryItem(name: "nodemo", value: "1")]
        web.loadFileURL(url?.url ?? page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    /// Sends the house in the snapshot file when it changed; a missing or stale file is an empty house.
    private func refresh() {
        guard running else { return }
        activity = SaverActivity.sample(activity, now: ProcessInfo.processInfo.systemUptime,
                                        running: running, visible: onScreen, preview: isPreview)
        if activity.exitHost { saverWillStop(); return }
        let visible = activity.draw
        // ScreenSaverEngine mirrors an occluded host. Only a currently presented saver may ignore that
        // occlusion; hidden-page timer and process throttling retain WebKit's defaults throughout.
        if sentActive != visible, let web { Self.occlusionDetection(web, enabled: isPreview || !visible) }
        if visible && !loaded && web?.isLoading == false { reload(); return }
        guard loaded else { return }
        if sentActive != visible { sentActive = visible; send("room.setActive(\(visible))") }
        guard visible else { return }
        let now = Date()
        let next = (try? Data(contentsOf: file)).flatMap { HouseSnapshot.decode($0, now: now) } ?? .empty(at: now)
        let old = shown
        shown = next
        if old?.config != next.config { send("room.configure && room.configure(\(next.config))") }
        if old?.fps != next.fps { send("room.setFps(\(next.fps))") }
        if old?.agents != next.agents { send("room.setAgents(\(next.agents))") }
        if let usage = next.usage, old?.usage != usage { send("room.setUsage(\(usage))") }
    }

    private func send(_ js: String) {
        guard loaded, let web else { return }
        web.evaluateJavaScript("window.room && (\(js)); true") { [weak self] _, error in
            if let error { MainActor.assumeIsolated { self?.log("page call failed: \(error.localizedDescription)") } }
        }
    }

    private static func occlusionDetection(_ web: WKWebView, enabled: Bool) {
        let selector = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        guard web.responds(to: selector), let method = class_getInstanceMethod(type(of: web), selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(method_getImplementation(method), to: Setter.self)(web, selector, enabled)
    }

    private func log(_ message: String) { NSLog("agent-notch-house: \(message)") }
}

extension HouseSaverView: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            guard webView === web else { return }
            loaded = true
            shown = nil
            log("page loaded")
            // nothing covers the screen saver: no menu bar, no Dock, no desktop icons
            send("room.setInsets({top: 0, bottom: 0, right: 0})")
            refresh()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { log("page failed: \(error.localizedDescription)") }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { log("page failed to open: \(error.localizedDescription)") }
    }

    /// The system may kill the page's process while the saver runs; a black screen would stay until the next start.
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated {
            guard webView === web else { return }
            log("page process ended")
            loaded = false
            shown = nil
            sentActive = nil
            if onScreen { reload() }
        }
    }
}
