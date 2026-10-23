import SwiftUI
import NotchCore

/// What the widget window shares with its view: its own card selection and whether it is being dragged.
@MainActor
final class WidgetModel: ObservableObject {
    @Published var selected: Agent.ID?
    @Published var dragging = false
}

extension WidgetSize {
    var width: CGFloat {
        switch self {
        case .small: 260
        case .medium: 340
        case .large: 380
        }
    }
    var minHeight: CGFloat {
        switch self {
        case .small: 170
        case .medium: 230
        case .large: 420
        }
    }
    /// Rows the list may take before it makes room (see WidgetPlan).
    var capacity: Int {
        switch self {
        case .small: 4
        case .medium: 9
        case .large: 18
        }
    }
}

enum WidgetMenuText {
    static var size: String { Loc.t("Size", "Размер") }
    static func size(_ s: WidgetSize) -> String {
        switch s {
        case .small: Loc.t("Small", "Маленький")
        case .medium: Loc.t("Medium", "Средний")
        case .large: Loc.t("Large", "Большой")
        }
    }
    static var style: String { Loc.t("Widget style", "Стиль виджета") }
    static var followTheme: String { Loc.t("Same as theme", "Как тема") }
    static var hide: String { Loc.t("Hide widget", "Скрыть виджет") }
    static var settings: String { Loc.t("Settings…", "Настройки…") }
    static var title: String { Loc.t("Desktop widget", "Виджет на рабочем столе") }
    static var help: String {
        Loc.t("Lies on the desktop under all windows. Drag it anywhere; right-click for size and style.",
              "Лежит на рабочем столе под всеми окнами. Перетащите куда удобно; правый клик — размер и стиль.")
    }
    static func done(_ n: Int) -> String { Loc.t("\(n) more done", "ещё \(n) готово") }
}

/// The desktop widget: a big count, the agents by project with their requests, the limits at the bottom.
/// Every style draws the same lines and buttons; only the dress changes.
struct DesktopWidgetView: View {
    @ObservedObject var store: Store
    @ObservedObject var model: WidgetModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var usage: UsageModel
    var onSize: (CGSize) -> Void = { _ in }
    var onDrag: (_ ended: Bool) -> Void = { _ in }
    var openSettings: () -> Void = {}

    var body: some View {
        let theme = settings.widgetTheme
        let size = settings.widget.size
        let projects = store.projects
        let live = projects.flatMap(\.live)
        VStack(alignment: .leading, spacing: 0) {
            WidgetHero(live: live.count, waiting: live.filter { $0.state == .waiting }.count,
                       errors: live.filter { $0.state == .error }.count, size: size)
            if projects.isEmpty {
                Text(SettingsListText.empty(minutes: settings.appearance.finishedMinutes))
                    .font(.system(size: 11)).foregroundStyle(dim).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            } else {
                list(projects, size: size)
            }
            Spacer(minLength: 0)
            WidgetLimits(usage: usage, compact: size == .small)
        }
        .padding(.vertical, 10)
        .modifier(Glow(color: theme.glow))
        .frame(width: size.width, alignment: .topLeading)
        .frame(minHeight: size.minHeight, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .themeSurface(theme, radius: max(theme.radius, theme.id == .pixel ? 0 : 18))
        .themed(theme)
        .font(.system(size: 12, design: theme.design))
        .foregroundStyle(Ink.text)
        .background(GeometryReader { g in Color.clear.onAppear { onSize(g.size) }.onChange(of: g.size) { _, s in onSize(s) } })
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { _ in onDrag(false) }
            .onEnded { _ in onDrag(true) })
        .contextMenu { menu }
    }

