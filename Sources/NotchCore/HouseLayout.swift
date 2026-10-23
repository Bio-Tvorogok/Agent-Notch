import Foundation

/// Pure geometry from room/index.html. Coordinates are JS art pixels unless a
/// field describes tiles (NX/NY, tx/ty/tz, ports, boxes and links). S = 2.
/// This is a fresh layout, with the home camera and drop = 0; animation state
/// retained by JS relayouts belongs to HouseSim, not this value.
public struct HouseLayout: Encodable, Sendable {
    public enum Style: String, Codable, Sendable { case islands, towers, steps }
    public struct Canvas: Codable, Sendable {
        public let width, height, dpr: Double
        public init(width: Double, height: Double, dpr: Double = 2) {
            self.width = width; self.height = height; self.dpr = dpr
        }
    }
    public struct Insets: Codable, Sendable {
        public let top, bottom, right: Double
        public init(top: Double = 0, bottom: Double = 0, right: Double = 0) {
            self.top = top; self.bottom = bottom; self.right = right
        }
    }
    public struct Room: Codable, Sendable {
        public let key, name, theme: String
        public var NX, NY: Double
        public var tower = 0, floor = 0
        public var tx = 0.0, ty = 0.0
        public var tz: Double? = 0
        public var ox = 0.0, oy = 0.0, drop = 0.0
        public var wx: Double? = 0, wy: Double? = 0
        /// JS `r.seed`: hashStr(key) % 97 (the yard's is fixed at 11); windows and lights read it.
        public var seed: Int { key == "__yard" ? 11 : Int(HouseLayout.hashStr(key) % 97) }
    }
    /// JS hashStr; one implementation, in HouseRoutes.
    static func hashStr(_ s: String) -> UInt32 { HouseRoutes.hashStr(s) }
    public struct Port: Codable, Sendable {
        public let kind: String
        public let q: [Double]
    }
    public struct YardPort: Codable, Sendable {
        public let q, d: [Double]
        public let opp: String
    }
    public struct Target: Codable, Sendable {
        public var room: String? = nil
        public var up: Bool? = nil
    }
    public struct Link: Codable, Sendable {
        public let kind, id, a, b: String
        public let pa, pb: Port
        public let A, B: [Double]
        public var axis: String? = nil
        public var z: Double? = nil
        public var len: Double
        public var ang: Double? = nil
        public var rise: Double? = nil
        public var steps: Int? = nil
        public var z0: Double? = nil
        public var lo: String? = nil
        public var hi: String? = nil
        public var targets: [Target]? = nil
    }
    public struct Shaft: Codable, Sendable {
        public let x0, y0, x1, y1, cx, cy: Double
    }
    public struct Cabin: Codable, Sendable {
        public let kind, id: String
        public let sh: Shaft
        public let z: Double
        public let level: Int
        public let len: Double
    }
    public struct LiftFloor: Codable, Sendable {
        public let room: String
        public let f: Int
        public let yoff, z, levelZ: Double
        /// null represents +Infinity in liftSlice's upper bound.
        public let slice: [Double?]
    }
    public struct Lift: Codable, Sendable {
        public let fl: [LiftFloor]
        public let shafts: [Shaft]
        public let cabins: [Cabin]
        public let x0, x1, y0, y1, top: Double
        /// JS liftZ: a stale floor number falls back to the last floor.
        public func liftZ(_ k: Int) -> Double {
            k == 0 ? -6 : (fl.indices.contains(k) ? fl[k] : fl[fl.count - 1]).z
        }
        public func liftSlice(_ f: Int) -> [Double?] { fl[f].slice }
    }
    public struct Yard: Codable, Sendable {
        public let on: Bool
        public let room: Room
        public let YD: [String: Double]
        public let YW: [[Double]]
        public let YUP: [Int]
        public let YGATE: [String: Int]
        public let ports: [String: YardPort]
        /// hullOf-style ground bounds: x0,y0,z0,x1,y1,z1.
        public let ground: [Double]
        public let gates: [String: Bool]
    }
    public struct Escape: Codable, Sendable {
        public let room, layer, shape: String
    }
    public struct Primitive: Codable, Sendable {
        /// box: one [x,y,z,w,d,h] in tiles; line/polygon: local art pixels.
        public let kind: String
        public let points: [[Double]]
    }
    public struct DrawItem: Codable, Sendable {
        public let key: String
        public var depth: Double? = nil
    }
    public struct View: Codable, Sendable {
        public let PXD, DPR, width, height, cssWidth, cssHeight, base: Double
        public let home, at: [Double]
    }
    public struct Frame: Codable, Sendable {
        public let ox, oy, drop: Double
        public init(ox: Double, oy: Double, drop: Double) { self.ox = ox; self.oy = oy; self.drop = drop }
        public func iso(_ x: Double, _ y: Double, _ z: Double) -> [Double] {
            [ox + (x - y) * 8 * 2, oy + drop + (x + y) * 4 * 2 - z * 2]
        }
    }
    public let rooms: [Room]
    public let lift: Lift?
    public let links: [Link]
    public let hulls: [[[Double]]]
    public let yard: Yard
    public let escapes: [Escape]
    public let escapeShapes: [String: [Primitive]]
    public let drawOrder: [DrawItem]
    public let view: View
    public let worldFrame: Frame
    /// How the rooms stand (islands: lift, yard and links; towers and steps: stacks joined by outside stairs). Not part of the page fixtures.
    public var style: Style = .islands

