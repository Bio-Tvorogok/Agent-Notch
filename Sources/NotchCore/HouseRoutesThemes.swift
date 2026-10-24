import Foundation

public enum HouseRoutes {
    public struct Theme: Codable, Sendable {
        public let hub: [Double]
        public let spots: [String: [[Double]]]
    }
    // THEMES / YARD_THEME navigation data. Keep category/spot order and height.
    // Selection and occupancy rules are deliberately left to stage 2b.
    public static let themes: [String: Theme] = [
        "bedroom": Theme(hub: [5.4, 3.3, 0], spots: [
            "seat": [[1.6, 6.3, 3], [3.2, 7.1, 1.5]],
            "work": [[6.7, 2.3, 6.6], [8.4, 2.3, 6.6]],
            "read": [[4.5, 4.8, 5], [6.8, 6, 5]],
            "web": [[3.65, 1.6, 0]],
            "sleep": [[0.85, 1.7, 10.6], [1.9, 1.7, 10.6]],
            "wait": [[7, 6.95, 0], [5.2, 7, 0], [7.6, 6.4, 0]],
            "pace": [[3.4, 3.3, 0], [5, 2.8, 0]],
            "task": [[6.6, 4.3, 0], [7.4, 5.2, 0]],
        ]),
        "server": Theme(hub: [6, 3.4, 0], spots: [
            "seat": [[1.7, 6.9, 5], [2.6, 6.9, 5], [1.4, 4.2, 3]],
            "work": [[7.4, 2.4, 6.6], [8.8, 2.4, 6.6]],
            "read": [[2.3, 2, 0], [3.7, 2, 0], [1.9, 2.6, 0]],
            "web": [[5.6, 1.5, 0]],
            "sleep": [[8.3, 5.4, 5.5], [9.25, 5.4, 5.5]],
            "wait": [[5, 6.4, 0], [4.4, 6.9, 0], [6.6, 6.9, 0]],
            "pace": [[3.2, 4.6, 0], [5.6, 3, 0]],
            "task": [[2.4, 5.4, 0], [3.4, 5.9, 0]],
        ]),
        "library": Theme(hub: [6.4, 3.4, 0], spots: [
            "seat": [[1.5, 7, 3], [1.6, 3, 5]],
            "work": [[8.5, 3.6, 6.6], [5.1, 6.2, 6.6]],
            "read": [[2.2, 1.9, 0], [3.1, 4.6, 6]],
            "web": [[4.7, 1.7, 0]],
            "sleep": [[7.95, 6.9, 6], [8.9, 6.9, 6]],
            "wait": [[4.6, 7, 0], [3.4, 7.3, 0], [4, 6.3, 0]],
            "pace": [[4.4, 3, 0], [6.1, 3.7, 0]],
            "task": [[5.6, 3.3, 0]],
        ]),
        "greenhouse": Theme(hub: [5, 3.2, 0], spots: [
            "seat": [[1.5, 6.6, 5], [2.7, 7.3, 1.5]],
            "work": [[7, 2.2, 6.6], [8.6, 2.2, 6.6]],
            "read": [[1.9, 2.4, 0], [3.7, 1.6, 0]],
            "web": [[5.2, 1.5, 0]],
            "sleep": [[7.9, 6, 12.6], [8.7, 6, 12.6]],
            "wait": [[5.4, 6.6, 0], [4.4, 7.1, 0], [6.2, 7.2, 0]],
            "pace": [[3.2, 3, 0], [5.2, 4.6, 0]],
            "task": [[5.6, 3.2, 0]],
        ]),
        "arcade": Theme(hub: [5.4, 3.4, 0], spots: [
            "seat": [[1.6, 6.5, 3], [2.7, 7.3, 3]],
            "work": [[8, 2.3, 6.6], [9.2, 2.3, 6.6]],
            "read": [[3.1, 2, 6.5], [3.1, 3.3, 6.5]],
            "web": [[5.1, 1.8, 0], [6.3, 1.8, 0]],
            "sleep": [[6.5, 5.7, 5], [7.7, 6.5, 5]],
            "wait": [[4.6, 6.8, 0], [3.4, 6.4, 0], [5.6, 7.2, 0]],
            "pace": [[4.6, 3.6, 0], [6, 3, 0]],
            "task": [[5.6, 4.7, 0]],
        ]),
        "kitchen": Theme(hub: [4.2, 3, 0], spots: [
            "wait": [[0.8, 2.6, 6.6], [0.8, 4.1, 6.6], [4.8, 5.6, 11.6], [6.8, 5.6, 11.6], [3.6, 1.7, 0], [8, 2.9, 0]],
            "cowork": [[0.8, 3.35, 6.6], [4.8, 5.6, 11.6], [6.8, 5.6, 11.6], [9.2, 6, 6.6]],
            "sleep": [[9.2, 6, 6.6], [8.8, 6.7, 6.6]],
            "pace": [[3.4, 3.4, 0], [7.4, 2.6, 0]],
            "coffee": [[1, 1.7, 0]],
        ]),
        "bath": Theme(hub: [3.4, 3.2, 0], spots: [
            "wash": [[3.3, 1.75, 0]],
            "shower": [[1.1, 1, 1.6]],
            "dry": [[2.45, 2.45, 0]],
            "wait": [[3, 3.4, 0], [3.8, 2.8, 0]],
            "pace": [[3, 3, 0], [4.2, 2.8, 0]],
        ]),
        "roof": Theme(hub: [5, 4, 0], spots: [
            "cat": [[1.05, 4.5, 0]],
            "sleep": [[3, 2.2, 4.4], [5, 2.2, 4.4], [7, 2.2, 4.4]],
            "cowork": [[3, 2.2, 4.4], [5, 2.2, 4.4], [7, 2.2, 4.4], [4.2, 5.6, 0]],
            "wait": [[6, 5, 0]],
            "pace": [[4, 4.5, 0], [6, 4, 0]],
            "look": [[5.6, 6.6, 0]],
        ]),
        "yard": Theme(hub: [8.9, 6.3, 0], spots: [
            "stroll": [[12.2, 3.7, 0], [10.6, 5.3, 0], [12.1, 6.85, 0], [5.4, 6.95, 0], [11.4, 3.8, 0], [8.1, 3.9, 0]],
            "bench": [[10, 4.55, 3.8], [10.55, 4.55, 3.8]],
            "swing": [[10.7, 7.05, 4.5]],
            "sleep": [[10, 4.55, 3.8], [10.55, 4.55, 3.8], [10.7, 7.05, 4.5]],
            "look": [[10.5, 5.6, 0], [11.9, 6.3, 0]],
            "water": [[10.4, 2.45, 0], [11.75, 3, 0]],
            "wait": [[8.9, 6.3, 0]],
            "pace": [[10.6, 5.3, 0], [11.4, 3.8, 0]],
            "mail": [[4.05, 6.95, 0]],
            "dog": [[15.55, 6.95, 0]],
            "romp": [[14.6, 2.2, 0], [15.6, 3, 0], [14.8, 4.6, 0], [15.9, 4.4, 0], [12.4, 6.9, 0]],
            "cowork": [[10, 4.55, 3.8], [10.55, 4.55, 3.8], [8.1, 3.9, 0], [11.4, 3.8, 0]],
        ]),
    ]

    /// Theme data by name; an unknown name uses the bathroom's, never traps.
    static func theme(_ name: String) -> Theme { themes[name] ?? themes["bath"] ?? Theme(hub: [3.4, 3.2, 0], spots: [:]) }
    static func same(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case let (a?, b?): return a.utf16.elementsEqual(b.utf16)
        case (nil, nil): return true
        default: return false
        }
    }
    // JS for-of visits Unicode scalars; charCodeAt(0) uses only the high
    // surrogate of an astral scalar (unlike nameHash, which visits both units).
    public static func hashStr(_ string: String) -> UInt32 {
        var h: UInt32 = 7
        for scalar in string.unicodeScalars {
            let v = scalar.value
            let first = v > 0xffff ? 0xd800 + ((v - 0x10000) >> 10) : v
            h = h &* 31 &+ first
        }
        return h
    }
}
