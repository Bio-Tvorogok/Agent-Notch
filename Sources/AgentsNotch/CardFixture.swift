import Foundation
import NotchCore

enum CardFixture {
    static let agent = Agent(id: "card-fixture", vendor: .codex, title: CardFixtureText.title,
                             model: "gpt-6.1-sol", effort: .high, state: .working, project: "Agents Notch",
                             cwd: "/tmp/agents-notch", branch: "feat/ui-card", worktree: "ui-card")
    static var detail: AgentDetail {
        AgentDetail(plan: [PlanItem(text: CardFixtureText.completed, status: .done),
                           PlanItem(text: CardFixtureText.active, status: .active),
                           PlanItem(text: CardFixtureText.todo, status: .todo)],
                    files: [FileChange(path: "Sources/AgentsNotch/CardView.swift", added: 96, removed: 3)],
                    commands: [CommandRun(command: "./scripts/build.sh", ok: true),
                               CommandRun(command: "./scripts/test.sh", ok: false),
                               CommandRun(command: "./scripts/test.sh", ok: true)],
                    lastMessage: CardFixtureText.message,
                    errors: [DetailError(text: CardFixtureText.error, count: 2)],
                    meta: DetailMeta(model: "gpt-6.1-sol", effort: .high,
                                     startedAt: Date().timeIntervalSince1970 - 732, branch: "feat/ui-card", worktree: "ui-card"))
    }
}

private enum CardFixtureText {
    static let title = "Карточка агента"
    static let completed = "Подключить чтение журнала"
    static let active = "Проверить вкладки карточки"
    static let todo = "Проверить переход в окно агента"
    static let message = "Карточка читает журнал в фоне. Осталось проверить переход между окнами."
    static let error = "Не найден файл проверки"
}
