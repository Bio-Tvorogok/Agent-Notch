import AppKit
import NotchCore
import SpriteKit
import simd

/// The agents' house drawn by SpriteKit from room/atlas/parts.json for ANY project list: the static house is composed from
/// `HouseLayout` (rooms, links, lift, yard, draw order) and the cut parts, lit by the hour with one SKShader, and the moving
/// sprites come from `HouseSim`. Stage 1c of docs/house-spritekit-port.md.
///
/// Everything sits in canvas ("art") pixels of the page (y down) under `world`, which is scaled by `unit` points per art pixel.
/// Depth is an explicit `zPosition` (the view runs with ignoresSiblingOrder): every drawn piece takes the next z in the page's
/// own draw order, spaced so that moving sprites can sit between two pieces of a room.
final class HouseScene2: SKScene {
    struct Slot { var depth: Double; var z: CGFloat; var fixture: Bool }
    struct RoomInfo { var slots: [Slot] = []; var endZ: CGFloat = 0 }
    struct LinkInfo { var down: [SKNode] = [], up: [SKNode] = []; var backZ: CGFloat = 0, stepsZ: CGFloat = 0, frontZ: CGFloat = 0 }
    /// One piece of a lift cage in one floor's slice, shown while the cabin is inside that slice.
    struct CagePiece { let node: SKSpriteNode; let cabin: Int; let floor: Int; let part: String; let cage: HouseParts.LiftCage?; let zlo, zhi: Double; let rope: Bool }

    let parts: HouseParts, pages: HousePages, shaders: HouseShaders
    private(set) var layout: HouseLayout
    /// Points per art pixel. With the app's screen-sized view it follows the layout (a relayout changes the canvas' pixel density);
    /// a harness that sizes the scene to the canvas sets `followsLayoutScale` off.
    private(set) var unit: CGFloat
    var followsLayoutScale = true
    /// An extra screen (the page's `?scene=extra`): the sky and the city of an empty layout (`HouseLayout.extraScreen`), without the sun and the moon.
    var extraScreen = false
    struct LiveItem { weak var node: SKSpriteNode?; let make: (HousePainter) -> (CGImage, CGPoint, CGSize)?; let clock: Bool }
    var canvasW: Int { Int(layout.view.width) }
    var canvasH: Int { Int(layout.view.height) }
    let world = SKNode()
    var root = SKNode()
    var movers = SKNode()

    // time and light
    var light: HouseLightState
    var hour = 12.0
    var day = 0
    var clockHM = (12, 0)
    /// The clock face's colon: the page blinks it with the seconds; the proof freezes it blank (seconds = 0).
    var colon = true
    /// The scene's own time in ms (clouds, mist wisps, pane stars, poses).
    var clockMillis = 100_000.0
    /// Proofs only: the time the page draws its room animations at (the atlas cuts them at 100000).
    var roomClockOverride: Double?
    var growth: [String: Int] = [:]

    // built state
    var nextZ: CGFloat = 0
    var topZ: CGFloat = 0
    var roomInfo: [String: RoomInfo] = [:]
    var linkInfo: [String: LinkInfo] = [:]
    var glows: [(SKSpriteNode, HouseParts.Light)] = []
    var cagePieces: [CagePiece] = []
    var riderZ: [Int: [Int: CGFloat]] = [:] // cabin -> floor -> z between the cage's back and front
    var cabinState: [(z: Double, state: String)] = []
    var skyGroup = SKNode()
    var clouds: [(Int, SKSpriteNode)] = []
    var ants: [(SKSpriteNode, Double)] = []
    /// The page's window: its CSS height and the Dock's bottom inset set where the city's ground lies.
    var env: HouseSkyEnv?
    /// The CPU painting (signs, clock faces, panes, sky, city) runs on its own queue; its results are swapped in on the main thread.
    let painter: HousePainter
    let paintQueue = DispatchQueue(label: "agents-notch.house.paint", qos: .userInitiated)
    var texCache: [String: SKTexture] = [:]
    var liveItems: [LiveItem] = []
    var lastLive: [Int: (SKTexture, CGPoint, CGSize)] = [:]
    /// Called on the main thread when the atlas cannot be read any more (a page is missing or corrupt): the host falls back to the page.
    var onFailure: (() -> Void)?
    /// The textures did not preload in time (a busy GPU, not a broken atlas); nil means onFailure.
    var onStall: (() -> Void)?
    /// Main-thread cost of applying a finished paint, ms (for measurements).
    var onApply: ((Double) -> Void)?
    var mistBands: [SKSpriteNode] = [], mistWisps: [(SKSpriteNode, SKSpriteNode, Int)] = []
    var builtVariant = -1, builtKey = ""
    var wf: HouseLayout.Frame { layout.worldFrame }

