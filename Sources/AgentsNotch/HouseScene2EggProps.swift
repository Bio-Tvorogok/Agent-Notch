import AppKit
import NotchCore
import SpriteKit

/// The page's eggItems on the roof: the Christmas garlands and tree, the disco's light spots and its mirror ball. They are live items of the
/// roof in the page (add(depth, fn, true)), so each is its own rect layer whose z sorts with the Clawds the way a room slot does.
extension HouseScene2 {
    private var S: Int { 2 }
    static let disco = ["#ff5a8a", "#5ae0ff", "#ffd040", "#a0ff70", "#c080ff", "#ff9a40"]

    /// The z of a live item at `depth` in a room: what place() gives a sprite of that depth.
    func eggItemZ(_ room: String, _ depth: Double) -> CGFloat {
        guard let info = roomInfo[room] else { return topZ }
        if depth >= 50 { return info.endZ + 3.5 } // above every Clawd (the deepest sits at endZ + 0.15 * depth, under 3.2), below the next layers of the room
        let slot = info.slots.first { $0.depth > depth }
        return ((slot?.z ?? info.endZ + 4) - 4) + CGFloat(depth) * 0.15
    }

    private func propLayer(_ name: String, depth: Double) -> HouseRects {
        let l = eggDraw.props[name] ?? { let r = rectPool(); eggDraw.props[name] = r; return r }()
        if l.parent !== root { l.removeFromParent(); root.addChild(l) }
        l.zPosition = eggItemZ("__roof", depth)
        return l
    }
    private func propChanged(_ name: String, _ sig: String) -> Bool {
        if eggDraw.sigs[name] == sig { return false }
        eggDraw.sigs[name] = sig; return true
    }

    private func eggPoly(_ r: HouseRects, _ cv: HouseRoomCanvas, _ pts: [[Double]], _ c: [Int], alpha: Double = 1, blend: Bool = false) {
        let s = cv.spans(pts)
        for (i, o) in s.out.enumerated() { if let o, o.1 > o.0 { r.add(c, o.0, s.y0 + i, o.1 - o.0, 1, alpha: alpha, blend: blend ? .add : .alpha) } }
    }
    private func eggLineA(_ r: HouseRects, _ a: [Double], _ b: [Double], _ c: [Int], alpha: Double = 1, blend: Bool = false) {
        let x0 = HouseLight.round(a[0]), y0 = HouseLight.round(a[1]), x1 = HouseLight.round(b[0]), y1 = HouseLight.round(b[1])
        let bl: SKBlendMode = blend ? .add : .alpha
        if x0 == x1 && y0 == y1 { r.add(c, x0, y0, 1, 1, alpha: alpha, blend: bl); return }
        if x0 == x1 || y0 == y1 { r.add(c, min(x0, x1), min(y0, y1), abs(x1 - x0) + 1, abs(y1 - y0) + 1, alpha: alpha, blend: bl); return }
        let n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in 0...n { r.add(c, HouseLight.round(Double(x0) + Double(x1 - x0) * Double(i) / Double(n)), HouseLight.round(Double(y0) + Double(y1 - y0) * Double(i) / Double(n)), 1, 1, alpha: alpha, blend: bl) }
    }

    private func eggGarland(_ r: HouseRects, _ cv: HouseRoomCanvas, _ t: Double, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, z: Double = 11.2) {
        let n = max(2, HouseLight.round(hypot(x1 - x0, y1 - y0) / 0.9)), steps = n * 6
        var prev: [Double]?
        let cols = ["#ff5a5a", "#ffd040", "#5ae0ff", "#ff80e0"]
        for i in 0...steps {
            let u = Double(i) / Double(steps), p = cv.iso(x0 + (x1 - x0) * u, y0 + (y1 - y0) * u, z - sin(Double(i % 6) / 6 * Double.pi) * 2.2)
            if let q = prev { cv.line(q, p, cv.lit("#2e7a3a")); cv.line([q[0], q[1] + 1], [p[0], p[1] + 1], cv.lit("#4aa84a")) }
            prev = p
            if i % 3 == 1 {
                let c = cols[(i / 3) % 4], on = light.dark > 0.2 && (Int(floor(t / 650)) + i) % 3 != 0
                r.add(on ? emiC(c) : litC(c), HouseLight.round(p[0]), HouseLight.round(p[1]) + 1, S, S)
            }
        }
    }

