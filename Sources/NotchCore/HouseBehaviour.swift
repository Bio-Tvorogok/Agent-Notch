import Foundation

/// Wire format emitted by RoomWallpaper.rows. Unknown vendor values use Claude
/// on first spawn, just as the page does; later rows do not change its skin/home.
public struct HouseAgentRow: Codable, Sendable {
    public var id: String
    public var project: String?
    public var vendor: String
    public var state: String
    public var title, activity, parentId, model, ask: String?
    public var context: Double?
    public init(id: String, project: String? = nil, vendor: String = "claude", state: String = "working",
                title: String? = nil, activity: String? = nil, parentId: String? = nil,
                model: String? = nil, ask: String? = nil, context: Double? = nil) {
        self.id = id; self.project = project; self.vendor = vendor; self.state = state
        self.title = title; self.activity = activity; self.parentId = parentId
        self.model = model; self.ask = ask; self.context = context
    }
}

public final class HouseErrand {
    public let room, cat: String
    public var dur: Double?, until: Double, since: Double?, t0: Double?, lost = false
    public init(room: String, cat: String, dur: Double? = nil, until: Double = .infinity, since: Double? = nil) {
        self.room = room; self.cat = cat; self.dur = dur; self.until = until; self.since = since
    }
}

public final class HouseHandover {
    public let parent: String, t0: Double
    public var vanish: Bool, stage = "walk", t1: Double?
    public let errand: HouseErrand?
    init(parent: String, vanish: Bool, t0: Double, errand: HouseErrand?) {
        self.parent = parent; self.vanish = vanish; self.t0 = t0; self.errand = errand
    }
}

public final class HouseBehaviourSpriteState {
    public var agent: HouseAgentRow?, errand: HouseErrand?, handover: HouseHandover?
    public var vendor = "claude", restOnRoof = false, restInYard = false
    public var towel: Double?, handed = false, popped = false
}

/// Life-layer extension points, installed by enableLife (the seeded initializer
/// enables it automatically). The injected-RNG initializer keeps the isolated
/// stage 2b contract until explicitly enabled. Returning false lets agent behaviour
/// proceed. Subagent pop/handover is stage 2b and runs outside these gates.
/// sceneTrack gates celebration after >8s work, git commit/push mail and their
/// hold cancellation/resumption. sceneLeave gates releasing those scene holds.
/// dogGreet gates the dog's meet/along/wait trip accompanying wash/shower/dry.
/// residents gates quiet-room spawning/fading and random visits/stair sitting.
/// cat gates cat spawn, catThink/catGo/catNaps/catHome and keyboard/nap roaming.
/// dog gates dog spawn/removal, dogThink/dogGo, greet/fire/kennel roaming, ballAt,
/// pickThrower/startFetch/fetchStep/dropBall and throw/return holds.
/// dayScenes gates residentRoutine, plantSpots, yardVisit and arriveState.
/// scenes gates SC initialization/demo activities, error fire creation/clearing,
/// findFireHelper/extGoal, non-handover stepHold branches, drawSkyLife scheduling
/// (birds/planes/balloons) and their random numbers. Seasonal drawing is renderer
/// work. updateYard physics and subagent paper/puff expiry remain stage 2b.
public struct HouseBehaviourHooks {
    public var sceneTrack: (HouseSprite, HouseAgentRow, String?) -> Bool = { _, _, _ in false }
    public var sceneLeave: (HouseSprite) -> Bool = { _ in false }
    public var dogGreet: (HouseSprite) -> Bool = { _ in false }
    public var residents: (Double) -> Bool = { _ in false }
    public var cat: (Double) -> Bool = { _ in false }
    public var dog: (Double) -> Bool = { _ in false }
    public var dayScenes: (Double) -> Bool = { _ in false }
    public var scenes: (Double) -> Bool = { _ in false }
    public init() {}
}

