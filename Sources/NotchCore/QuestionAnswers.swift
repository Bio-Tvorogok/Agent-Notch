import Foundation

/// Builds answers from the current question's state before a click is submitted.
public enum QuestionAnswers {
    public static func build(questions: [Question], picked: [String: [String]], own: [String: String], ownOpen: Set<String>) -> [String: String]? {
        let current = Set(questions.map(\.question))
        guard !questions.isEmpty, Set(picked.keys).isSubset(of: current),
              Set(own.keys).isSubset(of: current), ownOpen.isSubset(of: current) else { return nil }
        var out: [String: String] = [:]
        for q in questions {
            let chosen = picked[q.question] ?? []
            let labels = Set(q.options.map(\.label))
            guard chosen.allSatisfy(labels.contains), Set(chosen).count == chosen.count,
                  q.multiSelect || chosen.count <= 1 else { return nil }
            let text = own[q.question]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if ownOpen.contains(q.question), !text.isEmpty {
                out[q.question] = text
            } else if !chosen.isEmpty {
                out[q.question] = q.options.map(\.label).filter(chosen.contains).joined(separator: ", ")
            } else {
                return nil
            }
        }
        return out
    }
}