    // moving sprites
    var sim: HouseSim?
    /// The real agents (HouseScene2Agents.swift): its simulation is `sim`, its layout the scene's.
    var behaviour: HouseBehaviour? {
        didSet {
            sim = behaviour?.sim
            look = { sp in HouseLook(vendor: sp.behaviour.vendor, activity: sp.behaviour.agent?.activity ?? "") }
        }
    }
    var pendingRows: [HouseAgentRow]?
    /// After a delivery has been applied: the host stores the growth.
    var onDelivered: (() -> Void)?
    var builtProjects = -1
    /// The harness steps the behaviour itself.
    var freezeSim = false
    /// The host's window is covered: nothing is drawn until `wake()`.
    var covered = false
    var canopyCache: [String: SKTexture] = [:]
    var canopyNodes: [String: SKSpriteNode] = [:]
    var driveSim = false
    var look: (HouseSprite) -> HouseLook = { _ in HouseLook() }
    var moverNodes: [String: SKSpriteNode] = [:]
    /// The layers (sprite * 2 + glow) each mover node shows now.
    var moverSig: [String: [Int]] = [:]
    /// The rope colour last set on the cage pieces (nil after a rebuild).
    var ropeColor: [Int]?
    /// The info (battery, eyelids) and the status marks drawn over each Clawd, and its hit box (feet-relative) for the chat bubbles.
    var infoRects: [String: HouseRects] = [:], markRects: [String: HouseRects] = [:]
    var hitBoxes: [String: [Int]] = [:]
    var fxRects: HouseRects?
    /// The page's seasonNow() and weather; the season overlay's still and drifting layers.
    var season = "autumn", weather = "clear", seasonSig = ""
    var seasonStill: HouseRects?, seasonDrift: HouseRects?
    let skyLifeLayer = HouseSkyLifeLayer()
    let eggDraw = HouseEggDraw()
    /// The mailbox letter's tip: text and canvas position (nil hides it).
    var onEggCard: ((String?, Double, Double) -> Void)?
    var yardRects: HouseRects?
    var flagPools: [String: HouseRects] = [:]
    static let screenDepths: [String: Double] = ["bedroom": 6.65, "server": 7.05, "library": 11.41, "greenhouse": 8.01, "arcade": 8.81]
    struct DynKey: Hashable { let room: String; let name: String }
    var dynNodes: [DynKey: (node: SKNode, z: CGFloat)] = [:]
    var lampNodes: [String: SKSpriteNode] = [:]
    var lastPos: [String: (Double, Double)] = [:]
    var faceMemory: [String: Int] = [:]
    /// Holds the scene's clock (clouds, wisps, stars) where the page's reference frame had it, for a pixel comparison.
    var freezeClock = false
    var lastTime: TimeInterval?
    /// The sky follows the wall clock (the app); off for the proof and for fixed-hour runs.
    var followClock = false
    var lastMinute = -1
    /// The wall clock the sky follows (a benchmark pins it to an hour).
    var wallClock: () -> Date = { Date() }
    /// The highest rate this view may run at (60 on power, 30 on battery); `fixedFps` turns off the adaptive rate.
    var maxFps = 60 { didSet { rate = fixedFps ?? min(rate, maxFps); view?.preferredFramesPerSecond = rate } }
    var fixedFps: Int?
    var yardSig: [String: String] = [:]
    /// Set by the host for direct manipulation (pointer, camera glide), which the page paints at the burst rate too.
    var burstExtra: () -> Bool = { false }
    var rate = 60
    var stillSince: TimeInterval?
    var napTimer: Timer?
    var counted = 0, countFrom: TimeInterval = 0
    var deliveredFps = 0.0
    /// Frames since the last report, for measurements.
    var onFrame: ((Double) -> Void)?