/// Agent decisions and lifecycle over HouseSim. Time/dt use milliseconds;
/// rows may be JSONDecoder-decoded directly from RoomWallpaper.rows output.
/// Projects persist in first-seen order after their last agent leaves.
public final class HouseBehaviour {
    public struct Growth: Sendable {
        public var project: String, n: Int, ids: [String]
        public var level: Int { n >= 15 ? 3 : n >= 6 ? 2 : n >= 2 ? 1 : 0 }
        public init(project: String, n: Int = 0, ids: [String] = []) { self.project = project; self.n = n; self.ids = ids }
    }
    public struct Puff: Sendable {
        public let room: String, x, y, z, t0: Double, col: String, seed: Double
    }
    public struct Paper {
        let source, target: HouseSprite
        public let t0: Double
        public var from: String { source.id }
        public var to: String { target.id }
        init(from: HouseSprite, to: HouseSprite, t0: Double) { source = from; target = to; self.t0 = t0 }
    }
    public let life = HouseLifeState()
    public var stage3 = HouseLifeStage3Hooks()
    /// The page's birds, plane and balloon (HouseSkyLife.swift); runs only after enableSkyLife().
    public let skyLife = HouseSkyLife()
    public internal(set) var eggs: HouseEggs?
    public let sim: HouseSim
    public var hooks = HouseBehaviourHooks()
    public internal(set) var projects: [String] = []
    /// Host may persist this value (the page debounces localStorage by 2s).
    public var growth: [Growth] = []
    public internal(set) var puffs: [Puff] = [], papers: [Paper] = []
    public var sprites: [HouseSprite] { sim.sprites }
    public var time: Double { sim.time }
    public var layout: HouseLayout { sim.layout }
    let style: HouseLayout.Style, canvas: HouseLayout.Canvas, insets: HouseLayout.Insets
    let themes: [HouseLayout.ThemeChoice]
    var born: [(String, Double)] = [("__bath",0),("__kitchen",0),("__roof",0)]

