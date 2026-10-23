import Foundation
import NotchCore

/// How far each project's room has grown. Native is the only store (UserDefaults `houseGrowth.v1`): the SpriteKit house's
/// HouseBehaviour is seeded from here and written back after its agents changed. The old WebKit page kept its own copy in
/// localStorage; `importLegacyPage` takes that over once. The rules are the page's (growthNote / growthLevel): every distinct agent
/// id a project has ever had counts once (the last 150 are remembered) and the room's level is the last GROWTH_STEPS entry
/// [0, 2, 6, 15] the count reaches. The JSON is the page's `{project: {n, ids}}`.
final class HouseGrowthStore {
    static let steps = [0, 2, 6, 15]
    struct Entry: Codable, Equatable { var n = 0; var ids: [String] = [] }

    private let defaults: UserDefaults, key: String
    private(set) var entries: [String: Entry]

    init(defaults: UserDefaults = .standard, key: String = "houseGrowth.v1") {
        self.defaults = defaults; self.key = key
        entries = (defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) }) ?? [:]
    }

    static func level(_ n: Int) -> Int {
        var l = 0
        for (i, s) in steps.enumerated() where n >= s { l = i }
        return l
    }

    /// The count of this project (a project without a name is "—", as on the page).
    func level(project: String) -> Int { Self.level(entries[project.isEmpty ? "—" : project]?.n ?? 0) }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key) }
    }

    /// The behaviour starts from the stored counts.
    func seed(_ b: HouseBehaviour) {
        b.growth = entries.sorted { $0.key < $1.key }.map { .init(project: $0.key, n: $0.value.n, ids: $0.value.ids) }
    }

    /// Stores the behaviour's counts; true when something changed.
    @discardableResult
    func capture(from b: HouseBehaviour) -> Bool {
        var e: [String: Entry] = [:]
        for g in b.growth { e[g.project] = Entry(n: g.n, ids: g.ids) }
        guard e != entries else { return false }
        entries = e
        save()
        return true
    }

    /// A saved count in the page's shape (`{project: {n, ids}}`): per project the larger count wins. True when something changed.
    @discardableResult
    func merge(page: Any?) -> Bool {
        guard let dict = page as? [String: Any] else { return false }
        var changed = false
        for (project, raw) in dict {
            guard let o = raw as? [String: Any], let n = (o["n"] as? NSNumber)?.intValue, n >= 0 else { continue }
            let ids = ((o["ids"] as? [Any]) ?? []).compactMap { $0 as? String }.suffix(150)
            if n > (entries[project]?.n ?? -1) { entries[project] = Entry(n: n, ids: Array(ids)); changed = true }
        }
        if changed { save() }
        return changed
    }

    static let importedKey = "houseGrowth.legacyPageImported.v1"

    /// Once per user: takes over the growth the old WebKit page saved in its localStorage (WebKit's database under
    /// ~/Library/WebKit/<bundle id>). The flag is set even when nothing was found, so the database is read only on the first run.
    /// The old files stay where they are. Returns what was merged.
    @discardableResult
    func importLegacyPage(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/WebKit/\(Bundle.main.bundleIdentifier ?? "com.forichok.agents-notch")", isDirectory: true)) -> Bool {
        guard !defaults.bool(forKey: Self.importedKey) else { return false }
        defaults.set(true, forKey: Self.importedKey)
        return merge(page: HouseGrowthLegacy.readAll(root: root))
    }
}
