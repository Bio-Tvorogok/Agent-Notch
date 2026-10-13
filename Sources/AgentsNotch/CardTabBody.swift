import SwiftUI
import NotchCore

struct CardTabBody: View {
    let detail: AgentDetail
    let tab: CardTab
    let blocks: [CardBlock]
    let cwd: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch tab {
            case .done:
                plan(empty: CardText.noDone)
                if blocks.contains(.commands), !detail.commands.isEmpty {
                    section(CardText.commands) { commands(limit: 5) }
                }
                if blocks.contains(.lastMessage), let message = detail.lastMessage, !message.isEmpty {
                    section(CardText.message) { Text(message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                }
            case .remaining: plan(empty: CardText.noRemaining)
            case .files:
                if detail.files.isEmpty { Text(CardText.noFiles).foregroundStyle(dim) }
                ForEach(Array(detail.files.enumerated()), id: \.offset) { _, file in
                    HStack(alignment: .top, spacing: 5) {
                        Text(CardFormat.path(file.path, cwd: cwd ?? detail.meta.cwd, home: FileManager.default.homeDirectoryForCurrentUser.path))
                            .font(.system(size: 11, design: .monospaced)).lineLimit(3).truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer(minLength: 2)
                        Text("+\(file.added)").foregroundStyle(Ink.working)
                        Text("−\(file.removed)").foregroundStyle(Ink.error)
                    }
                }
            case .prompts:
                let prompts = CardContent.prompts(detail)
                if prompts.start == nil && prompts.later.isEmpty { Text(CardText.noPrompts).foregroundStyle(dim) }
                if let start = prompts.start {
                    section(CardText.start) { PromptBubble(prompt: start) }
                } else if !prompts.later.isEmpty {
                    Text(CardText.startLost).font(.system(size: 10.5)).foregroundStyle(dim)
                }
                if !prompts.later.isEmpty {
                    section(CardText.later) {
                        ForEach(Array(prompts.later.enumerated()), id: \.offset) { _, prompt in PromptBubble(prompt: prompt) }
                    }
                }
            case .log:
                if (!blocks.contains(.commands) || detail.commands.isEmpty) && (!blocks.contains(.errors) || detail.errors.isEmpty) {
                    Text(CardText.noLog).foregroundStyle(dim)
                }
                if blocks.contains(.commands) { commands(limit: 30) }
                if blocks.contains(.errors), !detail.errors.isEmpty {
                    section(CardText.errors) {
                        ForEach(Array(detail.errors.enumerated()), id: \.offset) { _, error in
                            HStack(alignment: .top) {
                                Text(error.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                                Spacer(minLength: 4)
                                Text("×\(error.count)").monospacedDigit()
                            }.foregroundStyle(Ink.error)
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func plan(empty: String) -> some View {
        let items = CardContent.plan(detail, tab: tab)
        if items.isEmpty { Text(empty).foregroundStyle(dim) }
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            HStack(alignment: .top, spacing: 7) {
                Text(item.status == .done ? "✓" : item.status == .active ? "●" : "○")
                    .foregroundStyle(item.status == .done ? Ink.working : dim)
                Text(item.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
    }

    private func commands(limit: Int) -> some View {
        ForEach(Array(CardContent.commands(detail, limit: limit).enumerated()), id: \.offset) { _, command in
            HStack(alignment: .top, spacing: 7) {
                Text(CardContent.result(command))
                    .foregroundStyle(command.ok == true ? Ink.working : command.ok == false ? Ink.error : dim)
                VStack(alignment: .leading, spacing: 3) {
                    if command.isTest { Text(CardText.test).font(.system(size: 10)).foregroundStyle(dim) }
                    Text(command.command).font(.system(size: 11, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10.5, weight: .medium)).foregroundStyle(dim)
            content()
        }
    }
}

/// The owner's own words stand out from the agent's: a tinted block with a bar on the left.
struct PromptBubble: View {
    let prompt: UserPrompt
    @State private var expanded = false
    static let tint = Color(red: 0.29, green: 0.55, blue: 1)

    private var long: Bool { prompt.text.count > 160 || prompt.text.filter { $0 == "\n" }.count > 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let at = prompt.at {
                Text(Date(timeIntervalSince1970: at), format: .dateTime.hour().minute())
                    .font(.system(size: 10)).foregroundStyle(dim).monospacedDigit()
            }
            Text(prompt.text).lineLimit(expanded ? nil : 3).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if long {
                Button(expanded ? CardText.less : CardText.more) { expanded.toggle() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Self.tint)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Self.tint.opacity(0.16)))
        .overlay(alignment: .leading) { Rectangle().fill(Self.tint).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