    public convenience init(seed: UInt32 = 173, layout: HouseLayout.Style = .islands,
                            canvas: HouseLayout.Canvas = .init(width: 1440, height: 900),
                            insets: HouseLayout.Insets = .init(), themes: [HouseLayout.ThemeChoice] = []) {
        let rng = HouseRandom(seed: seed)
        self.init(layout: layout, canvas: canvas, insets: insets, themes: themes, random: { rng.nextDouble() })
        enableLife()
    }
    public init(layout: HouseLayout.Style = .islands, canvas: HouseLayout.Canvas = .init(width: 1440, height: 900),
                insets: HouseLayout.Insets = .init(), themes: [HouseLayout.ThemeChoice] = [], random: @escaping () -> Double) {
        style = layout; self.canvas = canvas; self.insets = insets; self.themes = themes
        sim = HouseSim(layout: .make(projects: [], layout: layout, canvas: canvas, insets: insets, themes: themes), random: random)
        // ensureRoom for the three shared rooms in page bootstrap relayouts the cages.
        for c in sim.cabins { c.state = "open" }
    }
    func find(_ id: String) -> HouseSprite? { sprites.first { HouseRoutes.same($0.id,id) } }
    func growthNote(_ a: HouseAgentRow) {
        let project = a.project.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        let i: Int
        if let found = growth.firstIndex(where: { HouseRoutes.same($0.project,project) }) { i = found }
        else { i = growth.count; growth.append(.init(project: project)) }
        if growth[i].ids.contains(where: { HouseRoutes.same($0,a.id) }) { return }
        growth[i].ids.append(a.id)
        if growth[i].ids.count > 150 { growth[i].ids.removeFirst() }
        growth[i].n += 1
    }
    @discardableResult
    func newAgent(_ a: HouseAgentRow, room: String) -> HouseSprite {
        let sp = sim.spawn(id: a.id, room: room, small: !(a.parentId ?? "").isEmpty)
        sp.behaviour.vendor = a.vendor == "codex" ? "codex" : "claude"
        return sp
    }
    public func setAgents(_ rows: [HouseAgentRow]) {
        var seen = Set<[UInt16]>()
        for a in rows {
            let project = a.project.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
            let room = ensureRoom(project)
            seen.insert(Array(a.id.utf16)); growthNote(a)
            var sp = find(a.id) ?? newAgent(a,room: room)
            let prev = sp.behaviour.agent?.state
            if let fall = sp.fall {
                // Map.delete + Map.set moves the old faller to the end.
                sim.removeSprite(sp); sp.id = a.id + "#fall" + Self.jsNumber(fall.t0); sim.sprites.append(sp)
                sp = newAgent(a,room: room)
            }
            if sp.exit { sp.exit = false; sp.goal = nil }
            let b = sp.behaviour
            b.agent = a; sp.context = a.context; sp.leaving = false; sp.fade = 1
            if b.errand == nil { sp.state = a.state }
            if a.state == "done", let prev, !prev.isEmpty, prev != "done" {
                b.restOnRoof = sim.random() < 0.5
                b.restInYard = !b.restOnRoof && sim.random() < 0.5
                if sim.random() < 0.5 {
                    let busy = sprites.contains { $0.goal?.room == "__bath" && $0.goal?.cat == "shower" }
                    b.errand = .init(room: "__bath", cat: busy ? "wash" : "shower", dur: busy ? 6000 : 20000, since: time)
                    _ = hooks.dogGreet(sp)
                }
            }
            if a.state != "done" { b.errand = nil }
            if life.enabled {
                if hooks.sceneTrack(sp,a,prev) { continue }
            } else if hooks.sceneTrack(sp,a,prev) || trackSubagent(sp,a,prev) { continue }
            let (target,cat) = b.errand.map { ($0.room,$0.cat) } ?? placeFor(sp)
            if sp.goal == nil || sp.goal!.cat != cat || !HouseRoutes.same(sp.goal!.room,target) {
                sim.setGoal(sp,pickSpot(sp,target,cat))
            }
        }
        for sp in sprites where sp.kind == "agent" && !seen.contains(Array(sp.id.utf16)) && !sp.leaving {
            sp.leaving = true; sp.behaviour.errand = nil
            if sp.alpha < 0.5 || sp.room == nil { sp.fade = 0; continue }
            if hooks.sceneLeave(sp) || (!life.enabled && leaveSubagent(sp)) { continue }
            sp.exit = true; sp.state = "idle"; sp.goal = nil
            guard let key = sp.room else { continue }
            let r = sim.room(key)
            sim.route(sp,to: r.key,point: [r.NX * 0.55,r.NY - 0.1,0])
        }
    }
    /// One fixed tick of `dt` ms (the golden fixtures step 50 ms): a single
    /// stepSprites + updateLifts of the whole `dt`. It is NOT the page's frame();
    /// a renderer driven by a display link calls `advance(frame:)`, which clamps the
    /// delta and runs the 50 ms substeps the page does.
    /// Optional rows arrive at this step's ending clock, before errands/movement,
    /// matching a page setAgents delivery immediately before its frame.
    public func step(dt: Double, agents: [HouseAgentRow]? = nil) {
        let dt = HouseSim.sane(dt)
        sim.time += dt
        beginStep(agents)
        sim.stepSprites(dt); sim.updateLifts(dt)
        finishStep()
    }
    /// The page's frame() (see HouseSim.advance(frame:)): `raw` is the frame
    /// clock's delta, motion is clamped to [0, 1500] ms in 50 ms substeps.
    public func advance(frame raw: Double, agents: [HouseAgentRow]? = nil) {
        let raw = raw.isFinite ? raw : 0, dt = min(1500, max(0, raw))
        sim.time += max(0, raw)
        beginStep(agents)
        var left = dt
        while left > 0 {
            let step = min(50, left); left -= step
            sim.stepSprites(step); sim.updateLifts(step, now: time - left)
        }
        finishStep()
    }
    /// Called with the step's ending clock right after its rows arrive and before the eggs, errands and motion run: the place where the page
    /// handles an input of that tick (a proof replays a trigger here). Nothing in the app sets it.
    public var afterRows: ((Double) -> Void)?
    private func beginStep(_ agents: [HouseAgentRow]?) {
        if let agents { setAgents(agents) }
        afterRows?(time)
        eggs?.sky(at: time)
        if life.enabled { stage3.lightingAndWeather(time); stage3.eggSky(time) }
        _ = hooks.residents(time)
        updateErrands()
    }
    private func finishStep() {
        if life.enabled { _ = hooks.scenes(time) }
        else {
            updateYard()
            for sp in sprites where sp.behaviour.handover != nil { stepHandover(sp) }
        }
        if !life.enabled {
            _ = hooks.cat(time); _ = hooks.dog(time); _ = hooks.dayScenes(time)
            _ = hooks.scenes(time)
        }
        if life.enabled { stage3.eggStep(time) }
        eggs?.step(at: time)
        sim.updateStairs()
        for (key,start) in born {
            let e = min(1,max(0,(time-start)/900))
            sim.roomDrops[key] = houseRound(-pow(1-e,3)*140)
        }
        if life.enabled { updateLifeFacing() }
        updateFallers()
        // drawSceneOverlays owns these lifetimes on the page, after fallers.
        if life.enabled { stage3.drawSeason(time) }
        puffs.removeAll { time-$0.t0 > 750 }
        papers.removeAll { time-$0.t0 > 900 || ($0.source.room == nil && $0.source.onBridge == nil) || ($0.target.room == nil && $0.target.onBridge == nil) }
        if life.enabled {
            life.fireworks.removeAll { time-$0.t0 > 3800 || !sim.hasRoom($0.room) }
            stage3.eggOver(time)
        }
        eggs?.over(at: time)
    }
    static func jsNumber(_ x: Double) -> String { x.rounded() == x ? String(format: "%.0f", x) : String(x) }
}

// V8 Math.hypot: scale before squaring and compensate summation error.
func houseBehaviourHypot(_ values: [Double]) -> Double {
    let scale = values.map(abs).max() ?? 0
    if scale == 0 || scale.isInfinite { return scale }
    var sum = 0.0, compensation = 0.0
    for value in values {
        let n = abs(value)/scale, summand = n*n-compensation, previous = sum
        sum += summand; compensation = (sum-previous)-summand
    }
    return sqrt(sum)*scale
}
