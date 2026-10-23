import AppKit
import NotchCore
import SpriteKit

/// The page's scene-level overlays (drawChats, drawSceneOverlays, the ball of drawYard): chat bubbles, foam, papers, puffs,
/// fireworks, the night lamp glow and the fetch ball. Solid rects in the canvas, drawn above the whole house like the page does.
extension HouseScene2 {
    private var S: Int { 2 }

    func fxLayer() -> HouseRects {
        if let f = fxRects, f.parent === movers { return f }
        let f = HouseRects(); movers.addChild(f); fxRects = f
        return f
    }

    /// scPos: the feet of a sprite on the canvas, on a bridge too.
    func feet(_ sp: HouseSprite, sim: HouseSim) -> (Double, Double)? {
        guard let p = place(sp, sim: sim) else { return nil }
        return (p.x, p.y)
    }

    func updateEffects(sim: HouseSim, simT: Double, t: Double) {
        let fx = fxLayer()
        if let b = behaviour { updateYardDyn(b, sim: sim, simT: simT) }
        fx.zPosition = topZ + 4
        fx.begin()
        defer { fx.end() }
        guard let b = behaviour else { lampOff(); return }
        let out = litC("#2a1f2e")
        let byId = Dictionary(sim.sprites.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // drawChats
        var groups: [String: [HouseSprite]] = [:]
        for sp in sim.sprites where sp.alpha > 0.5 && hitBoxes[sp.id] != nil {
            let n = sp.path.first
            var k: String?
            if let l = n?.lift, sp.onBridge == nil, !sp.moving { k = "L\(l.from)" }
            else if let w = n?.wait, w != 0, let ob = sp.onBridge { k = "S" + ob.pair }
            if let k { groups[k, default: []].append(sp) }
        }
        for list in groups.values where list.count >= 2 {
            let l = list.sorted { $0.seed < $1.seed }
            let sp = l[Int(floor(t / 2600)) % l.count]
            guard let h = hitBoxes[sp.id], let f = feet(sp, sim: sim) else { continue }
            let X = HouseLight.round(f.0), Y = HouseLight.round(f.1)
            let bx = X + h[0] + h[2] - S, by = Y + h[1] - 4 * S
            fx.add(out, bx - 1, by - 1, 9 * S + 2, 5 * S + 2)
            fx.add([255, 255, 255], bx, by, 9 * S, 5 * S); fx.add([255, 255, 255], bx + S, by + 5 * S, S, S)
            let dots = Int(floor(t / 300)) % 4
            for k in 0..<3 where dots > k { fx.add(HouseLight.rgb("#5a5a6a"), bx + (2 + k * 2) * S, by + 2 * S, S, S) }
        }

        // the extinguisher's foam
        for sp in sim.sprites {
            guard let h = sp.life.hold, h.kind == "ext", h.spraying == true, let tgid = h.target, let tg = byId[tgid],
                  let a = feet(sp, sim: sim), let bb = feet(tg, sim: sim) else { continue }
            let ax = a.0 + Double(h.dir ?? 1) * (sp.small ? 7 : 12), ay = a.1 - (sp.small ? 8 : 12)
            let bx = bb.0, by = bb.1 - (tg.small ? 10 : 18)
            for i in 0..<9 {
                let k = (t / 450 + Double(i) / 9).truncatingRemainder(dividingBy: 1)
                let x = ax + (bx - ax) * k, y = ay + (by - ay) * k - sin(k * .pi) * 4 * Double(S), s = 1 + (i % 3 != 0 ? 1 : 2)
                fx.add(litC("#b8c8d8"), HouseLight.round(x) - 1, HouseLight.round(y) - 1, s + 2, s + 2)
                fx.add(emiC("#ffffff", 0.85 + 0.15 * light.amb[0]), HouseLight.round(x), HouseLight.round(y), s, s)
            }
            let n = min(7, Int(floor((simT - (h.sprayFrom ?? simT)) / 350)))
            for i in 0..<max(0, n) {
                let x = HouseLight.round(bb.0 + Double((i * 7) % 13 - 6 - 2)), y = HouseLight.round(bb.1 - 2 - Double((i % 3) * 2))
                fx.add(litC("#a8b8c8"), x - 1, y - 1, 6, 4); fx.add(emiC("#f4f8ff"), x, y, 4, 2)
            }
        }

        // the lamp glow of the night (additive sprites)
        var used = Set<String>()
        if b.life.dark > 0.45, let lamp = parts.poses.lamp {
            for sp in sim.sprites where sp.kind == "agent" && sp.state == "working" && sp.goal?.cat == "work" && sp.path.isEmpty && sp.onBridge == nil && sp.goal?.room == sp.room {
                guard let key = sp.room, let r = roomFrame(key), sp.alpha > 0.001 else { continue }
                let p = iso(HouseLayout.Frame(ox: r.ox, oy: r.oy, drop: 0), sp.x + 0.2, sp.y - 1.1, sp.z + 11)
                let n = lampNodes[sp.id] ?? {
                    let rc = pages.rect(lamp.sprite)
                    let m = SKSpriteNode(texture: pages.texture(lamp.sprite), size: CGSize(width: rc.w, height: rc.h))
                    m.anchorPoint = CGPoint(x: 0, y: 1); m.blendMode = .add
                    if let sh = shaders.shader(page: rc.page, flag: rc.flag) { m.shader = sh }
                    movers.addChild(m); lampNodes[sp.id] = m; return m
                }()
                n.isHidden = false
                n.position = CGPoint(x: Double(HouseLight.round(p.0) - lamp.r), y: -Double(HouseLight.round(p.1) - lamp.r))
                n.zPosition = topZ + 3
                n.alpha = CGFloat(min(1, 0.55 * (b.life.dark - 0.3)))
                used.insert(sp.id)
            }
        }
        for (id, n) in lampNodes where !used.contains(id) { n.isHidden = true }

        // papers changing hands
        for p in b.papers {
            let e = (simT - p.t0) / 900
            guard e <= 1, let s = byId[p.from], let d = byId[p.to], let a = feet(s, sim: sim), let c = feet(d, sim: sim) else { continue }
            let x = a.0 + (c.0 - a.0) * e, y = a.1 + (c.1 - a.1) * e - 10 * Double(S) - sin(e * .pi) * 10 * Double(S)
            let px = HouseLight.round(x - 2), py = HouseLight.round(y - 2)
            let pc = litC("#ffffff"), lc = litC("#8a90a8")
            // PROP.paper: a 5x6 sheet at one pixel per cell with ruled lines
            fx.add(lc, px, py, 5, 6); fx.add(pc, px + 1, py + 1, 3, 4)
            fx.add(lc, px + 1, py + 2, 3, 1)
        }

        // puffs
        for p in b.puffs {
            let e = (simT - p.t0) / 750
            guard e <= 1, let r = roomFrame(p.room) else { continue }
            let q = iso(HouseLayout.Frame(ox: r.ox, oy: r.oy, drop: 0), p.x, p.y, p.z), c = HouseLight.rgb(p.col)
            for i in 0..<8 {
                let ang = Double(i) / 8 * 2 * .pi + p.seed, rr = 2 * Double(S) + e * 8 * Double(S)
                let s = max(1, HouseLight.round((1 - e) * 3 * Double(S))) + 1
                let x = HouseLight.round(q.0 + cos(ang) * rr - Double(s) / 2), y = HouseLight.round(q.1 - 6 * Double(S) + sin(ang) * rr * 0.6 - Double(s) / 2)
                fx.add([Int(Double(c[0]) * 0.7), Int(Double(c[1]) * 0.7), Int(Double(c[2]) * 0.75)], x - 1, y - 1, s + 2, s + 2, alpha: (1 - e) * 0.8)
                fx.add(c, x, y, s, s, alpha: 1 - e)
            }
        }

        // fireworks over the top of the tower
        let colors = ["#ff5a5a", "#ffd040", "#5ae0ff", "#a0ff70", "#ff80e0"]
        for f in b.life.fireworks {
            let e = simT - f.t0
            guard e <= 3800, let room = roomFrame(f.room) else { continue }
            let tower = layout.rooms.filter { $0.tower == room.tower }
            guard let top = tower.max(by: { $0.floor < $1.floor }) else { continue }
            let base = iso(HouseLayout.Frame(ox: top.ox, oy: top.oy, drop: 0), top.NX / 2, top.NY / 2, top.theme == "roof" || top.theme == "yard" ? 24 : parts.WH)
            for k in 0..<3 {
                let tk = e - Double(k) * 520
                guard tk >= 0 else { continue }
                let bx = HouseLight.round(base.0 + Double(k - 1) * 28 * Double(S))
                let by = HouseLight.round(max(base.1 - Double(42 + (k % 2) * 16) * Double(S), Double(26 + (k % 2) * 12) * Double(S)))
                let col = colors[(k + Int(f.seed)) % colors.count]
                if tk < 600 {
                    let y = base.1 - 4 * Double(S) + (Double(by) - base.1 + 4 * Double(S)) * (tk / 600)
                    fx.add(emiC("#fff0c0"), bx, HouseLight.round(y), S, 2 * S)
                    for j in 1..<4 { fx.add([255, 200, 120], bx, HouseLight.round(y + Double(j * 2 * S)), S, S, alpha: 0.6 - Double(j) * 0.15) }
                    continue
                }
                let bk = (tk - 600) / 1500
                guard bk <= 1 else { continue }
                if bk < 0.12 { fx.add([255, 255, 255], bx - 2 * S, by - 2 * S, 5 * S, 5 * S, alpha: 1 - bk / 0.12) }
                for j in 0..<20 {
                    let ang = Double(j) / 20 * 2 * .pi, rr = (1 - (1 - bk) * (1 - bk)) * 30 * Double(S)
                    if bk > 0.6 && (j + Int(floor(t / 90))) % 3 == 0 { continue }
                    let x = Double(bx) + cos(ang) * rr, y = Double(by) + sin(ang) * rr + bk * bk * 10 * Double(S)
                    fx.add(emiC(j % 4 != 0 ? col : "#ffffff"), HouseLight.round(x), HouseLight.round(y), S + 1, S + 1, alpha: 1 - bk * 0.8)
                    fx.add(emiC(col, 0.6), HouseLight.round(Double(bx) + cos(ang) * rr * 0.7), HouseLight.round(Double(by) + sin(ang) * rr * 0.7 + bk * bk * 7 * Double(S)), 1, 1, alpha: 1 - bk * 0.8)
                }
            }
        }

        // the fetch ball, when it is not in the dog's mouth
        if let bl = b.life.ball, !bl.held, let yard = roomFrame("__yard") {
            let p = b.ballAt(bl, simT)
            let G = -parts.SLAB
            let q = iso(HouseLayout.Frame(ox: yard.ox, oy: yard.oy, drop: 0), p[0], p[1], G + p[2])
            let sh = iso(HouseLayout.Frame(ox: yard.ox, oy: yard.oy, drop: 0), p[0], p[1], G)
            fx.add([0, 0, 0], HouseLight.round(sh.0) - 1, HouseLight.round(sh.1), 3, 1, alpha: 0.22)
            fx.add(out, HouseLight.round(q.0) - 2, HouseLight.round(q.1) - 4, 4, 4)
            fx.add(HouseLight.rgb("#f0d040"), HouseLight.round(q.0) - 1, HouseLight.round(q.1) - 3, 2, 2)
        }
    }

    func lampOff() { for (_, n) in lampNodes { n.isHidden = true } }
}