    private func eggTree(_ r: HouseRects, _ cv: HouseRoomCanvas, _ t: Double, _ x: Double, _ y: Double) {
        cv.box(x - 0.35, y - 0.35, 0, 0.7, 0.7, 3, "#c04848"); cv.box(x - 0.1, y - 0.1, 3, 0.2, 0.2, 3, "#6a4a2a")
        let q = cv.iso(x, y, 5), cx = HouseLight.round(q[0]), by = HouseLight.round(q[1])
        let cols = ["#ff5a5a", "#ffd040", "#5ae0ff", "#ff80e0"], dark = light.dark
        for (k, (w, h, up)) in [(9, 9, 0), (7, 8, 6), (5, 7, 11)].enumerated() {
            let b = Double(by - up * S), W = Double(w * S), H = Double(h * S)
            let tri = [[Double(cx) - W, b], [Double(cx) + W, b], [Double(cx), b - H]]
            cv.polyOutline(tri, litC("#2a1f2e")); cv.poly(tri, litC(k % 2 != 0 ? "#3e9a46" : "#2e8a3e"))
            cv.poly([[Double(cx), b - H], [Double(cx) + W, b], [Double(cx) + W - Double(2 * S), b]], litC("#246e32"))
            for i in 0..<(4 - k) {
                let ox = HouseLight.round((Double(i) - Double(3 - k) / 2) * 3.4 * Double(S)), oy = Int(b) - 2 * S - ((i + k) % 2) * 2 * S, c = cols[(i + k) % 4]
                r.add(dark > 0.2 && (Int(floor(t / 500)) + i + k) % 4 != 0 ? emiC(c) : litC(c), cx + ox, oy, S, S)
            }
        }
        let top = by - 18 * S
        r.add(emiC("#ffe060"), cx - 1, top - 3 * S, 2, 4 * S); r.add(emiC("#ffe060"), cx - 1 - S, top - 2 * S, 2 + 2 * S, 2 * S)
        if dark > 0.3 {
            eggGlow("treeGlow1", Double(cx), Double(top - S), Double(12 * S), "#ffe080", 0.25 * dark, layer: root, z: r.zPosition + 0.1)
            eggGlow("treeGlow2", Double(cx), Double(by - 8 * S), Double(20 * S), "#ffb070", 0.12 * dark, layer: root, z: r.zPosition + 0.1)
        }
    }

    /// Called every frame from updateEggs (the roof's props); `hol` and `party` come from the egg state.
    func updateEggProps(_ e: HouseEggs, _ t: Double) {
        guard let r0 = roomFrame("__roof"), !extraScreen else { hideEggProps(); return }
        let tt = roomClockOverride ?? clockMillis
        let dk = Int(light.dark * 20), xmas = e.holidays.xmas, party = e.party
        let cv: (HouseRects) -> HouseRoomCanvas = { HouseRoomCanvas(rects: $0, scene: self, ox: r0.ox, oy: r0.oy) }
        let drop = sim?.room("__roof").drop ?? 0
        let amb = "\(light.variant)|\(dk)|\(r0.ox)|\(r0.oy)|\(drop)"
        // garlands (behind, depth -0.9; in front, depth 30.1)
        for (name, depth, segs) in [("garlandBack", -0.9, [[0.0, 0, 10, 0], [0, 0, 0, 8]]), ("garlandFront", 30.1, [[0.0, 8, 10, 8], [10, 0, 10, 8]])] {
            let l = propLayer(name, depth: depth)
            guard propChanged(name, xmas ? "\(amb)|\(Int(floor(tt / 650)))" : "off") else { continue }
            l.begin(); defer { l.end() }
            if xmas { let c = cv(l); for s in segs { eggGarland(l, c, tt, s[0], s[1], s[2], s[3]) } }
        }
        do {
            let l = propLayer("tree", depth: 6.1)
            if propChanged("tree", xmas ? "\(amb)|\(Int(floor(tt / 500)))" : "off") {
                l.begin(); defer { l.end() }
                if xmas { eggTree(l, cv(l), tt, 1.6, 4.0) } else { eggDraw.nodes["treeGlow1"]?.isHidden = true; eggDraw.nodes["treeGlow2"]?.isHidden = true }
            }
            if xmas && light.dark > 0.3 { eggDraw.used.insert("treeGlow1"); eggDraw.used.insert("treeGlow2") } else { eggDraw.nodes["treeGlow1"]?.isHidden = true; eggDraw.nodes["treeGlow2"]?.isHidden = true }
        }
        // the disco: light spots on the deck (depth -0.4), the ball over everything (99)
        do {
            let l = propLayer("discoSpots", depth: -0.4)
            if propChanged("discoSpots", party ? "\(amb)|\(Int(floor(tt / 40)))" : "off") {
                l.begin(); defer { l.end() }
                if party {
                    let c = cv(l), n = Double(Self.disco.count)
                    for (i, hex) in Self.disco.enumerated() {
                        let a = tt / 1100 + Double(i) / n * Double.pi * 2, x = 5 + cos(a) * 3.4, y = 4 + sin(a * 1.2) * 2.6, q = 0.5, k = HouseLight.rgb(hex)
                        eggPoly(l, c, [c.iso(x - q, y, 0.05), c.iso(x, y - q, 0.05), c.iso(x + q, y, 0.05), c.iso(x, y + q, 0.05)], k, alpha: 0.35 + 0.35 * light.dark, blend: true)
                    }
                }
            }
            let b = propLayer("discoBall", depth: 99)
            if propChanged("discoBall", party ? "\(amb)|\(Int(floor(tt / 160)))|\(Int(floor(tt / 40)))" : "off") {
                b.begin(); defer { b.end() }
                if party { eggDiscoBall(b, cv(b), tt) } else { eggDraw.nodes["discoGlow"]?.isHidden = true }
            }
            if party { eggDraw.used.insert("discoGlow") }
        }
    }

