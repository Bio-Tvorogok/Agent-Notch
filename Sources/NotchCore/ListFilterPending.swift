import Foundation

extension ListFilter {
    /// A hidden request must return to its agent before its row disappears.
    public func requestsToPass(_ pending: [PendingAsk], project: (String?) -> String, answerFromNotch: Bool,
                               agents: [Agent] = []) -> [PendingAsk] {
        pending.filter { ask in
            shouldPass(ask.event, project: project(ask.event.cwd), answerFromNotch: answerFromNotch,
                       owner: agents.first { $0.id == ask.event.agentKey })
        }
    }
}
