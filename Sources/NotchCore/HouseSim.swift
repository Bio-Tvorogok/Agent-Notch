import Foundation

/// scene.mjs's LCG. Inject nextDouble into a world to share or observe its stream.
public final class HouseRandom {
    public private(set) var state: UInt32
    public init(seed: UInt32 = 173) { state = seed }
    public func nextDouble() -> Double {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Double(state) / 4_294_967_296
    }
}

public struct HouseGoal: Codable, Sendable {
    public var room: String
    public var p: [Double]
    public var cat: String
    public var i: Int
    public init(room: String, p: [Double], cat: String = "idle", i: Int = -1) {
        self.room = room; self.p = p; self.cat = cat; self.i = i
    }
}

public struct HouseLiftTrip: Codable, Sendable {
    public var from, to: Int
    public init(from: Int, to: Int) { self.from = from; self.to = to }
}

/// The JS tagged node shape. Room/link/cabin references use their stable keys.
/// Nodes have reference identity: rerouting retains a node's wait/call timestamps.
public final class HouseRouteNode: Codable {
    public var r: String?, p: [Double]?, bridge: String?, to: Double?, from: Double?
    public var call: String?, aim: Int?, side: String?, lift: HouseLiftTrip?
    public var jump: Bool?, poof: Bool?, wait: Double?, until: Double?, since: Double?, cab: String?
    public init(r: String? = nil, p: [Double]? = nil, bridge: String? = nil, to: Double? = nil,
                from: Double? = nil, call: String? = nil, aim: Int? = nil, side: String? = nil,
                lift: HouseLiftTrip? = nil, jump: Bool? = nil, poof: Bool? = nil, wait: Double? = nil) {
        self.r = r; self.p = p; self.bridge = bridge; self.to = to; self.from = from
        self.call = call; self.aim = aim; self.side = side; self.lift = lift
        self.jump = jump; self.poof = poof; self.wait = wait
    }
}

public final class HouseSprite {
    public struct Transit {
        public var kind, pair: String
        public var u: Double
        public var forward: Bool?
        public init(kind: String, pair: String, u: Double, forward: Bool? = nil) {
            self.kind = kind; self.pair = pair; self.u = u; self.forward = forward
        }
    }
    public struct Fall {
        public var x, y, t0, seed: Double
    }
    public internal(set) var id: String
    public let behaviour = HouseBehaviourSpriteState()
    public let life = HouseLifeSpriteState()
    public let eggs = HouseEggSpriteState()
    public var room: String?, homeRoom: String
    public var x, y, z: Double
    public var path: [HouseRouteNode] = []
    public var alpha = 0.0, fade = 1.0, seed: Double
    public var kind = "agent", small = false
    public var moving = false, seated: Bool?, waving: Bool?, state: String?
    public var goal: HouseGoal?, onBridge: Transit?, fall: Fall?
    public var speed: Double?, context: Double?
    public var leaving = false, exit = false
    /// Inputs from the later egg layer, equivalent to hi5.until and UFO hold.
    public var frozenUntil: Double?, frozen = false

    public init(id: String, room: String, point: [Double], seed: Double? = nil) {
        self.id = id; self.room = room; homeRoom = room
        x = point[0]; y = point[1]; z = point[2]
        self.seed = seed ?? Double(HouseRoutes.hashStr(id) % 1000) / 1000
    }
}

public final class HouseLinkState {
    public struct Turn {
        public var a0, a1: Double
        public var to: Int
        public var t0, ms: Double
    }
    public let geometry: HouseLayout.Link
    public var lift = 0.0, aim = 0, turn: Turn?, next = 0.0, since: Double?
    init(_ geometry: HouseLayout.Link) { self.geometry = geometry }
}

public final class HouseCabinState {
    public let geometry: HouseLayout.Cabin
    public var z: Double, level: Int, state = "idle", t = 0.0, stop: Int?
    init(_ geometry: HouseLayout.Cabin) { self.geometry = geometry; z = geometry.z; level = geometry.level }
}