    private func eggDiscoBall(_ r: HouseRects, _ cv: HouseRoomCanvas, _ t: Double) {
        cv.line(cv.iso(10, 0, 30), cv.iso(0, 8, 30), litC("#5a4a3a"))
        let bp = cv.iso(5, 4, 24), wp = cv.iso(5, 4, 30), bx = HouseLight.round(bp[0]), by = HouseLight.round(bp[1]), wx = HouseLight.round(wp[0]), wy = HouseLight.round(wp[1])
        cv.line([Double(wx), Double(wy)], [Double(bx), Double(by - 4 * S)], litC("#c0c0c8"))
        let n = Double(Self.disco.count), dark = light.dark
        for (i, hex) in Self.disco.enumerated() {
            let a = t / 1100 + Double(i) / n * Double.pi * 2, k = HouseLight.rgb(hex)
            eggLineA(r, [Double(bx), Double(by)], cv.iso(5 + cos(a) * 3.4, 4 + sin(a * 1.2) * 2.6, 0), k, alpha: 0.1 + 0.15 * dark, blend: true)
        }
        eggGlow("discoGlow", Double(bx), Double(by), Double(16 * S), "#ffffff", 0.1 + 0.2 * dark, layer: root, z: r.zPosition + 0.1)
        let rr = 4 * S, rot = Int(floor(t / 160)), out = litC("#2a1f2e")
        for y in (-rr - 1)...rr {
            let h = HouseLight.round(sqrt(max(0, pow(Double(rr) + 0.5, 2) - pow(Double(y) + 0.5, 2))))
            r.add(out, bx - h - 1, by + y, h * 2 + 2, 1)
        }
        let shades = ["#e8ecf4", "#9aa2b8", "#c8cede", "#ffffff"]
        for y in -rr..<rr {
            let h = HouseLight.round(sqrt(max(0, Double(rr * rr) - pow(Double(y) + 0.5, 2))))
            for x in -h..<h {
                let f = ((x + 64 + rot * 2) >> 1) + ((y + 64) >> 1), sh = shades[f & 3]
                let c = f % 7 == 0 ? emiC(Self.disco[(f + rot) % Self.disco.count]) : emiC(sh, 0.8 + 0.2 * light.amb[0] - (x + y > 2 ? 0.2 : 0))
                r.add(c, bx + x, by + y, 1, 1)
            }
        }
    }

    func hideEggProps() {
        for name in ["garlandBack", "garlandFront", "tree", "discoSpots", "discoBall"] {
            if let l = eggDraw.props[name], eggDraw.sigs[name] != "off" { l.begin(); l.end(); eggDraw.sigs[name] = "off" }
        }
        for n in ["treeGlow1", "treeGlow2", "discoGlow"] { eggDraw.nodes[n]?.isHidden = true }
    }
}
