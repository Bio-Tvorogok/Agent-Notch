import SwiftUI
import NotchCore

let dim = Ink.dim

/// The list under the notch: summary, what needs you, then projects → sessions → subagents.
struct PanelView: View {
    @ObservedObject var store: Store
    @EnvironmentObject private var settings: AppSettings
    /// Off for snapshots: ImageRenderer draws nothing inside a ScrollView.
    var scrolls = true
    var onHeight: (CGFloat) -> Void = { _ in }
    @State private var expanded: [String: Bool] = [:]
    private var theme: Theme { settings.currentTheme }

    var body: some View {
        let list = VStack(alignment: .leading, spacing: 0) { content(store.projects) }
            .padding(.vertical, 6)
            .modifier(Glow(color: theme.glow))
            .background(GeometryReader { g in Color.clear.preference(key: HeightKey.self, value: g.size.height) })
        Group {
            if scrolls { ScrollView { list } } else { list }
        }
        .onPreferenceChange(HeightKey.self) { h in onHeight(h) }
        .onChange(of: settings.rows.subagentTree) { _, _ in expanded = [:] }
        .frame(width: 380)
        .themeSurface(theme)
        .themed(theme)
        .font(.system(size: 12, design: theme.design))
        // «Терминал» keeps the system label colour its rows always had.
        .foregroundStyle(theme.id == .terminal ? AnyShapeStyle(.primary) : AnyShapeStyle(Ink.text))
    }

    @ViewBuilder private func content(_ projects: [ProjectNode]) -> some View {
        if projects.isEmpty {
            PanelHeader(usage: store.usage).padding(.horizontal, 12)
            UsageInline(usage: store.usage)
            Note(text: SettingsListText.empty(minutes: settings.appearance.finishedMinutes))
        } else {
            Summary(projects: projects, usage: store.usage)
            UsageInline(usage: store.usage)
            let items = attention(projects)
            let firstAsk = store.hooks.pending.first?.event.agentKey
            ForEach(items, id: \.agent.id) { item in
                AttentionRow(item: item, multi: projects.count > 1, store: store, first: item.agent.id == firstAsk)
            }
            ForEach(settings.listSections(projects)) { p in
                if settings.rows.groupByProject && projects.count > 1 { ProjectHeader(project: p) }
                ForEach(p.sessions) { s in session(s) }
            }
        }
    }

