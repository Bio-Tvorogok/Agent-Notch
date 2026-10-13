import Foundation
import NotchCore

/// What the toast shows.
struct FinishNotice: Equatable {
    let agent: Agent
    let title: String
    let line: String
    let preview: String?
}

/// Turns "an agent finished" into a notice: reads the session log off the main thread, asks git for the commit hash
/// only when the run made a commit, and hands the result back on the main actor.
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
            let hash = FinishSummary.madeCommit(detail, since: f.workedSince) ? Self.shortHead(a.cwd) : nil
            let n = FinishNotice(agent: a, title: a.title, line: FinishSummary.line(detail, since: f.workedSince, commit: hash),
                                 preview: FinishSummary.preview(detail))
            Task { @MainActor in self?.onNotice(n) }
        }
    }

    /// Short hash of HEAD in the agent's folder, or nil.
    nonisolated private static func shortHead(_ cwd: String?) -> String? {
        guard let cwd, FileManager.default.fileExists(atPath: cwd) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd, "rev-parse", "--short", "HEAD"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return p.terminationStatus == 0 && text.range(of: #"^[0-9a-f]{4,40}$"#, options: .regularExpression) != nil ? text : nil
    }
}
