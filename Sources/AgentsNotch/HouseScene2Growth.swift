import Foundation

/// How far each project's room has grown, by the same rules as the page (room/index.html growthNote / growthLevel): every
/// distinct agent id a project has ever had counts once, and the room's level is the last GROWTH_STEPS entry the count reaches.
/// The page keeps its numbers in its own WebKit localStorage, which cannot be read without loading the page, so the SpriteKit
/// house keeps its own count here (UserDefaults) and starts it from zero.
final class HouseGrowthStore {
    static let steps = [0, 2, 6, 15]
    static let maxIds = 150
    struct Entry: Codable, Equatable { var n = 0; var ids: [String] = [] }

    private let defaults: UserDefaults, key: String
    private(set) var entries: [String: Entry]

    init(defaults: UserDefaults = .standard, key: String = "houseGrowth.v1") {
        self.defaults = defaults; self.key = key
        entries = (defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) }) ?? [:]
    }

    /// Counts the agents' ids; true when some project's level changed.
    @discardableResult
    func note(_ agents: [(id: String, project: String)]) -> Bool {
        var changed = false, levelChanged = false
        for a in agents {
            let p = a.project.isEmpty ? "—" : a.project
            var e = entries[p] ?? Entry()
            if e.ids.contains(a.id) { continue }
            let before = Self.level(e.n)
            e.ids.append(a.id)
            if e.ids.count > Self.maxIds { e.ids.removeFirst() }
            e.n += 1
            entries[p] = e
            changed = true
            if Self.level(e.n) != before { levelChanged = true }
        }
        if changed, let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
        return levelChanged
    }

    static func level(_ n: Int) -> Int {
        var l = 0
        for (i, s) in steps.enumerated() where n >= s { l = i }
        return l
    }

    /// The scene's growth map: room key ("p:" + project) → level, for the levels above zero.
    func levels(projects: [String]) -> [String: Int] {
        var out: [String: Int] = [:]
        for p in projects {
            let l = Self.level(entries[p.isEmpty ? "—" : p]?.n ?? 0)
            if l > 0 { out["p:" + p] = l }
        }
        return out
    }
}