/// Pure simulation. dt and time are milliseconds, positions are JS tiles/height
/// units. A step runs sprites, lifts, then stairs, using the step's ending time.
/// Goal selection belongs to the caller; this world never chooses a destination.
public final class HouseSim {
    public internal(set) var layout: HouseLayout
    public internal(set) var links: [HouseLinkState], cabins: [HouseCabinState]
    public internal(set) var sprites: [HouseSprite] = []
    public internal(set) var time = 0.0
    var roomDrops: [String: Double] = [:]
    /// True while a room is still dropping into place (a renderer keeps its frame rate up).
    public var roomsSettling: Bool { roomDrops.values.contains { $0 != 0 } }
    let random: () -> Double
    public convenience init(layout: HouseLayout, seed: UInt32 = 173) {
        let rng = HouseRandom(seed: seed)
        self.init(layout: layout, random: { rng.nextDouble() })
    }
    public init(layout: HouseLayout, random: @escaping () -> Double) {
        // An injected generator outside [0, 1) would trap the Int conversions downstream.
        self.layout = layout; self.random = { let v = random(); return v.isFinite ? min(max(v, 0), 0.9999999999999999) : 0 }
        links = layout.links.map(HouseLinkState.init)
        cabins = (layout.lift?.cabins ?? []).map(HouseCabinState.init)
    }

    /// A room by key. Never traps: an unknown key (stale goal, hand-built input)
    /// degrades to the bathroom, then to whatever room exists, then to the yard.
    public func room(_ key: String) -> HouseLayout.Room {
        if HouseRoutes.same(key, "__yard") {
            var r = layout.yard.room; r.drop = roomDrops["__bath"] ?? r.drop; return r
        }
        guard let room = layout.rooms.first(where: { HouseRoutes.same($0.key, key) })
                ?? layout.rooms.first(where: { HouseRoutes.same($0.key, "__bath") }) ?? layout.rooms.first else {
            var r = layout.yard.room; r.drop = roomDrops["__bath"] ?? r.drop; return r
        }
        var result = room; result.drop = roomDrops[room.key] ?? room.drop; return result
    }
    func hasRoom(_ key: String) -> Bool {
        HouseRoutes.same(key, "__yard") || layout.rooms.contains { HouseRoutes.same($0.key, key) }
    }
    public func hub(_ key: String) -> [Double] { HouseRoutes.theme(room(key).theme).hub }
    public func spots(_ key: String) -> [String: [[Double]]] { HouseRoutes.theme(room(key).theme).spots }
    func roomAt(_ tower: Int, _ floor: Int) -> HouseLayout.Room? {
        layout.rooms.first { $0.tower == tower && $0.floor == floor }
    }
    func isIsland(_ r: HouseLayout.Room) -> Bool { r.floor == 0 && r.tower > 0 && layout.yard.on }
    /// nil for a stale id: the page keeps the dead link object alive, a value
    /// world has nothing to point at, so callers skip or reroute.
    func link(_ id: String) -> HouseLinkState? { links.first { HouseRoutes.same($0.geometry.id, id) } }

    @discardableResult
    public func spawn(id: String, room key: String, kind: String = "agent", small: Bool = false) -> HouseSprite {
        let r = room(key), sp = HouseSprite(id: id, room: key, point: [hub(key)[0], hub(key)[1], 0])
        sp.kind = kind; sp.small = small
        if r.floor > 0 && kind != "home", let below = roomAt(r.tower, r.floor - 1) {
            sp.room = below.key; sp.x = hub(below.key)[0]; sp.y = hub(below.key)[1]
        }
        if let index = sprites.firstIndex(where: { HouseRoutes.same($0.id, id) }) { sprites[index] = sp }
        else { sprites.append(sp) }
        return sp
    }
    func removeSprite(_ sprite: HouseSprite) { sprites.removeAll { $0 === sprite } }
    public func setGoal(_ sprite: HouseSprite, _ goal: HouseGoal) {
        sprite.goal = goal; route(sprite, to: goal.room, point: goal.p)
    }
    /// dt in milliseconds. Non-finite or negative input counts as zero.
    static func sane(_ dt: Double) -> Double { dt.isFinite ? max(0, dt) : 0 }
    /// One fixed step at the end of dt: the contract of the golden fixtures.
    public func step(dt: Double) {
        let dt = Self.sane(dt)
        time += dt
        stepSprites(dt); updateLifts(dt); updateStairs()
    }
    /// The page's frame(): `raw` is the frame clock's delta (rAF stamp minus the
    /// last one). The clock follows it (never backwards), the motion it drives is
    /// clamped to [0, 1500] ms and cut into 50 ms substeps of sprites then lifts
    /// (lifts see the substep's own end), stairs run once per frame. Late paints
    /// after a stall catch up at most 1.5 s of motion.
    public func advance(frame raw: Double) {
        let raw = raw.isFinite ? raw : 0, dt = min(1500, max(0, raw))
        time += max(0, raw)
        var left = dt
        while left > 0 {
            let step = min(50, left); left -= step
            stepSprites(step); updateLifts(step, now: time - left)
        }
        updateStairs()
    }
}
