import AppKit
import SpriteKit

/// The agents' house drawn by SpriteKit from atlases cut out of room/index.html (scripts/export-house-atlas.sh).
/// Phase 0 prototype: the tower as exported, two scripted agents on the routes the page planned, the lift, the sky.
/// Everything sits in canvas pixels of the page (y down) under `world`; depth is `zPosition`, as the page's list order.
/// The view runs at full rate while something walks or rides, slower while agents only type, and stops when still.
final class HouseScene: SKScene {
    enum Script { case demo, idle }

    private let atlas: HouseAtlas
    private let script: Script
    private let world = SKNode()
    private var tex: [String: SKTexture] = [:]
    private let sky = SKSpriteNode()
    private var skyKey = ""
    private var sun: SKSpriteNode?
    private var clouds: [(HouseAtlas.Cloud, SKSpriteNode)] = []
    private var cabins: [Cabin] = []
    private var agents: [Agent] = []
    private var t0: TimeInterval?
    private var lastTime: TimeInterval = 0
    private var stillSince: TimeInterval?
    private var napTimer: Timer?
    /// The highest rate this view may run at (60 on power, 30 on battery); `fixedFps` turns off the adaptive rate.
    var maxFps = 60 { didSet { view?.preferredFramesPerSecond = rate } }
    var fixedFps: Int?
    /// The hour the sky shows; nil follows the clock. The rooms keep the light they were exported in (phase 0).
    var fixedHour: Double?
    /// Holds the clouds where the page's reference frame has them, for a pixel comparison.
    var freezeClock = false
    /// Frames delivered over the last report window, for measurements (AGENT_NOTCH_HOUSE_FPS=1 logs them).
    private(set) var deliveredFps = 0.0
    private var counted = 0, countFrom: TimeInterval = 0
    private let logFps = ProcessInfo.processInfo.environment["AGENT_NOTCH_HOUSE_FPS"] != nil
    private var rate = 60

