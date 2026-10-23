import AppKit
import Combine
import SwiftUI
import NotchCore

/// Owns card lifetime so closing the list also stops detail reads.
@MainActor
final class CardPanel {
    private let panel: NSPanel
    private let model = CardDetailModel()
    private weak var list: NSPanel?
    private var selection: AnyCancellable?
    private var updates: AnyCancellable?
    private var mouseTimer: Timer?
    private var leftAt: Date?
    private let onLeave: () -> Void
    private weak var store: Store?
    /// The list's card follows the store's selection; the desktop widget brings its own.
    private let current: () -> Agent.ID?
    private let clear: () -> Void
    /// The list may slide over to make room; the widget stays where it was put and the card takes the free side.
    private let movesList: Bool

    init(store: Store, list: NSPanel, settings: AppSettings? = nil, selection: AnyPublisher<Agent.ID?, Never>? = nil,
         current: (() -> Agent.ID?)? = nil, clear: (() -> Void)? = nil, onLeave: @escaping () -> Void) {
        let settings = settings ?? .shared
        self.list = list
        self.store = store
        self.onLeave = onLeave
        self.current = current ?? { [weak store] in store?.selected }
        self.clear = clear ?? { [weak store] in if let store, store.selected != nil { store.selected = nil } }
        movesList = selection == nil
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        model.readsUsage = { settings.cardBlockShown(.contextCost) }
        panel.contentView = NSHostingView(rootView: LiveCardView(model: model, settings: settings) { [weak store] in store?.open($0) })
        self.selection = (selection ?? store.$selected.eraseToAnyPublisher()).receive(on: RunLoop.main).sink { [weak self] id in
            self?.apply(id, retry: true)
        }
        updates = store.objectWillChange.receive(on: RunLoop.main).sink { [weak self, weak store] _ in
            guard let self, let id = self.model.agent?.id, let agent = store?.shown.first(where: { $0.id == id }) else { return }
            self.model.update(agent)
        }
    }

    /// A select can land a tick before the list is on screen (the toast opens both): look once more before closing.
    private func apply(_ id: Agent.ID?, retry: Bool) {
        guard let store, let list else { close(); return }
        guard let id, let agent = store.shown.first(where: { $0.id == id }) else { close(); return }
        guard list.isVisible else {
            if retry { DispatchQueue.main.async { [weak self] in self?.apply(self?.current(), retry: false) } } else { close() }
            return
        }
        let changed = !panel.isVisible || model.agent?.id != agent.id
        model.show(agent)
        place(nextTo: list)
        panel.orderFrontRegardless()
        if changed { SoundPlayer.shared.play(.cardOpened, settings: store.settings) }
        watchMouse()
    }

    func place(nextTo list: NSPanel) {
        guard model.agent != nil else { return }
        let width: CGFloat = 340
        let gap: CGFloat = 6
        let screen = list.screen ?? NSScreen.main
        var listFrame = list.frame
        if !movesList, let visible = screen?.visibleFrame {
            let height = min(480, max(1, listFrame.maxY - visible.minY - 8))
            let right = listFrame.maxX + gap
            let x = right + width <= visible.maxX - 8 ? right : max(visible.minX + 8, listFrame.minX - gap - width)
            let y = max(visible.minY + 8, min(listFrame.maxY - height, visible.maxY - height))
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
            return
        }
        if let visible = screen?.visibleFrame {
            let maxListX = visible.maxX - 8 - listFrame.width - gap - width
            listFrame.origin.x = max(visible.minX + 8, min(listFrame.minX, maxListX))
            if listFrame != list.frame { list.setFrame(listFrame, display: true) }
        }
        let available = screen.map { listFrame.maxY - $0.visibleFrame.minY - 8 } ?? 480
        let height = min(480, max(1, available))
        panel.setFrame(NSRect(x: listFrame.maxX + gap, y: listFrame.maxY - height, width: width, height: height), display: true)
    }

    func close() {
        if panel.isVisible { SoundPlayer.shared.play(.cardClosed, settings: store?.settings) }
        panel.orderOut(nil)
        mouseTimer?.invalidate()
        mouseTimer = nil
        leftAt = nil
        model.close()
        // A card that is gone must not stay selected, or the next open would show it again.
        clear()
    }

    private func watchMouse() {
        mouseTimer?.invalidate()
        leftAt = nil
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkMouse() }
        }
    }

    private func checkMouse() {
        guard let list, list.isVisible else { close(); return }
        let point = NSEvent.mouseLocation
        // Include the narrow crossing gap; a short grace also permits diagonal crossings.
        if list.frame.insetBy(dx: -3, dy: 0).contains(point) || panel.frame.insetBy(dx: -3, dy: 0).contains(point) {
            leftAt = nil
        } else if let leftAt {
            if Date().timeIntervalSince(leftAt) >= 0.25 { onLeave() }
        } else { leftAt = Date() }
    }
}
