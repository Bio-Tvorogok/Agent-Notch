import AppKit
import NotchCore
import SpriteKit

/// A pool of solid-colour rectangles in canvas pixels (y down, like the page's fillRect): the marks over a Clawd are a handful
/// of such rects, recoloured every frame, so no texture is made. Rects past `begin()`'s count stay hidden.
final class HouseRects: SKNode {
    private var pool: [SKSpriteNode] = []
    private var used = 0
    func begin() { used = 0 }
    func add(_ c: [Int], _ x: Int, _ y: Int, _ w: Int, _ h: Int, alpha: Double = 1, blend: SKBlendMode = .alpha) {
        guard w > 0, h > 0, alpha > 0 else { return }
        let n: SKSpriteNode
        if used < pool.count { n = pool[used] } else {
            n = SKSpriteNode(color: .white, size: .zero)
            n.anchorPoint = CGPoint(x: 0, y: 1)
            addChild(n); pool.append(n)
        }
        used += 1
        n.isHidden = false
        n.color = SKColor(srgbRed: CGFloat(c[0]) / 255, green: CGFloat(c[1]) / 255, blue: CGFloat(c[2]) / 255, alpha: 1)
        n.alpha = CGFloat(min(1, alpha))
        n.blendMode = blend
        n.size = CGSize(width: w, height: h)
        n.position = CGPoint(x: x, y: -y)
        n.zPosition = CGFloat(used) * 0.0001
    }
    func end() { if used < pool.count { for i in used..<pool.count { pool[i].isHidden = true } } }
}

/// What the page's drawClawd paints over a Clawd that is not a body pose: the context battery and eyelids, and the status marks
/// (the "!" of a waiting agent, the smoke of an error, the Zs of a sleeper). They follow the sprite while it walks, so they are
/// drawn here from the page's own formulas, in the sprite's coordinates (the feet are (0, 0)), and not baked into the poses.
extension HouseScene2 {
    func litRGB(_ c: [Int], _ k: Double = 1) -> [Int] { (0..<3).map { Int(min(255, Double(c[$0]) * light.amb[$0] * k)) } }
    func litC(_ hex: String, _ k: Double = 1) -> [Int] { litRGB(HouseLight.rgb(hex), k) }
    func emiC(_ hex: String, _ k: Double = 1) -> [Int] { HouseLight.rgb(hex).map { Int(min(255, Double($0) * k)) } }
    func mixC(_ a: String, _ b: String, _ t: Double) -> [Int] {
        let A = HouseLight.rgb(a), B = HouseLight.rgb(b)
        return (0..<3).map { HouseLight.round(Double(A[$0]) + Double(B[$0] - A[$0]) * t) }
    }

    /// The look key in parts.json poses.looks for a sprite.
    func lookKey(_ sp: HouseSprite, _ look: HouseLook) -> String {
        sp.kind == "home" ? "home" : look.vendor + (sp.small ? "-mini" : "")
    }

    /// Feet-relative hit box of a Clawd (the page's sp.hit): left - 2S, top - 2S, (w + 4) C, (rows + legH + 4) C.
    func hitBox(_ sp: HouseSprite, geo g: HouseParts.Look, t: Double) -> [Int] {
        let C = 2
        return [-(g.w * C) / 2 - 2 * C, -(g.rows + g.legH) * C - hop(sp, t) - 2 * C, (g.w + 4) * C, (g.rows + g.legH + 4) * C]
    }

    func hop(_ sp: HouseSprite, _ t: Double) -> Int {
        if sp.state == "waiting" && !sp.moving { return HouseLight.round(abs(sin(t / 260)) * 3) }
        return sp.moving ? (Int(floor(t / 110)) % 2) * 2 : 0
    }