    init(atlas: HouseAtlas, script: Script = .demo) {
        self.atlas = atlas
        self.script = script
        super.init(size: CGSize(width: atlas.canvas.w, height: atlas.canvas.h))
        scaleMode = .resizeFill
        backgroundColor = .black
        addChild(world)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Loads house.json and its pages from a folder (the app's Resources/room/atlas, or the repo's room/atlas).
    static func load(from dir: URL, script: Script = .demo) -> HouseScene? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("house.json")),
              let atlas = try? JSONDecoder().decode(HouseAtlas.self, from: data) else { return nil }
        let scene = HouseScene(atlas: atlas, script: script)
        for (i, name) in atlas.pages.enumerated() {
            guard let img = NSImage(contentsOf: dir.appendingPathComponent(name))?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            scene.pages[i] = SKTexture(cgImage: img)
        }
        scene.attachTextures()
        return scene
    }

    private var pages: [Int: SKTexture] = [:]
    private var pending: [(SKSpriteNode, String)] = []

    // MARK: building

    private func sprite(_ name: String, x: Double, y: Double, z: Double) -> SKSpriteNode {
        let n = SKSpriteNode()
        n.anchorPoint = CGPoint(x: 0, y: 1)
        n.position = CGPoint(x: x, y: -y)
        n.zPosition = CGFloat(z)
        pending.append((n, name))
        world.addChild(n)
        return n
    }

    private func texture(_ name: String) -> SKTexture? {
        if let t = tex[name] { return t }
        guard let f = atlas.sprites[name], let page = pages[f.page] else { return nil }
        let w = Double(page.size().width), h = Double(page.size().height)
        let t = SKTexture(rect: CGRect(x: f.x / w, y: 1 - (f.y + f.h) / h, width: f.w / w, height: f.h / h), in: page)
        t.filteringMode = .nearest
        tex[name] = t
        return t
    }

    private func set(_ n: SKSpriteNode, _ name: String) {
        guard let t = texture(name) else { return }
        if n.texture !== t { n.texture = t; n.size = t.size() }
    }

    private func attachTextures() {
        pages.values.forEach { $0.filteringMode = .nearest }
        for (n, name) in pending { set(n, name) }
        pending = []
        agents.forEach { a in set(a.node, a.poses.stand[0].sprite) }
        updateSky(hour: atlas.hour, force: true)
    }

    private func build() {
        sky.anchorPoint = CGPoint(x: 0, y: 1)
        sky.zPosition = -1000
        world.addChild(sky)
        if let s = atlas.sky.sun { sun = sprite(s.sprite, x: 0, y: 0, z: -950) }
        clouds = atlas.sky.clouds.map { ($0, sprite($0.sprite, x: 0, y: 0, z: -800)) }
        for l in atlas.layers {
            let n = sprite(l.sprite, x: l.x, y: l.y, z: l.z)
            if l.blend == "add" { n.blendMode = .add }
        }
        if let lift = atlas.lift {
            cabins = lift.shafts.indices.map { i in
                let part = { (p: String) in lift.cages.first { $0.shaft == i && $0.part == p } }
                let back = part("back").map { sprite($0.sprite, x: $0.x, y: $0.y, z: 0) } ?? SKSpriteNode()
                let front = part("front").map { sprite($0.sprite, x: $0.x, y: $0.y, z: 0) } ?? SKSpriteNode()
                let ropes = lift.floors.map { _ in
                    let r = SKSpriteNode(color: Self.color(lift.rope), size: CGSize(width: 1, height: 1))
                    r.anchorPoint = CGPoint(x: 0, y: 1)
                    world.addChild(r)
                    return r
                }
                return Cabin(shaft: i, z: lift.cageZ, back: back, front: front, ropes: ropes,
                             backY: part("back")?.y ?? 0, frontY: part("front")?.y ?? 0,
                             frontClosed: part("front")?.sprite ?? "", frontOpen: part("frontOpen")?.sprite ?? "")
            }
        }
        if script == .demo {
            for r in atlas.routes {
                guard let poses = atlas.poses[r.vendor], let room = rooms[r.start.room] else { continue }
                let node = sprite(poses.stand[0].sprite, x: 0, y: 0, z: 0)
                let a = Agent(route: r, poses: poses, node: node, room: room, x: r.start.p[0], y: r.start.p[1], z: r.start.p.count > 2 ? r.start.p[2] : 0)
                a.nodes = r.legs.first?.nodes ?? []
                agents.append(a)
            }
        }
        cabins.forEach(placeCabin)
    }

    private lazy var rooms: [String: HouseAtlas.Room] = Dictionary(uniqueKeysWithValues: atlas.rooms.map { ($0.key, $0) })

    override func didChangeSize(_ oldSize: CGSize) {
        world.setScale(CGFloat(atlas.pxd / atlas.dpr)) // one canvas pixel is PXD device pixels, as the page's CSS
        world.position = CGPoint(x: 0, y: size.height)
        sky.size = CGSize(width: atlas.canvas.w, height: atlas.canvas.h)
    }

    // MARK: the sky

    /// The page's colour table (AMBK): the sky's two colours at this hour.
    private func updateSky(hour: Double, force: Bool = false) {
        let k = atlas.sky.ambk
        var i = 0
        while i + 1 < k.count, k[i + 1].hour <= hour { i += 1 }
        let a = k[i], b = k[min(i + 1, k.count - 1)], t = b.hour > a.hour ? (hour - a.hour) / (b.hour - a.hour) : 0
        let top = Self.mix(a.top, b.top, t), bottom = Self.mix(a.bottom, b.bottom, t)
        let key = "\(top)\(bottom)"
        if key != skyKey || force {
            skyKey = key
            sky.texture = Self.gradient(top, bottom, height: Int(atlas.canvas.h))
            sky.texture?.filteringMode = .nearest
            sky.size = CGSize(width: atlas.canvas.w, height: atlas.canvas.h)
        }
        if let s = atlas.sky.sun, let sun { // the page's sun arc (drawCelestial)
            let W = atlas.canvas.w, H = atlas.canvas.h, g = atlas.sky.ground, S = atlas.S, ks = (hour - 6) / 13.5
            sun.isHidden = !(ks > -0.08 && ks < 1.08)
            let x = (W * (0.08 + 0.84 * ks)).rounded(), y = (g + 5 * S - sin(.pi * ks) * (g - H * 0.1)).rounded()
            sun.position = CGPoint(x: x - s.ax, y: -(y - s.ay))
        }
    }

    private func placeClouds(_ t: Double) { // the page's drawClouds: each drifts at its own pace
        let W = atlas.canvas.w, H = atlas.canvas.h, S = atlas.S, g = atlas.sky.ground
        for (c, n) in clouds {
            let i = Double(c.i)
            let x = ((i * 131 * S + t * (0.004 + Double(c.i % 3) * 0.002) * S).truncatingRemainder(dividingBy: W + 80 * S) - 60 * S).rounded()
            let y = (8 * S + (i * 29 * S).truncatingRemainder(dividingBy: max(20, min(H * 0.3, g * 0.45)))).rounded()
            n.position = CGPoint(x: x + c.dx, y: -(y + c.dy))
        }
    }

    // MARK: the loop

    override func update(_ currentTime: TimeInterval) {
        if t0 == nil { t0 = currentTime; lastTime = currentTime; countFrom = currentTime }
        let dt = min(1.5, max(0, currentTime - lastTime)); lastTime = currentTime
        let t = freezeClock ? atlas.refT : (currentTime - t0!) * 1000 + atlas.refT // the page's clock, in ms
        var left = dt
        while left > 0 { let step = min(0.05, left); left -= step; stepAgents(step, now: currentTime - left); stepLift(step, now: currentTime - left) }
        placeClouds(t)
        agents.forEach { place($0, t: t) }
        cabins.forEach(placeCabin)
        if let h = fixedHour { updateSky(hour: h) } else {
            let d = Date(), c = Calendar.current
            updateSky(hour: Double(c.component(.hour, from: d)) + Double(c.component(.minute, from: d)) / 60)
        }
        pace(currentTime)
    }

    /// Full rate while something moves across the screen, 25 fps while agents only type (their arms change
    /// every 160 ms, the clouds a pixel at a time), paused after 3 s of nothing, woken each minute for the sky.
    private func pace(_ now: TimeInterval) {
        counted += 1
        if now - countFrom >= 5 {
            deliveredFps = Double(counted) / (now - countFrom)
            if logFps { NSLog("agents-notch: house fps %.1f (target %d)", deliveredFps, rate) }
            counted = 0; countFrom = now
        }
        let moving = cabins.contains { $0.state != .idle } || agents.contains { $0.moving || $0.riding != nil || $0.waitingLift }
        let typing = !agents.isEmpty
        let want = fixedFps ?? (moving ? maxFps : typing ? min(25, maxFps) : maxFps)
        if want != rate { rate = want; view?.preferredFramesPerSecond = want }
        if moving || typing || fixedFps != nil { stillSince = nil; return }
        if stillSince == nil { stillSince = now }
        if let s = stillSince, now - s >= 3 { sleepUntilNextMinute() }
    }

    private func sleepUntilNextMinute() {
        view?.isPaused = true
        napTimer?.invalidate()
        let ms = 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60) + 0.05
        napTimer = Timer.scheduledTimer(withTimeInterval: ms, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let view = self.view else { return }
                self.stillSince = self.lastTime - 3.1 // one frame for the new minute, then asleep again
                view.isPaused = false
            }
        }
    }

    /// Wakes a sleeping house (the host calls it when the window shows again).
    func wake() { napTimer?.invalidate(); stillSince = nil; view?.isPaused = false }
    /// Stops drawing until wake(), without the minute refresh (the host calls it when the window is covered).
    func hide() { napTimer?.invalidate(); view?.isPaused = true }

    // MARK: agents

    final class Agent {
        let route: HouseAtlas.Route, poses: HouseAtlas.Poses, node: SKSpriteNode
        var room: HouseAtlas.Room?
        var x: Double, y: Double, z: Double
        var nodes: [HouseAtlas.Node] = []
        var leg = 0
        var moving = false
        var dwellUntil: TimeInterval?
        var riding: Int?, cab: Int?, since: TimeInterval = 0
        var waitingLift: Bool { nodes.first?.lift != nil && riding == nil }
        init(route: HouseAtlas.Route, poses: HouseAtlas.Poses, node: SKSpriteNode, room: HouseAtlas.Room, x: Double, y: Double, z: Double) {
            self.route = route; self.poses = poses; self.node = node; self.room = room; self.x = x; self.y = y; self.z = z
        }
    }

    private func stepAgents(_ dt: Double, now: TimeInterval) {
        for a in agents {
            guard let n = a.nodes.first else { // at the spot: work a while, then the next leg
                a.moving = false
                if a.dwellUntil == nil { a.dwellUntil = now + (a.leg == 0 ? 6 : 9) }
                if let u = a.dwellUntil, now >= u {
                    a.dwellUntil = nil
                    a.leg += 1
                    if a.leg >= a.route.legs.count { a.leg = a.route.loopFrom }
                    a.nodes = a.route.legs[a.leg].nodes
                }
                continue
            }
            if n.lift != nil { a.moving = false; if a.since == 0 { a.since = now }; continue } // the cabins take it from here
            guard let p = n.p, let key = n.room else { a.nodes.removeFirst(); continue }
            if n.jump == true { a.room = rooms[key]; a.x = p[0]; a.y = p[1]; a.z = p[2]; a.nodes.removeFirst(); continue }
            let dz = (p[2] - a.z) / 14, dist = (pow(p[0] - a.x, 2) + pow(p[1] - a.y, 2) + dz * dz).squareRoot()
            let step = dt * atlas.walk.speed
            if dist <= step { a.x = p[0]; a.y = p[1]; a.z = p[2]; a.nodes.removeFirst(); a.moving = !a.nodes.isEmpty }
            else { let k = step / dist; a.x += (p[0] - a.x) * k; a.y += (p[1] - a.y) * k; a.z += (p[2] - a.z) * k; a.moving = true }
        }
    }

    private func place(_ a: Agent, t: Double) {
        let pose: HouseAtlas.Pose
        if a.moving { pose = a.poses.walk[Int(t / 110) % 2] }
        else if a.nodes.isEmpty, a.z > 3 { pose = a.poses.work[Int(t / 160) % 2] }
        else { pose = a.poses.stand[0] }
        set(a.node, pose.sprite)
        let X: Double, Y: Double, z: Double
        if let i = a.riding, let lift = atlas.lift { // in the cage: the page's transitPoint for a lift
            let c = cabins[i], sh = lift.shafts[i], w = (a.route.seed - 0.5) * 0.36
            (X, Y) = iso(lift.origin, sh.cx + w * 1.4, sh.cy - w * 0.8, c.z)
            z = cabinDepth(c) + 0.003
        } else if let r = a.room {
            (X, Y) = iso([r.ox, r.oy], a.x, a.y, a.z)
            z = r.zBase + 10 + a.x + a.y + 0.55 + (a.z > 9 ? 0.3 : 0)
        } else { a.node.isHidden = true; return }
        a.node.isHidden = false
        a.node.position = CGPoint(x: X.rounded() - pose.ax, y: -(Y.rounded() - pose.ay))
        a.node.zPosition = CGFloat(z)
    }

    private func iso(_ o: [Double], _ x: Double, _ y: Double, _ z: Double) -> (Double, Double) {
        let S = atlas.S
        return (o[0] + (x - y) * 8 * S, o[1] + (x + y) * 4 * S - z * S)
    }

    // MARK: the lift (the page's updateLifts, without the house-wide bookkeeping)

    final class Cabin {
        enum State { case idle, move, open }
        let shaft: Int, back: SKSpriteNode, front: SKSpriteNode, ropes: [SKSpriteNode]
        let backY: Double, frontY: Double, frontClosed: String, frontOpen: String
        var z: Double, level = 0, state = State.idle, t: TimeInterval = 0, stop = 0
        init(shaft: Int, z: Double, back: SKSpriteNode, front: SKSpriteNode, ropes: [SKSpriteNode], backY: Double, frontY: Double, frontClosed: String, frontOpen: String) {
            self.shaft = shaft; self.z = z; self.back = back; self.front = front; self.ropes = ropes
            self.backY = backY; self.frontY = frontY; self.frontClosed = frontClosed; self.frontOpen = frontOpen
        }
    }

    private func liftZ(_ k: Int) -> Double { atlas.lift.map { $0.floors[min(k, $0.floors.count - 1)].z } ?? 0 }

    private func stepLift(_ dt: Double, now: TimeInterval) {
        guard atlas.lift != nil else { return }
        let waiting = agents.filter { $0.waitingLift }
        for c in cabins {
            let inCab = agents.filter { $0.riding == c.shaft }
            switch c.state {
            case .move:
                let dz = liftZ(c.stop) - c.z, v = dt * 70
                if abs(dz) <= v { c.z = liftZ(c.stop); c.level = c.stop; c.state = .open; c.t = now } else { c.z += dz > 0 ? v : -v }
            case .open:
                for a in inCab where a.nodes.first?.lift?.to == c.level { a.riding = nil; a.cab = nil; a.since = 0; a.nodes.removeFirst() }
                if now - c.t > 0.5 {
                    for a in waiting where a.nodes.first?.lift?.from == c.level && (a.cab == nil || a.cab == c.shaft) {
                        if agents.filter({ $0.riding == c.shaft }).count >= 3 { break }
                        a.riding = c.shaft; a.cab = c.shaft; a.room = nil
                    }
                }
                if now - c.t > 1.7 {
                    let on = agents.filter { $0.riding == c.shaft }
                    if let to = on.compactMap({ $0.nodes.first?.lift?.to }).min(by: { abs(liftZ($0) - c.z) < abs(liftZ($1) - c.z) }) { c.stop = to; c.state = .move }
                    else { c.state = .idle }
                    for a in waiting where a.cab == c.shaft && a.riding == nil { a.cab = nil }
                }
            case .idle:
                let free = waiting.filter { $0.cab == nil }.sorted { $0.since < $1.since }
                guard let first = free.first, let want = first.nodes.first?.lift?.from else { continue }
                let d = { (o: Cabin) in abs(o.z - self.liftZ(want)) }
                if cabins.contains(where: { $0 !== c && $0.state == .idle && d($0) < d(c) }) { continue }
                for a in free where a.nodes.first?.lift?.from == want { a.cab = c.shaft }
                if d(c) < 0.5 { c.state = .open; c.t = now } else { c.stop = want; c.state = .move }
            }
        }
    }

    /// The slice of the lift a cage at z is drawn with: the page draws the lift a floor at a time, sorted into that floor.
    private func slice(_ z: Double) -> HouseAtlas.Floor? { atlas.lift?.floors.first { z >= $0.zlo && z < $0.zhi } }

    private func cabinDepth(_ c: Cabin) -> Double {
        guard let f = slice(c.z) else { return 0 }
        return f.zBase + 10 + f.depth + Double(c.shaft) * 0.01
    }

    private func placeCabin(_ c: Cabin) {
        guard let lift = atlas.lift else { return }
        let S = atlas.S, dy = ((c.z - lift.cageZ) * S).rounded(), base = cabinDepth(c)
        c.back.position.y = -(c.backY - dy)
        c.front.position.y = -(c.frontY - dy)
        c.back.zPosition = CGFloat(base + 0.002)
        c.front.zPosition = CGFloat(base + 0.004)
        set(c.front, c.state == .open ? c.frontOpen : c.frontClosed)
        // the rope, from the cage's top up to the head, a piece in every floor's slice
        let sh = lift.shafts[c.shaft], r0 = c.z + lift.cageH + 2, r1 = lift.top + 3
        for (f, rope) in zip(lift.floors, c.ropes) {
            let a = max(f.zlo, r0), b = min(f.zhi, r1)
            rope.isHidden = b <= a
            guard b > a else { continue }
            let (x, yTop) = iso(lift.origin, sh.cx, sh.cy, b), (_, yBot) = iso(lift.origin, sh.cx, sh.cy, a)
            rope.position = CGPoint(x: x.rounded(), y: -yTop.rounded())
            rope.size = CGSize(width: 1, height: yBot.rounded() - yTop.rounded() + 1)
            rope.zPosition = CGFloat(f.zBase + 10 + f.depth + Double(c.shaft) * 0.01 + 0.001)
        }
    }

    // MARK: colours

    static func rgb(_ hex: String) -> (Int, Int, Int) {
        if hex.hasPrefix("rgb(") {
            let v = hex.dropFirst(4).dropLast().split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return v.count == 3 ? (v[0], v[1], v[2]) : (0, 0, 0)
        }
        let n = Int(hex.dropFirst(), radix: 16) ?? 0
        return (n >> 16 & 255, n >> 8 & 255, n & 255)
    }

    static func color(_ s: String) -> NSColor {
        let c = rgb(s)
        return NSColor(srgbRed: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1)
    }

    /// The page's mixHex: each channel rounded.
    static func mix(_ a: String, _ b: String, _ t: Double) -> String {
        let A = rgb(a), B = rgb(b), m = { (x: Int, y: Int) in Int((Double(x) + Double(y - x) * t).rounded()) }
        return String(format: "#%02x%02x%02x", m(A.0, B.0), m(A.1, B.1), m(A.2, B.2))
    }

    /// A one pixel wide column from `top` to `bottom`, a row per canvas pixel, as the page's linear gradient.
    static func gradient(_ top: String, _ bottom: String, height: Int) -> SKTexture {
        let a = rgb(top), b = rgb(bottom), h = max(1, height)
        let ctx = CGContext(data: nil, width: 1, height: h, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<h { // CoreGraphics counts rows from the bottom
            let t = (Double(y) + 0.5) / Double(h), m = { (x: Int, z: Int) in CGFloat((Double(x) + Double(z - x) * t).rounded()) / 255 }
            ctx.setFillColor(red: m(a.0, b.0), green: m(a.1, b.1), blue: m(a.2, b.2), alpha: 1)
            ctx.fill(CGRect(x: 0, y: h - 1 - y, width: 1, height: 1))
        }
        return SKTexture(cgImage: ctx.makeImage()!)
    }
}