    @ViewBuilder private func session(_ s: SessionNode) -> some View {
        let open = settings.rows.subagentTree.showsChildren(override: expanded[s.id], kids: s.kids)
        Row(action: { store.select(s.agent) }, open: { store.open(s.agent) }) {
            RowParts(agent: s.agent)
            if !s.kids.isEmpty && (s.kids.count > 2 || !open) {
                Button { expanded[s.id] = !open } label: {
                    HStack(spacing: 2) {
                        if !open && settings.rows.subagentTree != .hidden { ForEach(s.kids) { k in AgentStatusMark(agent: k, small: true) } }
                        Text(settings.rows.subagentTree == .hidden ? "\(s.kids.count)" : (open ? "▾" : "▸ \(s.kids.count)")).foregroundStyle(dim).padding(.leading, 3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(settings.rows.subagentTree == .hidden)
            }
        }
        if open {
            // Finished subagents fold into one line; each mark still opens its card.
            let done = s.doneKids
            let rows = s.liveKids.count + (done.isEmpty ? 0 : 1)
            ForEach(Array(s.liveKids.enumerated()), id: \.element.id) { i, k in
                Row(indent: true, last: i == rows - 1, action: { store.select(k) }, open: { store.open(k) }) {
                    RowParts(agent: k, small: true)
                }
            }
            if !done.isEmpty {
                Row(indent: true, last: true, action: done.count == 1 ? { store.select(done[0]) } : nil,
                    open: done.count == 1 ? { store.open(done[0]) } : nil) {
                    HStack(spacing: 2) {
                        ForEach(done) { k in
                            Button { RowClick.isDouble ? store.open(k) : store.select(k) } label: { AgentStatusMark(agent: k, small: true).padding(3) }.buttonStyle(.plain)
                        }
                    }
                    Text(done.count == 1 ? "\(done[0].title) — " + Loc.t("done", "готово") : Loc.t("\(done.count) more done", "ещё \(done.count) готово"))
                        .foregroundStyle(dim).lineLimit(1)
                    Spacer()
                }
            }
        }
    }

    private func attention(_ projects: [ProjectNode]) -> [AttentionItem] {
        projects.flatMap { p in
            p.sessions.flatMap { s in
                s.all.filter(\.state.needsAttention).map { a in
                    AttentionItem(agent: a, project: p.name, parent: a.id == s.id ? nil : s.agent.title)
                }
            }
        }
        .sorted { $0.agent.state < $1.agent.state }
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct AttentionItem {
    let agent: Agent
    let project: String
    let parent: String?
}

private struct AttentionRow: View {
    let item: AttentionItem
    let multi: Bool
    @ObservedObject var store: Store
    /// The first open request answers to the hotkeys; its row shows them.
    var first = false
    @Environment(\.theme) private var theme

    var body: some View {
        let a = item.agent
        let waiting = a.state == .waiting
        let ask = store.pending(for: a)
        HStack(alignment: .top, spacing: 7) {
            AgentStatusMark(agent: a).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("\(a.vendor == .claude ? "Claude" : "Codex") · \(a.title)").lineLimit(1)
                    if let parent = item.parent { Text("← \(parent)").foregroundStyle(dim).lineLimit(1) }
                    if multi { Text(item.project).foregroundStyle(dim).lineLimit(1) }
                }
                .contentShape(Rectangle()).onTapGesture { RowClick.isDouble ? store.open(a) : store.select(a) }
                if let ask, ask.event.isQuestion {
                    QuestionChoices(ask: ask, store: store).id(ask.ticket)
                } else if let ask, ask.event.isPlan {
                    PlanChoices(ask: ask, store: store).id(ask.ticket)
                } else if let ask {
                    Request(event: ask.event)
                    Choices(ask: ask, store: store, hint: first)
                } else {
                    Text(waiting ? Loc.t("asks: ", "просит: ") + (a.ask ?? Loc.t("approval", "подтверждение")) : Loc.t("repeats the same error", "повторяет одну и ту же ошибку"))
                        .foregroundStyle(waiting ? Ink.askText : dim).lineLimit(1).truncationMode(.middle)
                        .font(.system(size: 11))
                }
            }
            Spacer(minLength: 6)
            if ask == nil {
                Button(waiting ? Loc.t("Answer", "Ответить") : Loc.t("Chat", "Чат")) { store.open(a) }
                    .buttonStyle(Pill(primary: waiting))
            }
        }
        .padding(.horizontal, 12 + theme.rowInset).padding(.vertical, 6 + (theme.rowInset > 0 ? 2 : 0))
        .background(ThemeRowFill(style: waiting ? Ink.waitingBg : Ink.errorBg))
        .padding(.vertical, theme.rowInset > 0 ? 2 : 0)
    }
}

/// What exactly the agent wants to run: tool, then the command or file in monospace.
private struct Request: View {
    let event: HookEvent
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(event.tool.map { $0.hasPrefix("mcp__") ? "MCP" : $0 } ?? Loc.t("action", "действие")).foregroundStyle(dim)
            // The approval row shows exactly what gets approved, whole (up to 12 lines), never the shortened activity line.
            Text(event.full ?? Loc.t("no details", "без подробностей"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(event.isRisky ? Ink.error : Ink.code)
                .lineLimit(event.isLong ? 12 : 1).truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .font(.system(size: 11))
    }
}

private struct Choices: View {
    let ask: PendingAsk
    let store: Store
    let hint: Bool
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        HStack(spacing: 6) {
            Button(SettingsListText.allow(hint: hint && !ask.event.needsClick, shortcut: settings.shortcuts.allow)) { store.decide(ask, .allow) }
                .buttonStyle(Pill(primary: true))
            AlwaysButton(ask: ask, store: store)
            Button(SettingsListText.deny(hint: hint, shortcut: settings.shortcuts.deny)) { store.decide(ask, .deny) }
                .buttonStyle(Pill(primary: false))
            Button(Loc.t("In the agent window", "В окне агента")) { store.decide(ask, .pass) }
                .buttonStyle(.plain).foregroundStyle(dim).font(.system(size: 11)).lineLimit(1)
            if ask.event.isRisky { Text(Loc.t("dangerous", "опасно")).foregroundStyle(Ink.error).font(.system(size: 10.5, weight: .medium)) }
        }
        .padding(.top, 2)
    }
}

private struct Summary: View {
    let projects: [ProjectNode]
    let usage: UsageModel
    var body: some View {
        let live = projects.flatMap(\.live)
        let waiting = live.filter { $0.state == .waiting }.count
        let errors = live.filter { $0.state == .error }.count
        VStack(alignment: .leading, spacing: 6) {
            PanelHeader(usage: usage)
        HStack(spacing: 10) {
            VendorCount(vendor: .claude, n: live.filter { $0.vendor == .claude }.count, label: "Claude")
            VendorCount(vendor: .codex, n: live.filter { $0.vendor == .codex }.count, label: "Codex")
            if waiting > 0 { Text(Loc.t("\(waiting) waiting", "\(waiting) ждёт")).foregroundStyle(Ink.waiting) }
            if errors > 0 { Text(Loc.t("\(errors) with errors", "\(errors) с ошибкой")).foregroundStyle(Ink.error) }
            Spacer()
            Text(projects.count > 1 ? Loc.t("projects: \(projects.count)", "проектов: \(projects.count)") : projects[0].name).foregroundStyle(dim)
        }
        }
        .font(.system(size: 11))
        .foregroundStyle(Ink.secondary)
        .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.rule).frame(height: 0.5) }
        .padding(.bottom, 4)
    }
}

private struct VendorCount: View {
    let vendor: Vendor
    let n: Int
    let label: String
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        if n > 0 {
            HStack(spacing: 4) {
                ThemedVendorMark(vendor: vendor)
                Text("\(n) \(label)")
            }
        }
    }
}