    // the pointer and the view (HouseScene2Camera.swift, HouseScene2Pointer.swift)
    /// The page's VIEW; nil keeps the overview and no pointer (the proof harness's scenes).
    var houseCamera: HouseCamera?
    var mistGroup = SKNode()
    var hudNode: SKNode?
    var hudSize = CGSize.zero
    var hudEnabled = true
    /// The cursor in the window's points (the page's `mouse`), nil when it is not over the bare desktop.
    var pointer: (x: Double, y: Double)?
    var hoveredId: String?
    var lastTip: HouseHit.Tip?
    /// The hover card changed (nil: hide it); the host shows it above the desktop icons.
    var onTip: ((HouseHit.Tip?) -> Void)?
    /// A click on an agent: its id.
    var onOpen: ((String) -> Void)?
    /// The clock of the camera in ms (the harness replaces it with a virtual one).
    var nowMs: () -> Double = { CACurrentMediaTime() * 1000 }
    var lastCameraNow: Double?
    var lastUpdateMs = 0.0
    /// The egg poses picked for a Clawd so far (the proof asks for them).
    var eggPoseSeen = Set<String>()
    var autoResetTimer: Timer?
    var signHits: [String: [Double]] = [:]

    init(parts: HouseParts, pages: HousePages, layout: HouseLayout, unit: CGFloat, size: CGSize) {
        self.parts = parts; self.pages = pages; self.layout = layout; self.unit = unit
        painter = HousePainter(parts: parts, layout: layout)
        shaders = HouseShaders(pages: pages, fa: parts.light.fA)
        light = HouseLight.state(parts, hour: 12)
        super.init(size: size)
        pages.onFailure = { [weak self] _ in self?.onFailure?() }
        scaleMode = .resizeFill
        backgroundColor = .black
        anchorPoint = .zero
        addChild(world)
        applyCamera()
        world.addChild(root)
        world.addChild(movers)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The atlas folder of a season next to the autumn one (room/atlas is autumn; the others are room/atlas-<season>).
    static func atlasDir(_ autumn: URL, season: String) -> URL {
        season == "autumn" ? autumn : autumn.deletingLastPathComponent().appendingPathComponent(autumn.lastPathComponent + "-" + season, isDirectory: true)
    }

    /// Loads parts.json and the pages from a folder (the app's Resources/room/atlas, or the repo's room/atlas).
    static func load(from dir: URL, layout: HouseLayout, unit: CGFloat, size: CGSize) -> HouseScene2? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("parts.json")) else { return nil }
        let parts: HouseParts
        do { parts = try JSONDecoder().decode(HouseParts.self, from: data) } catch { NSLog("parts.json: \(error)"); return nil }
        if let why = parts.problem() { NSLog("parts.json unusable: \(why)"); return nil }
        guard let pages = HousePages(parts: parts, dir: dir) else { NSLog("parts pages missing or not PNGs of the listed size in \(dir.path)"); return nil }
        return HouseScene2(parts: parts, pages: pages, layout: layout, unit: unit, size: size)
    }

    override func didChangeSize(_ oldSize: CGSize) { applyCamera(); layoutHud() }

    // MARK: public control

    /// A new project list: the layout changes, the house is built again.
    func setLayout(_ l: HouseLayout) {
        layout = l; builtKey = ""
        if followsLayoutScale { unit = CGFloat(l.view.PXD / l.view.DPR) }
        houseCamera = houseCamera?.rebased(layout: l)
        signHits = [:]
        rebuild()
    }

    /// New growth levels (room key -> level); the rooms that changed are built again.
    func setGrowth(_ g: [String: Int]) { guard g != growth else { return }; growth = g; rebuild() }

    /// The name of a room whose parts (theme, tower or island, growth level) parts.json does not have, nil when everything can be drawn.
    func missingParts(layout l: HouseLayout? = nil) -> String? {
        for r in (l ?? layout).rooms where parts.rooms[partsKey(r)] == nil { return partsKey(r) }
        return nil
    }

    /// The hour (and the day, for the morning mist). A new variant (DARK crossed a threshold) rebuilds the tree; otherwise
    /// only uniforms, glow alphas and the live parts change.
    func setTime(hour: Double, day: Int) {
        self.hour = hour; self.day = day
        defer { feedLife(hour: hour, dark: light.dark, exact: false) }
        let h = floor(hour), m = floor((hour.truncatingRemainder(dividingBy: 1)) * 60)
        clockHM = (Int(h), Int(m))
        light = HouseLight.state(parts, hour: hour)
        shaders.set(light.amb)
        if builtVariant != light.variant || builtKey != layoutKey { rebuild() } else { refreshLight() }
    }

    var layoutKey: String { layout.rooms.map(\.key).joined(separator: ",") + "|" + growth.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",") }

    // MARK: building

    func next() -> CGFloat { nextZ += 8; return nextZ }

    @discardableResult
    func sprite(_ id: Int, x: Double, y: Double, z: CGFloat, parent: SKNode? = nil, blend: String? = nil) -> SKSpriteNode {
        let r = pages.rect(id)
        let n = SKSpriteNode(texture: pages.texture(id), size: CGSize(width: r.w, height: r.h))
        n.anchorPoint = CGPoint(x: 0, y: 1)
        n.position = CGPoint(x: x, y: -y)
        n.zPosition = z
        shaders.apply(to: n, id: id)
        if blend == "add" { n.blendMode = .add }
        (parent ?? root).addChild(n)
        return n
    }

    /// An image painted on the CPU by the painter; it is empty until the first paint arrives (or shows the last one of the same slot).
    func live(z: CGFloat, clock: Bool = false, make: @escaping (HousePainter) -> (CGImage, CGPoint, CGSize)?) {
        let n = SKSpriteNode()
        n.anchorPoint = CGPoint(x: 0, y: 1)
        n.zPosition = z
        n.isHidden = true
        root.addChild(n)
        if let (t, p, sz) = lastLive[liveItems.count] { n.texture = t; n.size = sz; n.position = CGPoint(x: p.x, y: -p.y); n.isHidden = false }
        liveItems.append(LiveItem(node: n, make: make, clock: clock))
    }

    func partsKey(_ r: HouseLayout.Room) -> String {
        if r.key == "__bath" { return "bath/g\(layout.links.filter { $0.a == "__yard" }.count)" }
        if r.key == "__kitchen" { return "kitchen" }
        if r.key == "__roof" { return "roof" }
        return "\(r.theme)/\(r.tower == 0 ? "tower" : "island")/g\(growth[r.key] ?? 0)"
    }

    static let sharedNames = ["__bath": "Ванная", "__kitchen": "Кухня", "__roof": "Крыша"]

    func rebuild() {
        root.removeFromParent(); movers.removeAllChildren(); moverNodes = [:]; moverSig = [:]; ropeColor = nil; fxRects = nil; seasonStill = nil; seasonDrift = nil; seasonSig = ""; yardRects = nil; flagPools = [:]; yardSig = [:]; dynNodes = [:]; lampNodes = [:]; canopyNodes = [:]
        root = SKNode(); world.insertChild(root, at: 0)
        nextZ = 0; roomInfo = [:]; linkInfo = [:]; glows = []; liveItems = []; cagePieces = []; riderZ = [:]; clouds = []; mistBands = []; mistWisps = []
        cabinState = (layout.lift?.cabins ?? []).map { ($0.z, "idle") }
        let vi = light.variant
        buildId += 1
        if builtKey != layoutKey { lastLive.removeAll() } // other rooms: the old signs, clocks and panes belong to other slots
        builtVariant = vi; builtKey = layoutKey
        let oldSky = skyGroup
        skyGroup = SKNode(); root.addChild(skyGroup)
        mistGroup = SKNode(); root.addChild(mistGroup)
        for c in oldSky.children { c.removeFromParent(); skyGroup.addChild(c) } // until the new paint arrives
        buildSkyNodes()
        let rooms = Dictionary(layout.rooms.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let links = Dictionary(layout.links.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for item in layout.drawOrder {
            if let r = rooms[item.key] { buildRoom(r, vi: vi) } else if let l = links[item.key] { buildLink(l, vi: vi) }
        }
        nextZ += 16
        for r in layout.rooms {
            guard let pr = parts.rooms[partsKey(r)], vi < pr.variants.count else { continue }
            for o in pr.variants[vi].overlay { sprite(o.sprite, x: r.ox + o.x, y: r.oy + o.y, z: next()) }
        }
        topZ = next() + 8
        buildMist()
        applyCabins()
        refreshLight()
        if let sim { sync(sim: sim) }
        applyCamera()
    }
    var painted = false
    var buildId = 0

    private func addLights(_ list: [HouseParts.Light], ox: Double, oy: Double) {
        for l in list {
            let n = sprite(l.sprite, x: Double(HouseLight.round(ox + l.x) - l.r), y: Double(HouseLight.round(oy + l.y) - l.r), z: next(), blend: "add")
            n.blendMode = .add
            n.alpha = 0
            glows.append((n, l))
        }
    }

    func buildRoom(_ r: HouseLayout.Room, vi: Int) {
        guard let pr = parts.rooms[partsKey(r)], vi < pr.variants.count else { return }
        let v = pr.variants[vi]
        var info = RoomInfo(), litDone = false
        for l in v.layers {
            if l.kind == "sign" && l.variant == "plaque" && !litDone {
                info.endZ = nextZ + 4
                addLights(v.lights, ox: r.ox, oy: r.oy); litDone = true
            }
            let first = nextZ + 8
            switch l.kind {
            case "lift": buildLiftSlice(room: r.key, vi: vi, depth: l.depth, info: &info)
            case "sign":
                let name = r.theme == "bath" || r.theme == "kitchen" || r.theme == "roof" ? (Self.sharedNames[r.key] ?? r.name) : r.name
                live(z: next()) { p in p.signImage(room: r, name: name, vi: p.light.variant) }
            case "pane":
                live(z: next()) { p in p.paneImage(room: r, layer: l) }
            default:
                if l.tag == "clock", let c = pr.clock {
                    live(z: next(), clock: true) { p in p.clockImage(room: r, clock: c, vi: p.light.variant) }
                } else if let id = l.sprite {
                    let z = next()
                    let n = sprite(id, x: r.ox + (l.x ?? 0), y: r.oy + (l.y ?? 0), z: z, blend: l.blend)
                    if l.dyn == true, let d = l.depth {
                        var name = r.key == "__bath" && d == 17.6 ? "swing" : r.key == "__bath" && d == 12.21 ? "flag" : r.key == "__kitchen" && d == 12.41 ? "flagK" : nil
                        if Self.screenDepths[r.theme].map({ abs($0 - d) < 0.001 }) == true { name = "screen" }
                        if let name { dynNodes[DynKey(room: r.key, name: name)] = (n, z + 0.5) }
                    }
                }
            }
            if let d = l.depth { info.slots.append(Slot(depth: d, z: first, fixture: l.kind == "sign" || l.kind == "lift")) }
            if l.kind == "sign" && l.variant == "plaque" { /* the plaque follows the lights */ }
        }
        if !litDone { info.endZ = nextZ + 4; addLights(v.lights, ox: r.ox, oy: r.oy) }
        roomInfo[r.key] = info
    }

    func buildLink(_ l: HouseLayout.Link, vi: Int) {
        guard let pl = parts.village.links.first(where: { $0.kind == l.kind && Self.same($0.A, l.A) && Self.same($0.B, l.B) }), vi < pl.variants.count else { return }
        let v = pl.variants[vi]
        var info = LinkInfo()
        func add(_ p: HouseParts.Part) -> (nodes: [SKNode], back: CGFloat, steps: CGFloat, front: CGFloat) {
            var out: [SKNode] = [], back: CGFloat = 0, steps: CGFloat = 0, front: CGFloat = 0
            for ly in p.layers {
                guard let id = ly.sprite else { continue }
                let z = next()
                if ly.tag == "back" { back = z } else if ly.tag == "steps" { steps = z } else if ly.tag == "front" { front = z }
                out.append(sprite(id, x: wf.ox + (ly.x ?? 0), y: wf.oy + (ly.y ?? 0), z: z, blend: ly.blend))
            }
            let saved = glows.count
            addLights(p.lights, ox: wf.ox, oy: wf.oy)
            for i in saved..<glows.count { out.append(glows[i].0) }
            return (out, back, steps, front)
        }
        if l.kind == "stair", let down = v.down, let up = v.up {
            let start = nextZ
            let d = add(down)
            let end = nextZ
            nextZ = start
            let u = add(up) // both flights share one z span
            nextZ = max(end, nextZ)
            info.down = d.nodes; info.up = u.nodes
            info.backZ = d.back; info.stepsZ = d.steps; info.frontZ = d.front
            let lifted = (sim?.links.first(where: { $0.geometry.id == l.id })?.lift ?? 0) >= 0.5
            for n in lifted ? info.down : info.up { n.isHidden = true }
        } else if let ls = v.layers {
            let d = add(HouseParts.Part(layers: ls, lights: v.lights ?? []))
            info.down = d.nodes; info.backZ = d.back; info.frontZ = d.front
        }
        linkInfo[l.id] = info
    }

    static func same(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 } }

    // MARK: lift

    var liftParts: HouseParts.Lift? { layout.lift.flatMap { parts.village.lift["n\($0.fl.count)"] } }

    func buildLiftSlice(room key: String,  vi: Int, depth: Double?, info: inout RoomInfo) {
        guard let lf = liftParts, vi < lf.variants.count, !lf.variants[vi].floors.isEmpty else { return }
        // the room's slice is found by its key in the lift's floor list (room:'self'), never by the cut-time floor
        // (the atlas was cut with one project's name in the tower; the floor index is the same for any project)
        guard let f = layout.lift?.fl.firstIndex(where: { $0.room == key }) ?? lf.fl.firstIndex(where: { $0.room == key }), f < lf.variants[vi].floors.count else { return }
        let v = lf.variants[vi], fl = v.floors[f]
        var items: [(Double, (CGFloat) -> Void)] = []
        for p in fl.pieces { items.append((p.key, { [unowned self] z in self.sprite(p.sprite, x: self.wf.ox + p.x, y: self.wf.oy + p.y, z: z) })) }
        for i in 0..<(layout.lift?.cabins.count ?? 0) {
            items.append((Double(i) * 0.01 + 0.001, { [unowned self] z in
                let n = SKSpriteNode(color: .black, size: CGSize(width: 1, height: 1)); self.shaders.ink(n)
                n.anchorPoint = CGPoint(x: 0, y: 1); n.zPosition = z; self.root.addChild(n)
                self.cagePieces.append(CagePiece(node: n, cabin: i, floor: f, part: "rope", cage: nil, zlo: fl.zlo, zhi: fl.zhi, rope: true))
            }))
            for cg in v.cages where cg.shaft == i {
                items.append((cg.key, { [unowned self] z in
                    let n = self.sprite(cg.sprite, x: self.wf.ox + cg.x, y: self.wf.oy + cg.y, z: z)
                    self.cagePieces.append(CagePiece(node: n, cabin: i, floor: f, part: cg.part, cage: cg, zlo: fl.zlo, zhi: fl.zhi, rope: false))
                    if cg.part == "back" { self.riderZ[i, default: [:]][f] = z + 4 }
                }))
            }
        }
        for it in items.sorted(by: { $0.0 < $1.0 }) { it.1(next()) }
    }

    /// A pool of plain rects drawn like the parts (see HouseShaders.ink).
    func rectPool() -> HouseRects {
        let r = HouseRects(); r.ink = { [unowned self] in self.shaders.ink($0) }; return r
    }

    /// Cabins at their z: each cage piece shows in the slice that holds the cabin, open or closed.
    func applyCabins() {
        guard let lf = liftParts else { return }
        let S = 2.0
        let v = lf.variants[min(light.variant, lf.variants.count - 1)]
        for p in cagePieces {
            guard p.cabin < cabinState.count else { continue }
            let c = cabinState[p.cabin], z = c.z
            if p.rope {
                let sh = lf.shafts[p.cabin], r0 = max(p.zlo, z + lf.cageH + 2), r1 = min(p.zhi, lf.top + 3)
                if r1 > r0 {
                    let ya = wf.oy + (sh.cx + sh.cy) * 4 * S - r1 * S, yb = wf.oy + (sh.cx + sh.cy) * 4 * S - r0 * S
                    let x = wf.ox + (sh.cx - sh.cy) * 8 * S
                    let ra = HouseLight.round(ya), rb = HouseLight.round(yb)
                    p.node.isHidden = false
                    p.node.position = CGPoint(x: HouseLight.round(x), y: -min(ra, rb))
                    p.node.size = CGSize(width: 1, height: abs(rb - ra) + 1)
                } else { p.node.isHidden = true }
                continue
            }
            guard let cg = p.cage else { continue }
            let inSlice = z >= p.zlo && z < p.zhi
            let want = c.state == "open" ? cg.part != "front" : cg.part != "frontOpen"
            p.node.isHidden = !(inSlice && want)
            if inSlice { p.node.position = CGPoint(x: wf.ox + cg.x, y: -(wf.oy + cg.y - Double(HouseLight.round((z - lf.cageZ) * S)))) }
        }
        _ = v
        refreshRopes()
    }

    func refreshRopes() {
        guard let lf = liftParts else { return }
        let v = lf.variants[min(light.variant, lf.variants.count - 1)], c = HouseLight.mix(v.rope, light.amb, fa: parts.light.fA)
        guard c != ropeColor else { return } // applyCabins runs every frame; the colour changes with the light
        ropeColor = c
        let col = NSColor(srgbRed: CGFloat(c[0]) / 255, green: CGFloat(c[1]) / 255, blue: CGFloat(c[2]) / 255, alpha: 1)
        for p in cagePieces where p.rope { p.node.color = col }
    }

    // MARK: per-minute refresh

    func refreshLight() {
        shaders.set(light.amb)
        for (n, l) in glows { n.alpha = CGFloat(max(0, min(1, l.a + l.b * light.dark))) }
        refreshRopes()
        repaint(sync: !painted)
        refreshMist()
    }
}