    // Keep lift:null explicit, just like the JS fixture; other optional fields
    // denote absent JS properties and are omitted by their synthesized encoders.
    enum CodingKeys: String, CodingKey { case rooms, lift, links, hulls, yard, escapes, escapeShapes, drawOrder, view, worldFrame }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rooms, forKey: .rooms); try c.encode(lift, forKey: .lift)
        try c.encode(links, forKey: .links); try c.encode(hulls, forKey: .hulls)
        try c.encode(yard, forKey: .yard); try c.encode(escapes, forKey: .escapes)
        try c.encode(escapeShapes, forKey: .escapeShapes); try c.encode(drawOrder, forKey: .drawOrder)
        try c.encode(view, forKey: .view); try c.encode(worldFrame, forKey: .worldFrame)
    }

    /// One room per distinct project, in first-seen order (ensureRoom). An empty
    /// project name becomes “—”, as in setAgents. Shared rooms always exist.
    /// Theme choices accept only PROJECT_THEMES; shared/unknown choices fall
    /// back to the name hash. No random numbers are consumed by JS or Swift.
    public static func make(projects: [String], layout: Style = .islands, canvas: Canvas,
                            insets: Insets = Insets(), themes: [String: String] = [:]) -> HouseLayout {
        HouseLayoutBuilder(projects: projects, style: layout, canvas: canvas, insets: insets,
                           themes: themes.map { ThemeChoice(project: $0.key, theme: $0.value) }).make()
    }

    /// Use this overload when exact JS names include canonically equivalent
    /// spellings: Swift dictionaries cannot hold both of those keys.
    public struct ThemeChoice: Sendable {
        public let project, theme: String
        public init(project: String, theme: String) { self.project = project; self.theme = theme }
    }
    public static func make(projects: [String], layout: Style = .islands, canvas: Canvas,
                            insets: Insets = Insets(), themes: [ThemeChoice]) -> HouseLayout {
        HouseLayoutBuilder(projects: projects, style: layout, canvas: canvas, insets: insets, themes: themes).make()
    }

    /// The page's extra screen (`?scene=extra`, layoutEmpty): no rooms, no links, only the canvas and its scale (VIEW.base = max(1, round(innerHeight * DPR / 170) / 4)).
    public static func extraScreen(canvas: Canvas) -> HouseLayout {
        let blank = make(projects: [], canvas: canvas)
        let dpr = canvas.dpr == 0 ? 1 : canvas.dpr
        let base = max(1, houseRound(canvas.height * dpr / 170) / 4)
        let w = ceil(canvas.width * dpr / base), h = ceil(canvas.height * dpr / base)
        let view = View(PXD: base, DPR: dpr, width: w, height: h, cssWidth: w * base / dpr, cssHeight: h * base / dpr, base: base, home: [0, 0], at: [0, 0])
        return HouseLayout(rooms: [], lift: nil, links: [], hulls: [], yard: blank.yard, escapes: [], escapeShapes: [:], drawOrder: [], view: view, worldFrame: blank.worldFrame)
    }

    static let projectThemes = ["bedroom", "server", "library", "greenhouse", "arcade"]
    // projectTheme / nameHash: FNV-1a over UTF-16 (including surrogate pairs).
    static func projectTheme(_ name: String, choices: [ThemeChoice]) -> String {
        if let choice = choices.first(where: { $0.project.utf16.elementsEqual(name.utf16) })?.theme,
           projectThemes.contains(choice) { return choice }
        var h: UInt32 = 0x811c9dc5
        for ch in name.utf16 { h = (h ^ UInt32(ch)) &* 0x01000193 }
        h ^= h >> 16; h = h &* 0x45d9f3b; h ^= h >> 16
        return projectThemes[Int(h) % projectThemes.count]
    }
}

// JS Math.round rounds negative ties toward +Infinity, unlike Swift.rounded().
func houseRound(_ value: Double) -> Double { floor(value + 0.5) }