    @ViewBuilder private func list(_ projects: [ProjectNode], size: WidgetSize) -> some View {
        let pinned = Set(store.hooks.pending.map(\.event.agentKey))
        let sections = ListFilter.sections(projects, grouped: settings.rows.groupByProject, order: settings.rows.sort)
        let lines = WidgetPlan.lines(sections, tree: settings.rows.subagentTree, pinned: pinned, capacity: size.capacity)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                self.line(line, projects: projects)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder private func line(_ line: WidgetLine, projects: [ProjectNode]) -> some View {
        switch line {
        case .project(let name):
            WidgetProjectHeader(name: name)
        case .session(let agent, let folded):
            WidgetRow(agent: agent, folded: folded, select: select, open: { store.open($0) })
        case .kid(let agent, let last):
            WidgetRow(agent: agent, small: true, indent: true, last: last, select: select, open: { store.open($0) })
        case .doneKids(let kids):
            HStack(spacing: 7) {
                TreeLine(last: true).frame(width: 12)
                HStack(spacing: 2) {
                    ForEach(kids) { k in
                        Button { RowClick.isDouble ? store.open(k) : select(k) } label: { AgentStatusMark(agent: k, small: true).padding(2) }.buttonStyle(.plain)
                    }
                }
                Text(kids.count == 1 ? "\(kids[0].title) — " + Loc.t("done", "готово") : WidgetMenuText.done(kids.count))
                    .foregroundStyle(dim).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 14).frame(minHeight: 22)
        case .attention(let agent, let parent):
            let project = projects.first { p in p.all.contains { $0.id == agent.id } }?.name ?? agent.project
            let item = AttentionItem(agent: agent, project: project, parent: parent)
            let asks = store.hooks.pending.filter { $0.event.agentKey == agent.id }
            if asks.isEmpty {
                ArmedRow(key: agent.id, dragging: model.dragging) {
                    AttentionRow(item: item, multi: false, store: store, ask: nil, select: select)
                }
            } else {
                ForEach(asks) { ask in
                    ArmedRow(key: "\(ask.ticket)", dragging: model.dragging) {
                        AttentionRow(item: item, multi: false, store: store, ask: ask, select: select)
                    }
                }
            }
        case .more(let n):
            Text(WidgetText.more(n)).font(.system(size: 11)).foregroundStyle(dim)
                .padding(.horizontal, 14).padding(.vertical, 4)
        }
    }

    private func select(_ agent: Agent) {
        model.selected = model.selected == agent.id ? nil : agent.id
    }

    @ViewBuilder private var menu: some View {
        Picker(WidgetMenuText.size, selection: $settings.widget.size) {
            ForEach(WidgetSize.allCases, id: \.self) { Text(WidgetMenuText.size($0)).tag($0) }
        }
        Picker(WidgetMenuText.style, selection: $settings.widget.style) {
            Text(WidgetMenuText.followTheme).tag(ThemeID?.none)
            Divider()
            ForEach(ThemeID.allCases, id: \.self) { Text(SettingsText.theme($0)).tag(ThemeID?.some($0)) }
        }
        Divider()
        Button(WidgetMenuText.hide) { settings.widget.enabled = false }
        Button(WidgetMenuText.settings, action: openSettings)
    }
}

/// Answer buttons come alive half a second after they appear and stay dead while the widget is dragged,
/// so a click meant for the desktop or a drag never approves anything.
private struct ArmedRow<Content: View>: View {
    let key: String
    let dragging: Bool
    @ViewBuilder var content: () -> Content
    @State private var armed = false

    var body: some View {
        content()
            .allowsHitTesting(armed && !dragging)
            .task(id: key) {
                armed = false
                try? await Task.sleep(for: .milliseconds(500))
                armed = true
            }
    }
}

private struct WidgetProjectHeader: View {
    let name: String
    @Environment(\.theme) private var theme
    var body: some View {
        Text(theme.headingPrefix + (theme.headingUppercase ? name.uppercased() : name))
            .font(theme.headingFont).tracking(theme.headingUppercase ? 0.8 : 0)
            .foregroundStyle(theme.headingUppercase ? Ink.dim : Ink.secondary)
            .lineLimit(1)
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 2)
    }
}

/// One agent: the notch's row parts, the folded subagents as a counter, the run time ticking on the right.
private struct WidgetRow: View {
    let agent: Agent
    var folded = 0
    var small = false
    var indent = false
    var last = false
    let select: (Agent) -> Void
    let open: (Agent) -> Void
    @State private var hover = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            if indent { TreeLine(last: last).frame(width: 12) }
            RowParts(agent: agent, small: small, excluding: [.runningTime])
                .opacity(agent.state.isLive ? 1 : 0.6)
            Spacer(minLength: 4)
            if folded > 0 { Text("+\(folded)").font(.system(size: 10.5, weight: .medium)).foregroundStyle(dim) }
            WidgetClock(agent: agent)
        }
        .padding(.horizontal, 14 + theme.rowInset)
        .frame(minHeight: 22)
        .background { if hover { ThemeRowFill(style: Ink.hover) } }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { RowClick.isDouble ? open(agent) : select(agent) }
    }
}

/// "12:40" while the agent runs; nothing once it is done.
struct WidgetClock: View {
    let agent: Agent
    var body: some View {
        if agent.state.isLive, agent.startedAt > 0 {
            SurfaceTimeline(every: Date().timeIntervalSince1970 - agent.startedAt < 3600 ? 1 : 60) { date in
                if let text = Self.text(startedAt: agent.startedAt, now: date.timeIntervalSince1970) {
                    Text(text).font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(Ink.secondary)
                }
            }
        }
    }

    /// m:ss under an hour, then h:mm; over two days is a start time from somewhere else.
    static func text(startedAt: Double, now: Double) -> String? {
        let elapsed = now - startedAt
        guard elapsed.isFinite, elapsed >= 0, elapsed < 2 * 86_400 else { return nil }
        let s = Int(elapsed)
        if s < 3600 { return String(format: "%d:%02d", s / 60, s % 60) }
        return String(format: "%d:%02d %@", s / 3600, s % 3600 / 60, Loc.t("h", "ч"))
    }
}
