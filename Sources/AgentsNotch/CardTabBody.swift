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