    /// The info and the marks of one Clawd, at animation time t (halved already for a drowsy one). `node` is the mover node,
    /// whose children they are: its alpha fades the info with the sprite (the marks too: the page draws them opaque, a fade-in is short).
    func updateMarks(_ sp: HouseSprite, node n: SKSpriteNode, ax0: Int, ay0: Int, look: HouseLook, t: Double, napFace: Int? = nil, feetX: Double = 0) {
        let id = sp.id
        let info = infoRects[id] ?? { let r = HouseRects(); r.zPosition = 0.001; n.addChild(r); infoRects[id] = r; return r }()
        let marks = markRects[id] ?? { let r = HouseRects(); r.zPosition = 0.002; n.addChild(r); markRects[id] = r; return r }()
        if info.parent !== n { info.removeFromParent(); n.addChild(info) }
        if marks.parent !== n { marks.removeFromParent(); n.addChild(marks) }
        info.position = CGPoint(x: ax0, y: -ay0); marks.position = info.position
        info.begin(); marks.begin()
        defer { info.end(); marks.end() }
        if let face = napFace { // the Zs of a napping cat or dog: the page's drawCat / drawDog (the atlas pose is cut without them)
            let cat = sp.kind == "cat", period = cat ? 1800.0 : 1900.0, k = (t / period + sp.seed).truncatingRemainder(dividingBy: 1)
            let zx = HouseLight.round(feetX + Double(face < 0 ? (cat ? -6 : -7) : (cat ? 4 : 5)) + k * 3), zy = HouseLight.round(Double(-(cat ? 5 : 7) - 2) - k * 7), a = (1 - k) * 0.8
            marks.add([255, 255, 255], zx - HouseLight.round(feetX), zy, 3, 1, alpha: a); marks.add([255, 255, 255], zx - HouseLight.round(feetX) + 1, zy + 1, 1, 1, alpha: a)
            marks.add([255, 255, 255], zx - HouseLight.round(feetX), zy + 2, 3, 1, alpha: a)
            return
        }
        guard sp.kind != "cat", sp.kind != "dog", let g = parts.poses.looks?[lookKey(sp, look)] else { return }
        let S = 2, C = 2, st = sp.state ?? "", moving = sp.moving
        let w = g.w, left = -(w * C) / 2, top = -(g.rows + g.legH) * C - hop(sp, t)
        let sleeping = st == "done" || st == "idle-sleep" || st == "shower"
        let red = st == "error" ? 0.5 + 0.5 * sin(t / 300) : 0
        let bc = red > 0 ? mixC(g.body, "#e0503c", red * 0.7) : HouseLight.rgb(g.body)
        _ = moving

        // infoOverClawd: heavy eyelids and the battery
        if let ctx = sp.context.map({ min(1, max(0, $0)) }), st != "fall" {
            let f = ctx
            if f >= 0.9 && !sleeping {
                let c = litRGB((0..<3).map { HouseLight.round(Double(bc[$0]) * 0.65) })
                for e in g.eyes where e.count >= 2 { info.add(c, left + e[0] * C, top + e[1] * C, C, (C + 1) / 2) }
            }
            let rem = 1 - f, nn = 4, cell = S, inner = nn * cell + (nn - 1), bw = inner + 2, bh = 2 * S + 2
            let x = left - bw - 1, y = top - bh - 3
            let col = f >= 0.9 ? "#e5534b" : f >= 0.7 ? "#f0c040" : "#58c860"
            let blink = f >= 0.97 && Int(floor(t / 400)) % 2 == 1
            let out = litC("#2a1f2e")
            info.add(out, x - 1, y - 1, bw + 2, bh + 2); info.add(out, x + bw, y + 1, 2, bh - 2)
            let face = blink ? emiC("#e5534b") : litC("#f4f0e8")
            info.add(face, x, y, bw, bh); info.add(face, x + bw, y + 2, 1, bh - 4)
            info.add(HouseLight.rgb("#20182a"), x + 1, y + 1, inner, bh - 2)
            let on = max(0, min(nn, Int(ceil(rem * Double(nn) - 0.001))))
            for i in 0..<on { info.add(emiC(col), x + 1 + i * (cell + 1), y + 1, cell, bh - 2) }
        }

        // the status marks
        if st == "waiting" {
            let bw = 9 * S, bx = -(bw >> 1), by = top - 12 * S + HouseLight.round(sin(t / 400) * Double(S))
            let out = litC("#2a1f2e")
            marks.add(out, bx - 1, by - 1, bw + 2, bw + 2); marks.add(out, bx + 3 * S - 1, by + bw, 2 * S + 2, 2 * S + 1)
            marks.add([255, 255, 255], bx, by, bw, bw); marks.add([255, 255, 255], bx + 3 * S, by + bw, 2 * S, 2 * S)
            let amber = HouseLight.rgb("#f0a000")
            marks.add(amber, bx + 4 * S, by + 2 * S, S, 4 * S); marks.add(amber, bx + 4 * S, by + 7 * S, S, S)
        } else if st == "error" && sp.life.fire == nil {
            for i in 0..<3 {
                let k = (t / 900 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let c = i == 1 ? [240, 90, 60] : [120, 120, 130], a = i == 1 ? (1 - k) * 0.9 : (1 - k) * 0.8
                marks.add(c, -3 * S + i * 3 * S, HouseLight.round(Double(top) - 2 * Double(S) - k * 10 * Double(S)), 2 * S, 2 * S, alpha: a)
            }
        } else if sleeping && st != "shower" {
            let k = (t / 1400 + sp.seed).truncatingRemainder(dividingBy: 1), a = (1 - k) * 0.9
            let zx = HouseLight.round(Double(5 * S) + k * Double(3 * S)), zy = HouseLight.round(Double(top) - 2 * Double(S) - k * 8 * Double(S))
            marks.add([255, 255, 255], zx, zy, 3 * S, S, alpha: a); marks.add([255, 255, 255], zx + S, zy + S, S, S, alpha: a)
            marks.add([255, 255, 255], zx, zy + 2 * S, 3 * S, S, alpha: a)
        }

        // drawBathing: lather and bubbles of a shower, the towel rubbing a head dry, the turban after it
        let bw = w * C
        func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, v)) }
        if st == "shower" {
            let e = sp.behaviour.errand
            let k = (e?.t0).flatMap { t0 in e?.dur.map { (t - t0) / $0 } } ?? (t / 9000 + sp.seed).truncatingRemainder(dividingBy: 1)
            let grow = clamp((k - 0.08) / 0.2, 0, 1) * clamp((0.82 - k) / 0.1, 0, 1)
            if grow > 0 {
                let n = HouseLight.round(3 + grow * 6), out = litC("#2a1f2e")
                for i in 0..<n {
                    let u = (Double(i) * 0.618 + sp.seed).truncatingRemainder(dividingBy: 1)
                    let bx = HouseLight.round((u - 0.5) * Double(bw - 2 * C)), by = top - C - HouseLight.round((Double(i) * 0.37).truncatingRemainder(dividingBy: 1) * 2 * Double(C) * grow)
                    let z = i % 2 != 0 ? 2 * C : C
                    marks.add(out, bx - 1, by - 1, z + 2, z + 2); marks.add(litC(i % 3 != 0 ? "#ffffff" : "#e4eef6"), bx, by, z, z)
                }
                for i in 0..<3 {
                    let q = (t / 1300 + Double(i) / 3 + sp.seed).truncatingRemainder(dividingBy: 1)
                    marks.add([255, 255, 255], HouseLight.round(sin(t / 400 + Double(i) * 2) * 4) + (i - 1) * 3 * C, HouseLight.round(Double(top - 3 * C) - q * 12 * Double(C)), C, C, alpha: (1 - q) * 0.85 * grow)
                }
            }
        } else if st == "dry" {
            let sw = HouseLight.round(sin(t / 110) * 2 * Double(C)), y = top + HouseLight.round((1 + sin(t / 220)) * Double(C) * 0.5)
            marks.add(litC("#2a1f2e"), left - C + sw - 1, y - 1, bw + 2 * C + 2, 2 * C + 2)
            marks.add(litC("#7ac0e8"), left - C + sw, y, bw + 2 * C, 2 * C); marks.add(litC("#4a8ab8"), left - C + sw, y + HouseLight.round(Double(C) * 1.5), bw + 2 * C, max(1, C >> 1))
        } else if let tw = sp.behaviour.towel, tw > t {
            let x0 = left + C, ww = bw - 2 * C, y = top - 2 * C, out = litC("#2a1f2e")
            marks.add(out, x0 - 1, y - 1, ww + 2, 2 * C + 2); marks.add(out, -C - 1, y - 2 * C - 1, 2 * C + 2, 2 * C + 2)
            marks.add(litC("#7ac0e8"), x0, y, ww, 2 * C); marks.add(litC("#7ac0e8"), -C, y - 2 * C, 2 * C, 2 * C)
            marks.add(litC("#4a8ab8"), x0, y + C, ww, max(1, C >> 1))
        }
    }
}
