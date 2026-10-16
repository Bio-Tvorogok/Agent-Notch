import AppKit
import SwiftUI
import NotchCore

/// Words of the finish toast.
enum ToastText {
    static var menu: String { Loc.t("Toast when an agent finishes", "Тост, когда агент закончил") }
    static var open: String { Loc.t("Details", "Подробнее") }
}

extension AppActions {
    @objc func toggleFinishToast() { AppSettings.shared.finishToast.toggle() }
}

/// A small panel under the notch that shows for 6 seconds and opens the list with the agent's card on a click.
/// Never takes focus: the frontmost app keeps it.
@MainActor
final class FinishToast {
    static let seconds = 6.0
    private let panel: NSPanel = {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        return p
    }()
    private var timer: Timer?

    func show(_ n: FinishNotice, notch: (x: CGFloat, top: CGFloat, height: CGFloat)?, onOpen: @escaping () -> Void) {
        let width: CGFloat = 340
        let host = NSHostingView(rootView: ToastView(notice: n, onOpen: { [weak self] in self?.hide(); onOpen() }).environmentObject(AppSettings.shared))
        host.frame.size = NSSize(width: width, height: host.fittingSize.height)
        let height = host.fittingSize.height
        let screen = notch.flatMap { a in NSScreen.screens.first { $0.frame.maxY == a.top } } ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let top = notch.map { $0.top - $0.height } ?? (screen?.visibleFrame.maxY ?? frame.maxY - 24)
        panel.contentView = host
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: top - 8 - height, width: width, height: height), display: true)
        panel.orderFrontRegardless()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func hide() {
        timer?.invalidate()
        panel.orderOut(nil)
    }
}

private struct ToastView: View {
    let notice: FinishNotice
    let onOpen: () -> Void
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                AgentStatusMark(agent: notice.agent)
                Text(notice.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.strong).lineLimit(1)
            }
            Text(notice.line).font(.system(size: 11)).foregroundStyle(Ink.askText).lineLimit(1)
            if let p = notice.preview {
                Text(p).font(.system(size: 11)).foregroundStyle(dim).lineLimit(2)
            }
        }
        .frame(width: 340, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background { if settings.theme == .terminal { RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.11)) } }
        .overlay { if settings.theme == .terminal { RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.23), lineWidth: 1) } }
        .modifier(ToastSurface(theme: settings.currentTheme))
        .themed(settings.currentTheme)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .help(ToastText.open)
    }
}

/// «Терминал» keeps its original toast frame (drawn above); every other theme gets its surface.
private struct ToastSurface: ViewModifier {
    let theme: Theme
    func body(content: Content) -> some View {
        if theme.id == .terminal { content } else { content.themeSurface(theme, radius: min(theme.radius, 18)) }
    }
}

@MainActor
final class JumpToast {
    private let panel: NSPanel = {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        return p
    }()
    private var timer: Timer?

    func show(command: String?, terminalOrigin: Bool, screen: NSScreen, settings: AppSettings) {
        let host = NSHostingView(rootView: JumpToastView(canResume: command != nil, terminalOrigin: terminalOrigin) { [weak self] in
            if let command {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
            self?.timer?.invalidate()
            self?.timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.panel.orderOut(nil) }
            }
        }.environmentObject(settings))
        let size = host.fittingSize
        panel.contentView = host
        let top = screen.safeAreaInsets.top > 0 ? screen.frame.maxY - screen.safeAreaInsets.top : screen.visibleFrame.maxY
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: top - 8 - size.height,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.orderOut(nil) }
        }
    }
}

struct JumpToastView: View {
    let canResume: Bool
    var terminalOrigin = true
    let onCopy: () -> Void
    @State private var copied = false
    @State private var hovered = false
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(terminalOrigin
                ? Loc.t("Terminal not found — opened the project folder", "Терминал не найден — открыл папку проекта")
                : Loc.t("Couldn't open the app — opened the project folder", "Не удалось открыть приложение — открыл папку проекта"))
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Ink.strong)
                .fixedSize(horizontal: false, vertical: true)
            if canResume {
                Button {
                    guard !copied else { return }
                    copied = true
                    onCopy()
                } label: {
                    Text(copied ? Loc.t("Copied", "Скопировано") : Loc.t("Copy resume command", "Скопировать команду"))
                }
                .buttonStyle(Pill(primary: false, bordered: true, hovered: hovered))
                .onHover { hovered = $0 }
                .onContinuousHover { phase in
                    switch phase {
                    case .active: NSCursor.pointingHand.set()
                    case .ended: NSCursor.arrow.set()
                    }
                }
            }
        }
        .frame(width: 300, alignment: .leading)
        .padding(12)
        .background { if settings.theme == .terminal { RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.11)) } }
        .overlay { if settings.theme == .terminal { RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.23), lineWidth: 1) } }
        .modifier(ToastSurface(theme: settings.currentTheme))
        .themed(settings.currentTheme)
    }
}
