import AppKit
import Combine
import SwiftUI
import NotchCore

/// The desktop widget's window: on the desktop under every window, on all Spaces, where the user left it.
/// It is not WidgetKit: a plain panel keeps live answers and needs no extension or signing.
@MainActor
final class DesktopWidget: NSObject {
    private let store: Store
    private let settings: AppSettings
    private let model = WidgetModel()
    private let activity = SurfaceActivity()
    private var panel: KeyPanel?
    private var card: CardPanel?
    private var subscriptions: Set<AnyCancellable> = []
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var size: CGSize = .zero

    init(store: Store, settings: AppSettings? = nil) {
        self.store = store
        self.settings = settings ?? .shared
        super.init()
        self.settings.$widget.map(\.enabled).removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] on in self?.setVisible(on) }
            .store(in: &subscriptions)
        // A display that went away leaves the widget on one that is still there.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.place() }
            .store(in: &subscriptions)
        store.$hooks.map { $0.pending.contains(where: \.needsTyping) }.removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] typing in
                guard let panel = self?.panel else { return }
                panel.wantsKey = typing
                // Typing goes back to the user's own window once nothing here needs it.
                if !typing && panel.isKeyWindow { panel.resignKey() }
            }
            .store(in: &subscriptions)
    }

    private func setVisible(_ on: Bool) {
        if on { show() } else { hide() }
    }

    private func show() {
        if panel == nil { panel = makePanel() }
        place()
        updateKey()
        panel?.orderFrontRegardless()
        occlusionChanged()
    }

    /// Switched off, the widget lets go of its window and views, so nothing keeps ticking.
    private func hide() {
        card?.close()
        card = nil
        panel?.orderOut(nil)
        panel = nil
        size = .zero
        dragStart = nil
        model.dragging = false
    }

    /// Clocks and blinking marks run only while some of the widget can be seen.
    /// Coming into view also re-arms the answer buttons: a request uncovered by a closing window is not clickable at once.
    @objc private func occlusionChanged() {
        guard let panel else { return }
        let visible = panel.isVisible && panel.occlusionState.contains(.visible)
        if visible && !activity.active { model.armEpoch += 1 }
        activity.setActive(visible)
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 240), styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        // Above the desktop icons, below every ordinary window.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged), name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        let view = ActiveSurface(activity: activity) { DesktopWidgetView(store: store, model: model,
                                     onSize: { [weak self] in self?.resize($0) },
                                     onDrag: { [weak self] ended in self?.drag(ended: ended) },
                                     openSettings: { SettingsWindow.shared.open(.appearance) }) }
            .environmentObject(settings)
            .environmentObject(store.usage)
        panel.contentView = NSHostingView(rootView: view)
        card = CardPanel(store: store, list: panel, settings: settings,
                         selection: model.$selected.eraseToAnyPublisher(),
                         current: { [weak model] in model?.selected },
                         clear: { [weak model] in if let model, model.selected != nil { model.selected = nil } },
                         onLeave: { [weak self] in self?.card?.close() })
        return panel
    }

    /// A question or a plan has a text field, and a panel only takes typing when it may become key.
    private func updateKey() {
        panel?.wantsKey = store.hooks.pending.contains(where: \.needsTyping)
    }

    /// The view grows down from its top edge; the window follows it.
    private func resize(_ next: CGSize) {
        guard let panel, next.width > 0, next.height > 0, next != size else { return }
        size = next
        let top = panel.frame.maxY
        var frame = NSRect(x: panel.frame.minX, y: top - next.height, width: next.width, height: next.height)
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame { frame = Self.clamp(frame, to: visible) }
        panel.setFrame(frame, display: true)
    }

    private func drag(ended: Bool) {
        guard let panel, !(ended && dragStart == nil) else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil {
            dragStart = (mouse, panel.frame.origin)
            model.dragging = true
            card?.close()
        }
        guard let start = dragStart else { return }
        panel.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
        if ended {
            dragStart = nil
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? panel.screen {
                panel.setFrame(Self.clamp(panel.frame, to: screen.visibleFrame), display: true)
                save(on: screen)
            }
            // The buttons wake up only after the drop has settled.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.model.dragging = false }
        }
    }

    private func save(on screen: NSScreen) {
        guard let panel, let id = screen.displayID else { return }
        let visible = screen.visibleFrame
        settings.widgetPlace = WidgetPlace(display: id, x: panel.frame.minX - visible.minX, y: visible.maxY - panel.frame.maxY)
    }

    /// Back where it was left; the main display's top right corner the first time or when that display is gone.
    private func place() {
        guard let panel else { return }
        let frameSize = size == .zero ? panel.frame.size : size
        let saved = settings.widgetPlace
        // The primary display (the one with the menu bar) is first; NSScreen.main is merely the focused one.
        let screen = saved.flatMap { place in NSScreen.screens.first { $0.displayID == place.display } } ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        // Hero and limits take about 260 points; the list gets the rest of the display.
        model.maxListHeight = max(160, visible.height - 300)
        var frame: NSRect
        if let saved, screen?.displayID == saved.display {
            frame = NSRect(x: visible.minX + saved.x, y: visible.maxY - saved.y - frameSize.height, width: frameSize.width, height: frameSize.height)
        } else {
            frame = NSRect(x: visible.maxX - frameSize.width - 24, y: visible.maxY - frameSize.height - 24,
                           width: frameSize.width, height: frameSize.height)
        }
        frame = Self.clamp(frame, to: visible)
        panel.setFrame(frame, display: true)
    }

    static func clamp(_ frame: NSRect, to visible: NSRect) -> NSRect {
        var f = frame
        f.origin.x = max(visible.minX, min(f.minX, visible.maxX - f.width))
        f.origin.y = max(visible.minY, min(f.minY, visible.maxY - f.height))
        return f
    }
}

extension NSScreen {
    var displayID: UInt32? { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
}
