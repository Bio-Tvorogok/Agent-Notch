import AppKit
import ApplicationServices

/// Collapses the wing into one summary when the frontmost app's menu reaches it.
/// Needs Accessibility access; without it the wing never collapses for the menu.
@MainActor
final class MenuWatcher {
    private let store: Store
    private let wingLeft: () -> CGFloat?
    private var timer: Timer?

    init(store: Store, wingLeft: @escaping () -> CGFloat?) {
        self.store = store
        self.wingLeft = wingLeft
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    private func check() {
        guard AXIsProcessTrusted(), let left = wingLeft(), let menuRight = Self.frontMenuRightEdge() else {
            if store.menuCramped { store.menuCramped = false }
            return
        }
        let cramped = menuRight > left - 8
        if store.menuCramped != cramped { store.menuCramped = cramped }
    }

    /// Global x of the right edge of the frontmost app's last menu bar title.
    static func frontMenuRightEdge() -> CGFloat? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success, let bar else { return nil }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &kids) == .success,
              let items = kids as? [AXUIElement] else { return nil }
        return items.compactMap { item -> CGFloat? in
            var pos: CFTypeRef?, size: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &pos) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success else { return nil }
            var p = CGPoint.zero, s = CGSize.zero
            AXValueGetValue(pos as! AXValue, .cgPoint, &p)
            AXValueGetValue(size as! AXValue, .cgSize, &s)
            return p.x + s.width
        }.max()
    }
}