private struct ProjectHeader: View {
    let project: ProjectNode
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.theme) private var theme
    var body: some View {
        let live = project.live
        HStack(spacing: 8) {
            Text(theme.headingPrefix + (theme.headingUppercase ? project.name.uppercased() : project.name))
                .font(theme.headingFont).tracking(theme.headingUppercase ? 0.8 : 0).foregroundStyle(theme.headingUppercase ? Ink.dim : Ink.strong)
            Spacer()
            ForEach([Vendor.claude, .codex], id: \.self) { v in
                let n = live.filter { $0.vendor == v }.count
                if n > 0 {
                    HStack(spacing: 3) {
                        ThemedVendorMark(vendor: v)
                        Text("\(n)").foregroundStyle(dim).font(.system(size: 11))
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, theme.headingUppercase ? 12 : 8).padding(.bottom, theme.headingUppercase ? 4 : 3)
    }
}

private struct Note: View {
    let text: String
    var body: some View {
        Text(text).foregroundStyle(dim).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

/// The second click of a double click: the tap fires on every click, so a single click is never delayed.
private enum RowClick {
    @MainActor static var isDouble: Bool {
        // clickCount throws on anything but a mouse event (keyboard or VoiceOver activation).
        guard let e = NSApp.currentEvent, e.type == .leftMouseUp || e.type == .leftMouseDown else { return false }
        return e.clickCount == 2
    }
}

/// A list row: hover highlight, optional tree connector for subagents, click selects, double click opens the agent's window.
private struct Row<Content: View>: View {
    var indent = false
    var last = false
    var action: (() -> Void)?
    var open: (() -> Void)?
    @ViewBuilder var content: () -> Content
    @State private var hover = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            if indent { TreeLine(last: last).frame(width: 12) }
            content()
        }
        .padding(.horizontal, 12 + theme.rowInset)
        .frame(minHeight: 22)
        .background { if hover && action != nil { ThemeRowFill(style: Ink.hover) } }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { if RowClick.isDouble, let open { open() } else { action?() } }
    }
}

private struct TreeLine: View {
    let last: Bool
    var body: some View {
        GeometryReader { g in
            Path { p in
                // Starts a little below the top so it never touches a wrapped line of the row above.
                let x: CGFloat = 4, mid = g.size.height / 2
                p.move(to: CGPoint(x: x, y: 4))
                p.addLine(to: CGPoint(x: x, y: last ? mid : g.size.height))
                p.move(to: CGPoint(x: x, y: mid))
                p.addLine(to: CGPoint(x: g.size.width, y: mid))
            }
            .stroke(Ink.faint, lineWidth: 1)
        }
    }
}

struct Pill: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View { PillBody(configuration: configuration, primary: primary) }
}

private struct PillBody: View {
    let configuration: ButtonStyleConfiguration
    let primary: Bool
    @Environment(\.theme) private var theme
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.pillRadius, style: theme.cornerStyle)
        let pressed = configuration.isPressed
        if theme.bracketPills {
            // A terminal menu item: brackets, inverted when it is the default choice.
            HStack(spacing: 0) { Text("[ "); configuration.label; Text(" ]") }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, primary ? 2 : 0).padding(.vertical, 1)
                .background(Rectangle().fill(primary || pressed ? AnyShapeStyle(Ink.primary) : AnyShapeStyle(Color.clear)))
                .foregroundStyle(primary || pressed ? Ink.primaryText : Ink.pillText)
                .fixedSize()
        } else {
            pill(shape: shape, pressed: pressed)
        }
    }

    private func pill(shape: RoundedRectangle, pressed: Bool) -> some View {
        configuration.label
            .font(.system(size: 11, weight: theme.hardShadow ? .heavy : primary && theme.id != .terminal ? .semibold : .medium,
                          design: theme.id == .console ? .monospaced : theme.design))
            .padding(.horizontal, theme.pillRadius > 20 ? 10 : 8).padding(.vertical, theme.pillRadius > 20 || theme.hardShadow ? 3 : 2)
            .background {
                if primary, let colors = theme.primaryGradient {
                    shape.fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                } else {
                    shape.fill(primary ? Ink.primary : Ink.pill)
                }
            }
            .overlay {
                if theme.hardShadow { shape.strokeBorder(Color.black, lineWidth: 1.5) }
                else if !primary { shape.strokeBorder(Ink.pillStroke, lineWidth: theme.id == .synthwave || theme.id == .phosphor || theme.id == .blueprint ? 1 : 0.5) }
            }
            .foregroundStyle(primary ? Ink.primaryText : Ink.pillText)
            // Neo-brutal buttons sit on a hard black shadow and sink into it when pressed.
            .background { if theme.hardShadow { shape.fill(Color.black).offset(x: pressed ? 0 : 2, y: pressed ? 0 : 2) } }
            .offset(x: theme.hardShadow && pressed ? 2 : 0, y: theme.hardShadow && pressed ? 2 : 0)
            .shadow(color: primary && theme.id == .synthwave ? Color(red: 1, green: 0.3, blue: 0.7).opacity(0.7) : .clear, radius: 6)
            .opacity(!theme.hardShadow && pressed ? 0.7 : 1)
            .padding(.trailing, theme.hardShadow ? 2 : 0).padding(.bottom, theme.hardShadow ? 2 : 0)
            .fixedSize()
    }
}

/// Text that gives off light. Themes without it get no shadow at all: even a clear one moves the list offscreen and changes how it renders.
private struct Glow: ViewModifier {
    let color: Color?
    func body(content: Content) -> some View {
        if let color { content.shadow(color: color, radius: 3) } else { content }
    }
}