/// house.json, as scripts/house-atlas/export.js writes it.
struct HouseAtlas: Decodable {
    struct Size: Decodable { let w: Double, h: Double }
    struct Frame: Decodable { let page: Int, x: Double, y: Double, w: Double, h: Double }
    struct Layer: Decodable { let sprite: String, x: Double, y: Double, z: Double, blend: String? }
    struct Pose: Decodable { let sprite: String, ax: Double, ay: Double }
    struct Poses: Decodable { let stand: [Pose], walk: [Pose], work: [Pose] }
    struct Room: Decodable { let key: String, ox: Double, oy: Double, zBase: Double, floor: Int }
    struct Floor: Decodable { let level: Int, z: Double, zlo: Double, zhi: Double, depth: Double, zBase: Double }
    struct Cage: Decodable { let shaft: Int, part: String, sprite: String, x: Double, y: Double }
    struct Shaft: Decodable { let cx: Double, cy: Double }
    struct Lift: Decodable { let origin: [Double], cageZ: Double, cageH: Double, top: Double, rope: String, shafts: [Shaft], floors: [Floor], cages: [Cage] }
    struct LiftHop: Decodable { let from: Int, to: Int }
    struct Node: Decodable { let room: String?, p: [Double]?, jump: Bool?, lift: LiftHop? }
    struct Leg: Decodable { let to: String, nodes: [Node] }
    struct Start: Decodable { let room: String, p: [Double] }
    struct Route: Decodable { let id: String, vendor: String, seed: Double, start: Start, legs: [Leg], loopFrom: Int }
    struct Sun: Decodable { let sprite: String, ax: Double, ay: Double }
    struct Cloud: Decodable { let i: Int, w: Double, y: Double, sprite: String, dx: Double, dy: Double }
    /// One row of the page's AMBK: [hour, [r, g, b], sky top, sky bottom, dark].
    struct Light: Decodable {
        let hour: Double, top: String, bottom: String
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            hour = try c.decode(Double.self)
            _ = try c.decode([Double].self)
            top = try c.decode(String.self)
            bottom = try c.decode(String.self)
        }
    }
    struct Sky: Decodable { let ambk: [Light], ground: Double, sun: Sun?, clouds: [Cloud] }
    struct Walk: Decodable { let speed: Double, small: Double }

    let canvas: Size, pxd: Double, dpr: Double, S: Double, hour: Double, refT: Double
    let sky: Sky, rooms: [Room], lift: Lift?, poses: [String: Poses], routes: [Route]
    let layers: [Layer], sprites: [String: Frame], pages: [String], walk: Walk
}
