import Foundation

/// Made-up scenes for `--fixture <name>`: screenshots and checks without live agents.
public enum Fixtures {
    public static let names = ["one", "sub", "multi", "projects", "heavy", "ask", "question", "plan"]

    public static func agents(_ name: String) -> [Agent]? {
        var n = 0
        func a(_ v: Vendor, _ model: String, _ effort: Effort, _ title: String, _ state: AgentState,
               _ project: String = "wedding-app", parent: String? = nil, ask: String? = nil, act: String? = nil) -> Agent {
            n += 1
            return Agent(id: "fx-\(n)", vendor: v, title: title, model: model, effort: effort, state: state,
                         project: project, parentId: parent, ask: ask, startedAt: Double(n), activity: act)
        }
        switch name {
        case "one":
            return [a(.claude, "opus", .high, "fix/upload-compress", .working, act: "Bash · pnpm --filter api test")]
        case "sub":
            return [a(.claude, "opus", .high, "fix/upload-compress", .working),
                    a(.codex, "gpt-6.1-sol", .medium, "codex-job · schemas", .working, parent: "fx-1")]
        case "multi":
            return [a(.claude, "opus", .high, "fix/upload-compress", .working, act: "Agent · найти роуты загрузки"),
                    a(.claude, "haiku", .low, "Explore · роуты", .working, parent: "fx-1", act: "Grep · uploadRouter"),
                    a(.codex, "gpt-6.1-sol", .medium, "codex-job · schemas", .working, parent: "fx-1",
                      act: "shell · pnpm --filter shared typecheck"),
                    a(.claude, "sonnet", .medium, "test-writer", .done, parent: "fx-1"),
                    a(.codex, "gpt-6.1-sol", .high, "CONF-360", .waiting, ask: "rm -rf dist"),
                    a(.claude, "sonnet", .medium, "docs/upload", .working)]
        case "projects":
            return [a(.claude, "opus", .high, "fix/upload-compress", .working),
                    a(.claude, "opus", .high, "code-reviewer", .working, parent: "fx-1"),
                    a(.codex, "gpt-6-luna", .low, "codex-job · fixtures", .working, parent: "fx-1"),
                    a(.codex, "gpt-6.1-sol", .high, "CONF-360", .waiting, ask: "rm -rf dist"),
                    a(.claude, "opus", .xhigh, "v6/notch", .working, "agents-village"),
                    a(.claude, "haiku", .low, "Explore", .working, "agents-village", parent: "fx-5"),
                    a(.codex, "gpt-6-astra", .high, "release-notes", .error, "hexhaven")]
        case "heavy":
            return [a(.claude, "opus", .high, "fix/upload-compress", .working),
                    a(.claude, "opus", .high, "code-reviewer", .error, parent: "fx-1"),
                    a(.claude, "haiku", .low, "Explore · роуты", .working, parent: "fx-1"),
                    a(.claude, "haiku", .low, "Explore · тесты", .done, parent: "fx-1"),
                    a(.claude, "sonnet", .medium, "test-writer", .working, parent: "fx-1"),
                    a(.codex, "gpt-6.1-sol", .medium, "codex-job · schemas", .working, parent: "fx-1"),
                    a(.codex, "gpt-6-luna", .low, "codex-job · fixtures", .done, parent: "fx-1"),
                    a(.claude, "opus", .xhigh, "feat/guest-tg", .working),
                    a(.claude, "haiku", .low, "Explore", .working, parent: "fx-8"),
                    a(.claude, "sonnet", .medium, "test-writer", .working, parent: "fx-8"),
                    a(.codex, "gpt-6.1-sol", .medium, "codex-job · api", .working, parent: "fx-8"),
                    a(.claude, "sonnet", .medium, "browser-verifier", .done, parent: "fx-8"),
                    a(.codex, "gpt-6.1-sol", .high, "CONF-360", .waiting, ask: "rm -rf dist"),
                    a(.codex, "gpt-6.1-sol", .medium, "worker · migrate", .working, parent: "fx-13"),
                    a(.codex, "gpt-6-luna", .low, "worker · lint", .working, parent: "fx-13"),
                    a(.codex, "gpt-6-luna", .low, "worker · i18n", .working, parent: "fx-13"),
                    a(.codex, "gpt-6-astra", .high, "audit-b10", .working),
                    a(.codex, "gpt-6.1-sol", .medium, "worker · auth", .working, parent: "fx-17"),
                    a(.codex, "gpt-6.1-sol", .medium, "worker · money", .done, parent: "fx-17"),
                    a(.codex, "gpt-6-luna", .low, "worker · scan", .done, parent: "fx-17"),
                    a(.claude, "opus", .xhigh, "v6/notch", .working, "agents-village"),
                    a(.codex, "gpt-6-astra", .high, "release-notes", .error, "hexhaven")]
        case "ask", "question", "plan":
            return [a(.claude, "opus", .high, "fix/upload-compress", .working),
                    a(.claude, "haiku", .low, "Explore · роуты", .working, parent: "fx-1"),
                    a(.codex, "gpt-6.1-sol", .high, "CONF-360", .working),
                    a(.claude, "sonnet", .medium, "docs/upload", .done)]
        default:
            return nil
        }
    }

    /// Open permission requests for the scene: what the notch asks you to approve.
    public static func asks(_ name: String) -> [HookEvent] {
        if name == "question" { return [question] }
        if name == "plan" { return [plan] }
        guard name == "ask" else { return [] }
        return [HookEvent(vendor: .claude, name: "PermissionRequest", sessionId: "fx-1", tool: "Bash",
                          detail: "corepack pnpm --filter api exec vitest related --run",
                          full: "corepack pnpm --filter api exec vitest related --run \\\n  src/routes/upload.ts src/services/media.ts"),
                HookEvent(vendor: .codex, name: "PermissionRequest", sessionId: "fx-3", tool: "shell", detail: "rm -rf dist build")]
    }

    /// A multi-select question and a single-choice one, as AskUserQuestion sends them.
    static let question = HookEvent(
        vendor: .claude, name: "PermissionRequest", sessionId: "fx-1", tool: "AskUserQuestion", detail: "Как сжимать видео?",
        questions: [Question(question: "Как сжимать видео?", header: "Сжатие", options: [
            QuestionOption(label: "На клиенте", description: "WebCodecs в браузере гостя, сервер не нагружается"),
            QuestionOption(label: "На сервере", description: "ffmpeg в воркере, дольше, но предсказуемо")], multiSelect: false)],
        toolInput: #"{"questions":[{"header":"Сжатие","multiSelect":false,"options":[{"description":"WebCodecs","label":"На клиенте"},{"description":"ffmpeg","label":"На сервере"}],"question":"Как сжимать видео?"}]}"#)

    /// A short plan, as ExitPlanMode sends it.
    static let plan = HookEvent(
        vendor: .claude, name: "PermissionRequest", sessionId: "fx-1", tool: "ExitPlanMode", detail: "план",
        plan: """
        1. Прочитать загрузку в apps/app/features/upload
        2. Добавить сжатие через WebCodecs до 720p
        3. Покрыть тестами пограничные размеры
        4. Проверить на телефоне через agent-browser
        """, toolInput: #"{"plan":"1. Прочитать загрузку"}"#)
}
