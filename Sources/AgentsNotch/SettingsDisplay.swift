import SwiftUI
import NotchCore

struct SettingsAppearance: View {
    @ObservedObject var settings: AppSettings
    @State private var rowOrder = false
    @State private var cardOrder = false
    private let rowSwitches: [RowPart] = [.model, .activity, .branch, .runningTime, .context, .cost]

    var body: some View {
        Form {
            Section {
                SettingsLivePreview(settings: settings).listRowInsets(EdgeInsets())
                SettingsPresetPicker(settings: settings)
            }
            Section(SettingsText.theme) {
                SettingsThemePicker(settings: settings)
            }
            Section(SettingsText.marks) {
                HStack(spacing: 10) {
                    ForEach([MarkStyle.dots, .logos, .logosMono], id: \.self) { style in
                        SettingsMarkCard(style: style, selected: settings.appearance.markStyle == style) { settings.appearance.markStyle = style }
                    }
                }.padding(.vertical, 4)
                Picker(SettingsText.markSize, selection: $settings.appearance.markSize) {
                    ForEach(MarkSize.allCases, id: \.self) { Text(SettingsText.name($0.rawValue)).tag($0) }
                }.pickerStyle(.segmented)
            }
            Section {
                ForEach(rowSwitches, id: \.self) { part in
                    Toggle(isOn: Binding(get: { settings.rowPartShown(part) }, set: { settings.setRowPart(part, shown: $0) })) {
                        SettingsLabel(SettingsText.name(part.rawValue), hint: SettingsText.rowHints[part])
                    }.toggleStyle(.switch)
                }
            } header: {
                HStack {
                    Text(SettingsText.inRow)
                    Spacer()
                    Button(SettingsText.order) { rowOrder = true }.controlSize(.small)
                }
            }
            Section {
                ForEach(CardTab.allCases, id: \.self) { tab in
                    let block = CardBlock(rawValue: tab.rawValue) ?? .done
                    Toggle(SettingsText.name(tab.rawValue), isOn: Binding(get: { settings.cardBlockShown(block) },
                                                                          set: { settings.setCardBlock(block, shown: $0) }))
                        .toggleStyle(.switch)
                }
            } header: {
                HStack {
                    SettingsLabel(SettingsText.card, hint: SettingsText.cardHelp)
                    Spacer()
                    Button(SettingsText.order) { cardOrder = true }.controlSize(.small)
                }
            }
        }
        .sheet(isPresented: $rowOrder) { SettingsOrderSheet(title: SettingsText.orderTitle, parts: $settings.rowParts) }
        .sheet(isPresented: $cardOrder) { SettingsOrderSheet(title: SettingsText.cardOrderTitle, parts: $settings.cardBlocks) }
    }
}

/// Кратко / Подробно / Всё; a fourth «Своё» segment appears only after a change by hand.
struct SettingsPresetPicker: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        let current = settings.preset
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: Binding<String>(
                get: { current?.rawValue ?? "own" },
                set: { if let preset = DisplayPreset(rawValue: $0) { settings.apply(preset) } })) {
                ForEach(DisplayPreset.allCases, id: \.self) { Text(SettingsText.name($0.rawValue)).tag($0.rawValue) }
                if current == nil { Text(SettingsText.own).tag("own") }
            }
            .pickerStyle(.segmented).labelsHidden()
            Text(SettingsText.presetHelp).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

struct SettingsMarkCard: View {
    let style: MarkStyle
    let selected: Bool
    let choose: () -> Void
    var body: some View {
        Button(action: choose) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    StatusMark(vendor: .claude, state: .working, isLight: false, style: style, size: 14)
                    StatusMark(vendor: .codex, state: .working, isLight: false, style: style, size: 14)
                }
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 6))
                .environment(\.colorScheme, .dark)
                Text(SettingsText.name(style.rawValue)).font(.system(size: 11)).multilineTextAlignment(.center)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).frame(height: 28, alignment: .top)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1),
                                                                    lineWidth: selected ? 2.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The real wing and list, fed a made-up scene, so every switch shows its effect at once.
struct SettingsLivePreview: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var store: Store

    init(settings: AppSettings) {
        self.settings = settings
        _store = StateObject(wrappedValue: {
            let store = Store(settings: settings)
            // Recent start times, so «Время работы» has something to show.
            let now = Date().timeIntervalSince1970
            store.useFixture((Fixtures.agents("multi") ?? []).enumerated().map { i, agent in
                var agent = agent
                agent.startedAt = now - Double(180 + i * 420)
                if agent.parentId == nil { agent.branch = agent.title }
                return agent
            })
            // Made-up amounts, so «Примерная цена сессии» shows its effect too.
            let costs = Dictionary(uniqueKeysWithValues: store.agents.enumerated().map { i, agent in
                (agent.id, SessionCost(tokens: 1, usd: 0.18 + Double(i) * 0.37))
            })
            store.usage.useFixture(limits: [], spend: [], contexts: [:], costs: costs, now: Date())
            return store
        }())
    }

    var body: some View {
        VStack(spacing: 8) {
            WingView(layout: store.layout)
                .padding(.horizontal, 14).frame(height: 26).frame(minWidth: 200)
                .background(UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9).fill(.black))
                .environment(\.colorScheme, .dark)
            PanelView(store: store, scrolls: false).fixedSize(horizontal: false, vertical: true)
                .scaleEffect(0.86, anchor: .top).frame(width: 380 * 0.86)
        }
        .frame(maxWidth: .infinity).frame(height: 200, alignment: .top).clipped()
        .background(LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.56), Color(red: 0.18, green: 0.22, blue: 0.32)],
                                   startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
        .environmentObject(settings)
        .environmentObject(store.usage)
    }
}
