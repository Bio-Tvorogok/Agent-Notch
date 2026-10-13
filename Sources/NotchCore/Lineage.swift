import Foundation

/// Who started whom. Claude Code puts `CLAUDE_CODE_SESSION_ID` and Codex puts `CODEX_THREAD_ID` into the
/// environment of every command they run, so a child agent carries its parents' ids no matter which vendor
/// started it, and even after its process was detached from the parent.
public enum Lineage {
    static let keys = ["CODEX_THREAD_ID=", "CLAUDE_CODE_SESSION_ID="]

    /// The agent ids found in one process environment.
    static func parents(env: [String]) -> [String] {
        keys.compactMap { k in env.first { $0.hasPrefix(k) }.map { String($0.dropFirst(k.count)) } }.filter { !$0.isEmpty }
    }

    /// Agent → its parent. A chain across vendors leaves several ids (Claude A → Codex B → Claude C gives C both
    /// A and B); the nearest parent is the candidate the others are ancestors of.
    static func resolve(_ candidates: [String: [String]], known: Set<String>) -> [String: String] {
        func usable(_ id: String) -> [String] { (candidates[id] ?? []).filter { $0 != id && known.contains($0) } }
        func ancestors(_ id: String) -> Set<String> {
            var seen = Set<String>(), queue = usable(id)
            while let next = queue.popLast(), seen.count < 64 {
                if seen.insert(next).inserted { queue += usable(next) }
            }
            return seen
        }
        var out: [String: String] = [:]
        for id in candidates.keys {
            let list = usable(id)
            out[id] = list.max { a, b in
                let ca = ancestors(a).intersection(list).count, cb = ancestors(b).intersection(list).count
                return ca != cb ? ca < cb : list.firstIndex(of: a)! > list.firstIndex(of: b)!
            }
        }
        return out
    }
}
