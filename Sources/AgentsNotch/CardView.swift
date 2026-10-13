import SwiftUI
import NotchCore

enum CardText {
    static let open = "Открыть"
    static let loading = "Читаем журнал…"
    static let unavailable = "Журнал пока недоступен"
    static let hidden = "Вкладки скрыты в настройках"
    static let noDone = "Пока нет завершённых задач"
    static let noRemaining = "Открытых задач нет"
    static let noFiles = "Изменённых файлов пока нет"
    static let noLog = "Команд и ошибок пока нет"
    static let commands = "Последние команды"
    static let message = "Последнее сообщение"
    static let errors = "Ошибки и повторы"
    static let test = "тест"
    static func cost(_ amount: String) -> String { "цена сессии " + amount }
    static let costHelp = "Примерная цена по публичным ценам моделей, это не счёт"
    static func tab(_ tab: CardTab) -> String {
        switch tab { case .done: "Сделано"; case .remaining: "Осталось"; case .files: "Файлы"; case .log: "Лог" }
    }
}

struct CardView: View {
    let agent: Agent
    let detail: AgentDetail?
    var loading = false
    var blocks: [CardBlock] = CardBlock.allCases
    var context: ContextUsage?
    var cost: SessionCost?
    var onOpen: () -> Void = {}
    @State private var tab: CardTab = .done

    private var tabs: [CardTab] { CardContent.tabs(blocks: blocks) }
    private var visibleTab: CardTab? { tabs.contains(tab) ? tab : tabs.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(12)
            Divider().overlay(Color(white: 0.23))
            HStack(spacing: 6) {
                ForEach(tabs, id: \.self) { item in
                    Button(CardText.tab(item)) { tab = item }
                        .buttonStyle(Pill(primary: visibleTab == item))
                }
            }.padding(10)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if loading { Text(CardText.loading).foregroundStyle(dim) }
                    else if let detail, let visibleTab {
                        CardTabBody(detail: detail, tab: visibleTab, blocks: blocks, cwd: agent.cwd)
                    } else { Text(tabs.isEmpty ? CardText.hidden : CardText.unavailable).foregroundStyle(dim) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .frame(width: 340)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.11)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(white: 0.23), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
        .font(.system(size: 12))
        .foregroundStyle(Color(white: 0.92))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                AgentStatusMark(agent: agent)
                Text(agent.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 4)
                Button(CardText.open, action: onOpen).buttonStyle(Pill(primary: false))
            }
            Text([agent.project, agent.branch ?? detail?.meta.branch, agent.worktree ?? detail?.meta.worktree]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .foregroundStyle(dim).lineLimit(2).truncationMode(.middle)
            if blocks.contains(.modelTime) {
                HStack(spacing: 6) {
                    if let model = detail?.meta.model ?? agent.model { Text(model).lineLimit(1).truncationMode(.middle) }
                    EffortBars(effort: detail?.meta.effort ?? agent.effort)
                    Spacer(minLength: 4)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let duration = CardFormat.runTime(startedAt: detail?.meta.startedAt, lastAt: detail?.meta.lastAt,
                                                             live: agent.state.isLive, now: context.date.timeIntervalSince1970) {
                            Text(duration).monospacedDigit()
                        }
                    }
                }.foregroundStyle(dim).font(.system(size: 10.5))
            }
            if blocks.contains(.contextCost), context != nil || CardFormat.cost(cost) != nil {
                HStack(spacing: 6) {
                    if let context { Text(UsageViewText.context(context)) }
                    Spacer(minLength: 4)
                    if let amount = CardFormat.cost(cost) { Text(CardText.cost(amount)).help(CardText.costHelp) }
                }.foregroundStyle(dim).font(.system(size: 10.5)).lineLimit(1)
            }
        }
    }
}

struct LiveCardView: View {
    @ObservedObject var model: CardDetailModel
    @ObservedObject var settings: AppSettings
    let onOpen: (Agent) -> Void

    var body: some View {
        if let agent = model.agent {
            CardView(agent: agent, detail: model.detail, loading: model.loading,
                     blocks: DisplayOrder.visible(settings.cardBlocks), context: model.context, cost: model.cost, onOpen: { onOpen(agent) })
                .id(agent.id)
                .environmentObject(settings)
        }
    }
}
