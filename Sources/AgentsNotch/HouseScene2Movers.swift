import AppKit
import NotchCore
import SpriteKit

/// What `HouseSprite` does not carry but the page's drawClawd reads: whose Clawd it is and what it is doing at its desk.
/// The host (agent behaviour is stage 2b) supplies it per sprite; the scene only picks the pose sprite.
struct HouseLook {
    var vendor = "claude"
    var activity = ""
}

/// The moving sprites: each HouseSim sprite is one SKSpriteNode showing a pose cut from the page's drawClawd (feet anchor
/// ax, ay), placed at iso() of its spot, in front of the pieces of its room that lie behind it.
extension HouseScene2 {
    func linkW(_ sp: HouseSprite) -> Double { (sp.seed - 0.5) * 0.36 }

    func iso(_ f: HouseLayout.Frame, _ x: Double, _ y: Double, _ z: Double) -> (Double, Double) {
        (f.ox + (x - y) * 16, f.oy + f.drop + (x + y) * 8 - z * 2)
    }

    private func idx(_ n: Int, _ period: Double, _ t: Double) -> Int { Int(floor(t.truncatingRemainder(dividingBy: period) / period * Double(n))) % n }

    /// The pose sprite name for a sprite at time t (ms), per parts.json poses.names and poses.timing.
    func poseName(_ sp: HouseSprite, look: HouseLook, face: Int, t: Double) -> String {
        let tick = { (ms: Double) in Int(floor(t / ms)) % 2 }
        let st = sp.state ?? ""
        switch sp.kind {
        case "cat":
            let f = face >= 0 ? "r" : "l"
            return sp.moving ? "cat/walk\(tick(120) + 1).\(f)" : "cat/sit2.\(f)"
        case "dog":
            let f = face >= 0 ? "r" : "l"
            return sp.moving ? "dog/walk\(tick(120) + 1).\(f)" : "dog/sit2.\(f)"
        case "home":
            if st == "idle-sleep" { return "home/sleep.\(idx(4, 1400, t))" }
            return sp.moving ? "home/walk.\(tick(110))" : "home/stand.0"
        default:
            let p = look.vendor + (sp.small ? "-mini" : "")
            if st == "fall" { return p + "/fall.0" }
            if st == "shower" { return p + "/shower.\(idx(6, 9000, t))" }
            if st == "dry" { return p + "/dry.\(idx(6, 1382, t))" }
            if sp.waving == true { return p + "/wave.\(tick(300))" }
            if sp.moving { return p + "/walk.\(tick(110))" }
            if st == "waiting" { return p + "/waiting.\(idx(6, 1634, t))" }
            if st == "error" { return p + "/error.\(idx(4, 1885, t))" }
            if st == "done" || st == "idle-sleep" { return p + "/sleep.\(idx(4, 1400, t))" }
            if sp.seated == true {
                let a = look.activity
                if a.hasPrefix("Bash") && a.contains("test") { return p + "/flask.\(idx(4, 3200, t))" }
                if a.hasPrefix("Edit") || a.hasPrefix("Write") { return p + "/hammer.\(tick(190))" }
                if a.hasPrefix("WebSearch") || a.hasPrefix("WebFetch") { return p + "/binoculars.\(tick(600))" }
                if a.hasPrefix("Read") || a.hasPrefix("Grep") { return p + "/book.\(tick(600))" }
                return p + "/work.\(tick(160))"
            }
            return p + "/stand.0"
        }
    }

    func roomFrame(_ key: String) -> HouseLayout.Room? {
        key == "__yard" ? layout.yard.room : layout.rooms.first { $0.key == key }
    }

