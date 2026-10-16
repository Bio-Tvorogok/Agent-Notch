import Foundation
import NotchCore

/// What the toast shows.
struct FinishNotice: Equatable {
    let agent: Agent
    let title: String
    let line: String
    let preview: String?
}

/// Reads the finished session off the main thread and returns its notice on the main actor.
@MainActor
final class FinishNotifier {
    var onNotice: (FinishNotice) -> Void = { _ in }
    private var watcher = FinishWatcher()
    private let queue = DispatchQueue(label: "agents-notch.finish", qos: .utility)

    /// Feed it every poll.
    func check(_ agents: [Agent]) {
        let finished = watcher.update(agents, now: Date().timeIntervalSince1970)
        guard AppSettings.shared.finishToast else { return }
        for f in finished { notice(for: f) }
    }

    private func notice(for f: Finished) {
        let a = f.agent
        queue.async { [weak self] in
            let detail = a.logPath.flatMap { DetailReader.read(path: $0, vendor: a.vendor) } ?? AgentDetail()
            let n = FinishNotice(agent: a, title: a.title, line: FinishSummary.line(detail, since: f.workedSince),
                                 preview: FinishSummary.preview(detail))
            Task { @MainActor in self?.onNotice(n) }
        }
    }

}