    /// Where a sprite stands: its feet on the canvas and the z it is drawn at.
    func place(_ sp: HouseSprite, sim: HouseSim) -> (x: Double, y: Double, z: CGFloat)? {
        let S = 2.0, w = linkW(sp)
        if let ob = sp.onBridge {
            if ob.kind == "lift" {
                guard let ci = layout.lift?.cabins.firstIndex(where: { $0.id == ob.pair }), let lf = liftParts else { return nil }
                let sh = layout.lift!.cabins[ci].sh, cz = sim.cabins[ci].z
                let p = iso(wf, sh.cx + w * 1.4, sh.cy - w * 0.8, cz)
                let vi = min(light.variant, lf.variants.count - 1)
                let f = lf.variants[vi].floors.first { cz >= $0.zlo && cz < $0.zhi }?.level ?? 0
                return (p.0, p.1, riderZ[ci]?[f] ?? topZ)
            }
            guard let L = layout.links.first(where: { $0.id == ob.pair }), let info = linkInfo[L.id] else { return nil }
            if L.kind == "stair" {
                let c = cos(L.ang ?? 0), s = sin(L.ang ?? 0), d = ob.u * L.len, steps = Double(L.steps ?? 13)
                let k = min(steps, max(0, ceil(ob.u * steps - 0.2))), ww = w * 0.8
                let p = iso(wf, L.A[0] + c * d - s * ww, L.A[1] + s * d + c * ww, (L.z0 ?? 0) + k * (L.rise ?? 0) / steps)
                return (p.0, p.1, info.stepsZ + 4)
            }
            let x = L.A[0] + (L.B[0] - L.A[0]) * ob.u, y = L.A[1] + (L.B[1] - L.A[1]) * ob.u, z = (L.z ?? 0) - parts.SLAB
            let p = L.axis == "x" ? iso(wf, x, y + w, z) : iso(wf, x + w, y, z)
            return (p.0, p.1, info.backZ + 4)
        }
        guard let key = sp.room, let r = roomFrame(key) else { return nil }
        let p = iso(HouseLayout.Frame(ox: r.ox, oy: r.oy, drop: 0), sp.x, sp.y, sp.z)
        _ = S
        let atFoot = key == "__yard" && sp.x < 2.6
        let onStairs = layout.lift != nil ? (key == "__bath" && sp.y > r.NY - 0.05 && sp.x < 1.6) : false
        if atFoot || onStairs { return (p.0, p.1, topZ - 2 + CGFloat(sp.x + sp.y) * 0.01) }
        let listKey = key == "__yard" ? "__bath" : key
        guard let info = roomInfo[listKey] else { return nil }
        let depth = sp.x + sp.y + 0.55 + (sp.z > 9 ? 0.3 : 0)
        let slot = info.slots.first { $0.depth > depth || ($0.depth == depth && $0.fixture) }
        let base = (slot?.z ?? info.endZ + 4) - 4
        return (p.0, p.1, base + CGFloat(depth) * 0.15)
    }

    /// Puts every sprite of the simulation where it stands, in its pose; the cabins and stairs follow the simulation too.
    func sync(sim: HouseSim) {
        cabinState = sim.cabins.map { ($0.z, $0.state) }
        applyCabins()
        for l in sim.links where l.geometry.kind == "stair" {
            guard let info = linkInfo[l.geometry.id] else { continue }
            let up = l.lift >= 0.5
            for n in info.down { n.isHidden = up }
            for n in info.up { n.isHidden = !up }
        }
        let vi = min(light.variant, parts.poses.variants.count - 1)
        var seen = Set<String>()
        for sp in sim.sprites {
            seen.insert(sp.id)
            guard sp.alpha > 0.001, let at = place(sp, sim: sim) else { moverNodes[sp.id]?.isHidden = true; continue }
            let last = lastPos[sp.id], sx = (sp.x - sp.y)
            var face = 1
            if let last { let d = sx - (last.0 - last.1); face = abs(d) > 1e-6 ? (d > 0 ? 1 : -1) : faceMemory[sp.id] ?? 1 }
            faceMemory[sp.id] = face
            lastPos[sp.id] = (sp.x, sp.y)
            let name = poseName(sp, look: look(sp), face: face, t: clockMillis)
            guard let pose = parts.poses.variants[vi][name] ?? parts.poses.variants[vi][look(sp).vendor + "/stand.0"] else { continue }
            let r = pages.rect(pose.sprite)
            let n = moverNodes[sp.id] ?? {
                let m = SKSpriteNode(); m.anchorPoint = CGPoint(x: 0, y: 1); movers.addChild(m); moverNodes[sp.id] = m; return m
            }()
            if n.userData?["sprite"] as? Int != pose.sprite {
                n.texture = pages.texture(pose.sprite); n.size = CGSize(width: r.w, height: r.h)
                n.shader = shaders.shader(page: r.page, flag: r.flag)
                n.userData = ["sprite": pose.sprite]
            }
            n.isHidden = false
            n.alpha = CGFloat(sp.alpha)
            n.position = CGPoint(x: Double(HouseLight.round(at.x) - pose.ax), y: -Double(HouseLight.round(at.y) - pose.ay))
            n.zPosition = at.z
        }
        for (id, n) in moverNodes where !seen.contains(id) { n.removeFromParent(); moverNodes[id] = nil; lastPos[id] = nil; faceMemory[id] = nil }
    }

    /// True while anything moves: the view then runs at full rate; otherwise it may rest until the next minute.
    var isMoving: Bool {
        guard let sim else { return false }
        if sim.cabins.contains(where: { $0.state != "idle" }) || sim.links.contains(where: { $0.turn != nil }) { return true }
        return sim.sprites.contains { $0.moving || !$0.path.isEmpty || $0.onBridge != nil || $0.fall != nil || $0.alpha != $0.fade }
    }

    var isTyping: Bool { sim?.sprites.contains { $0.seated == true || $0.state == "working" } ?? false }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime.map { min(0.1, max(0, currentTime - $0)) } ?? 0
        lastTime = currentTime
        if !freezeClock { clockMillis += dt * 1000 }
        if driveSim, let sim { var left = dt * 1000; while left > 0 { let step = min(50, left); left -= step; sim.step(dt: step) } }
        if let sim { sync(sim: sim) }
        updateClouds()
        if mistAmount > 0.02 { refreshMist() }
        onFrame?(clockMillis)
    }
}
