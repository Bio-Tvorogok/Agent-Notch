import AppKit
import NotchCore
import SpriteKit

/// What the scene keeps for drawing the eggs (HouseEggs in NotchCore holds the state): the sky layer (below the house), the layer over
/// it (hearts, stars, the UFO, the ghost, the letter), the textured nodes pooled by name and the textures cached by light.
final class HouseEggDraw {
    var sky: HouseRects?, over: HouseRects?, add: HouseRects?
    var nodes: [String: SKSpriteNode] = [:]
    var used = Set<String>()
    var cache: [String: SKTexture] = [:]
    var glows: [String: SKTexture] = [:]
    var ambKey = ""
    var card: String?
}

/// The page's easter eggs that are drawn in the sky and over the house: the constellation, the whale, the sunglasses on the sun, the rain
/// of a clicked cloud, the Halloween bats, the Valentine hearts, the high-five stars, the UFO and its beam, the ghost and the mailbox letter.
/// pxStamp/glow/line are the page's own (rows of characters, a radial light, 1 px rects); the numbers are the page's eggSky/eggOver.
extension HouseScene2 {
    private var S: Int { 2 }

    static let whaleRows: [String] = {
        let W = 40, H = 16
        func cyAt(_ c: Int) -> Double { c < 16 ? 7.5 - Double(16 - c) * 0.22 : 7.5 }
        func half(_ c: Int) -> Double {
            if c >= 13 { return max(1.4, 5.6 * sqrt(max(0, 1 - pow(abs(Double(c) - 26.5) / 13.5, 2.6)))) }
            return c >= 5 ? 1.0 + Double(c - 5) * 0.05 : 4.2 - Double(c) * 0.55
        }
        var rows: [String] = []
        for r in 0..<H {
            var s = ""
            for c in 0..<W {
                let cy = cyAt(c), dy = Double(r) + 0.5 - cy, h = half(c)
                var ch: Character = "."
                if abs(dy) <= h && !(c <= 1 && abs(dy) < 1) {
                    ch = dy - 1 < -h ? "h" : "b"
                    if c > 15 && dy > h * 0.3 { ch = r % 2 != 0 ? "g" : "l" }
                    if c == 33 && r == 7 { ch = "e" }
                    if r == 9 && c >= 30 && c <= 38 { ch = "m" }
                }
                if r >= 11 && r <= 14 && c >= 22 - (r - 11) && c <= 25 - (r - 11) { ch = "f" }
                s.append(ch)
            }
            rows.append(s)
        }
        return rows
    }()
    static let batRows: [[String]] = [["#.....#", "##.#.##", ".#####.", "...#..."], [".......", "..#.#..", "#######", "#.....#"]]
    static let heartRows = [".rr.rr.", "rwrrrrr", "rrrrrrr", ".rrrrr.", "..rrr..", "...r..."]
    static let star5Rows = ["..y..", ".yyy.", "yyyyy", ".yyy.", ".y.y."]
    static let ufoRows = [".......cccccc.......", "......cwcccccc......", ".....cccccccccc.....", "..mmmmmmmmmmmmmmmm..",
                          "mMMMMMMMMMMMMMMMMMMm", ".mmlmmmlmmmlmmmlmmm.", "....dddddddddddd...."]
    static let ghostRows = ["...wwwwww...", "..wwwwwwww..", "..wEwwwwEw..", "wwwwwwwwwwww", "wwwwwoowwwww", "..wwwwwwww..", "..wwwwwwww.."]
    static let ghostHem = ["..w.ww.ww.w.", "..ww.ww.ww.."]
    static let letterRows = ["eeeeeeee", "edeeeede", "eedrrdee", "eeeddeee", "eeeeeeee"]
    static let constStars: [[Double]] = [[2, 0], [10, 0], [10, 6], [2, 6], [0, 2.6], [12, 2.6], [4.2, 1.8], [7.8, 1.8], [3, 8.4], [5, 8.4], [7, 8.4], [9, 8.4]]
    static let constLines: [[[Double]]] = [[[2, 0], [10, 0]], [[10, 0], [10, 6]], [[10, 6], [2, 6]], [[2, 6], [2, 0]], [[2, 2.6], [0, 2.6]], [[10, 2.6], [12, 2.6]],
                                          [[3, 6], [3, 8.4]], [[5, 6], [5, 8.4]], [[7, 6], [7, 8.4]], [[9, 6], [9, 8.4]]]

    // MARK: helpers

    /// pxStamp(x0, y0, rows, pal, flip, k, noLine) as a texture whose origin is (x0 - 1, y0 - 1) with the outline, (x0, y0) without.
    func eggStamp(_ key: String, _ rows: [String], _ pal: [Character: [Int]], flip: Bool = false, k: Int = 1, line: [Int]? = nil) -> (SKTexture, CGSize) {
        let w = rows[0].count, pad = line != nil ? 1 : 0
        let size = CGSize(width: w * k + 2 * pad, height: rows.count * k + 2 * pad)
        if let t = eggDraw.cache[key] { return (t, size) }
        let p = HousePixels(Int(size.width), Int(size.height))
        func X(_ c: Int) -> Int { pad + (flip ? w - 1 - c : c) * k }
        let cells = rows.map { Array($0) }
        if let line {
            for (r, row) in cells.enumerated() { for c in 0..<w where row[c] != "." { p.fill(line, X(c) - 1, pad + r * k - 1, k + 2, k + 2) } }
        }
        for (r, row) in cells.enumerated() { for c in 0..<w { if row[c] != ".", let col = pal[row[c]] { p.fill(col, X(c), pad + r * k, k, k) } } }
        let t = SKTexture(cgImage: p.image()); t.filteringMode = .nearest
        if eggDraw.cache.count > 96 { eggDraw.cache.removeAll() }
        eggDraw.cache[key] = t
        return (t, size)
    }

    /// A pooled textured node by name, shown at the canvas pixel (x, y) (its top left); the ones not shown in a frame are hidden after it.
    func eggShow(_ name: String, _ tex: SKTexture, _ size: CGSize, x: Int, y: Int, alpha: Double = 1, layer: SKNode, z: CGFloat, blend: SKBlendMode = .alpha) {
        let n = eggDraw.nodes[name] ?? {
            let m = SKSpriteNode(); m.anchorPoint = CGPoint(x: 0, y: 1); HouseRects.created += 1; eggDraw.nodes[name] = m; return m
        }()
        if n.parent !== layer { n.removeFromParent(); layer.addChild(n) }
        if n.texture !== tex { n.texture = tex }
        if n.size != size { n.size = size }
        n.position = CGPoint(x: x, y: -y); n.zPosition = z; n.alpha = CGFloat(min(1, max(0, alpha))); n.blendMode = blend
        n.isHidden = false
        eggDraw.used.insert(name)
    }

    /// glow(x, y, rad, color, k): the page's soft round light, additive.
    func eggGlow(_ name: String, _ x: Double, _ y: Double, _ rad: Double, _ hex: String, _ k: Double, layer: SKNode, z: CGFloat) {
        let r = max(1, HouseLight.round(rad)), key = hex + "|\(r)"
        let tex: SKTexture
        if let t = eggDraw.glows[key] { tex = t } else {
            let p = HousePixels(2 * r, 2 * r), c = HouseLight.rgb(hex)
            let cs = HousePixels.space, comps: [CGFloat] = [CGFloat(c[0]) / 255, CGFloat(c[1]) / 255, CGFloat(c[2]) / 255, 1, CGFloat(c[0]) / 255, CGFloat(c[1]) / 255, CGFloat(c[2]) / 255, 0]
            if let g = CGGradient(colorSpace: cs, colorComponents: comps, locations: [0, 1], count: 2) {
                p.ctx.drawRadialGradient(g, startCenter: CGPoint(x: r, y: r), startRadius: 0, endCenter: CGPoint(x: r, y: r), endRadius: CGFloat(r), options: [])
            }
            tex = SKTexture(cgImage: p.image()); tex.filteringMode = .nearest
            if eggDraw.glows.count > 64 { eggDraw.glows.removeAll() }
            eggDraw.glows[key] = tex
        }
        eggShow(name, tex, CGSize(width: 2 * r, height: 2 * r), x: HouseLight.round(x) - r, y: HouseLight.round(y) - r, alpha: k, layer: layer, z: z, blend: .add)
    }

    /// The page's line(): 1 px steps between the rounded ends.
    func eggLine(_ p: HousePixels, _ a: [Double], _ b: [Double], _ c: [Int], alpha: Double, dx: Int, dy: Int) {
        let x0 = HouseLight.round(a[0]), y0 = HouseLight.round(a[1]), x1 = HouseLight.round(b[0]), y1 = HouseLight.round(b[1])
        if x0 == x1 && y0 == y1 { p.fill(c, x0 - dx, y0 - dy, 1, 1, alpha: alpha); p.fill(c, x0 - dx, y0 - dy, 1, 1, alpha: alpha); return }
        if x0 == x1 || y0 == y1 { p.fill(c, min(x0, x1) - dx, min(y0, y1) - dy, abs(x1 - x0) + 1, abs(y1 - y0) + 1, alpha: alpha); return }
        let n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in 0...n {
            p.fill(c, HouseLight.round(Double(x0) + Double(x1 - x0) * Double(i) / Double(n)) - dx, HouseLight.round(Double(y0) + Double(y1 - y0) * Double(i) / Double(n)) - dy, 1, 1, alpha: alpha)
        }
    }

    /// The page's spans(): the rounded polygon on integer scanlines.
    static func eggSpans(_ pts: [[Double]]) -> (y0: Int, rows: [(Int, Int)?]) {
        let P = pts.map { [HouseLight.round($0[0]), HouseLight.round($0[1])] }, n = P.count
        guard let y0 = P.map({ $0[1] }).min(), let y1 = P.map({ $0[1] }).max(), y1 > y0 else { return (0, []) }
        var out: [(Int, Int)?] = []
        for y in y0..<y1 {
            let yc = Double(y) + 0.5
            var l = Double.infinity, r = -Double.infinity
            for i in 0..<n {
                let a = P[i], b = P[(i + 1) % n]
                if (Double(a[1]) <= yc && Double(b[1]) > yc) || (Double(b[1]) <= yc && Double(a[1]) > yc) {
                    let x = Double(a[0]) + (yc - Double(a[1])) * Double(b[0] - a[0]) / Double(b[1] - a[1])
                    l = min(l, x); r = max(r, x)
                }
            }
            out.append(l < r ? (HouseLight.round(l), HouseLight.round(r)) : nil)
        }
        return (y0, out)
    }

    /// The page's sun and clouds of this frame, for the click secrets and the rain.
    func eggFeed(_ e: HouseEggs) {
        let W = Double(canvasW), H = Double(canvasH), S = 2.0
        let gnd = Double(HousePainter.groundOf(layout: layout, env: env))
        let k = (hour - 6) / 13.5
        if !extraScreen && k > -0.08 && k < 1.08 {
            e.sun = [Double(HouseLight.round((W * (0.08 + 0.84 * k)))), Double(HouseLight.round(gnd + 5 * S - sin(Double.pi * k) * (gnd - H * 0.1)))]
        } else { e.sun = nil }
        e.clouds = clouds.map { (i, n) in
            let x = HouseLight.round(((Double(i) * 131 * S + clockMillis * (0.004 + Double(i % 3) * 0.002) * S).truncatingRemainder(dividingBy: W + 80 * S)) - 60 * S)
            let y = HouseLight.round(8 * S + (Double(i) * 29 * S).truncatingRemainder(dividingBy: max(20, min(H * 0.3, gnd * 0.45))))
            return [Double(x), Double(y), Double(n.size.width)]
        }
        e.dark = light.dark
        e.extra = extraScreen
    }

    /// eggLook's dy: the party's beat and the UFO's lift raise the sprite (canvas pixels).
    func eggLift(_ sp: HouseSprite) -> Double {
        guard let b = behaviour, let e = b.eggs, e.enabled else { return 0 }
        var dy = 0.0
        if e.party && sp.kind == "agent" && sp.state == "working" { dy += Double(HouseLight.round(abs(sin(b.time * Double.pi / 480)) * 3)) }
        if let u = e.ufo, u.target === sp, u.lift != 0 { dy += u.lift }
        return dy
    }

    var eggsMoving: Bool { behaviour?.eggs.map { $0.isMoving(at: behaviour!.time) } ?? false }

    // MARK: frame

    func updateEggs(sim: HouseSim, simT: Double, t clock: Double) {
        let t = simT
        guard let b = behaviour, let e = b.eggs, e.enabled else {
            if eggDraw.sky != nil || !eggDraw.used.isEmpty { eggsHideAll() }
            return
        }
        eggFeed(e)
        let ak = "\(Int(light.amb[0] * 255)),\(Int(light.amb[1] * 255)),\(Int(light.amb[2] * 255))"
        if ak != eggDraw.ambKey { eggDraw.cache.removeAll(); eggDraw.ambKey = ak }
        let sky = eggDraw.sky ?? { let r = rectPool(); eggDraw.sky = r; return r }()
        let over = eggDraw.over ?? { let r = rectPool(); eggDraw.over = r; return r }()
        let add = eggDraw.add ?? { let r = rectPool(); eggDraw.add = r; return r }()
        let skyZ: CGFloat = -46_499, overZ = topZ + 5
        for (l, z) in [(sky, skyZ), (over, overZ), (add, overZ + 0.5)] {
            if l.parent !== root { l.removeFromParent(); root.addChild(l) }
            l.zPosition = z
        }
        eggDraw.used.removeAll(keepingCapacity: true)
        sky.begin(); over.begin(); add.begin()
        if !extraScreen { eggConstellation(t, sky: sky, layer: root, z: skyZ) }
        if !extraScreen { eggWhale(e, t, sky: sky, z: skyZ) }
        if t < e.shadesUntil, let s = e.sun { eggShades(s, sky) }
        eggRain(e, t, sky)
        if e.holidays.halloween && light.dark > 0.5 && !extraScreen { eggBats(t, sky: sky, z: skyZ) }
        eggHearts(e, t, over: over, z: overZ)
        eggStars(e, t, over: over, z: overZ)
        eggUFO(e, t, add: add, z: overZ)
        eggGhost(e, t, z: overZ)
        eggLetter(e, t, z: overZ)
        sky.end(); over.end(); add.end()
        for (name, n) in eggDraw.nodes where !eggDraw.used.contains(name) && !n.isHidden { n.isHidden = true }
    }

    func eggsHideAll() {
        eggDraw.sky?.begin(); eggDraw.sky?.end(); eggDraw.over?.begin(); eggDraw.over?.end(); eggDraw.add?.begin(); eggDraw.add?.end()
        for n in eggDraw.nodes.values { n.isHidden = true }
        eggDraw.used.removeAll()
        setEggCard(nil, x: 0, y: 0)
    }

    private func setEggCard(_ text: String?, x: Double, y: Double) {
        if text != eggDraw.card { eggDraw.card = text }
        onEggCard?(text, x, y)
    }

    // MARK: the sky

    private func eggConstellation(_ t: Double, sky: HouseRects, layer: SKNode, z: CGFloat) {
        let dark = light.dark
        guard dark > 0.45 else { return }
        let W = Double(canvasW), H = Double(canvasH)
        let a = min(1, (dark - 0.45) / 0.35), u = 4.0 * Double(S)
        let ox = HouseLight.round(min(W * 0.7, W - 15 * u)), oy = HouseLight.round(H * 0.07)
        func P(_ p: [Double]) -> [Double] { [Double(ox) + p[0] * u, Double(oy) + p[1] * u] }
        let key = "const|\(Int(a * 64))|\(ox)|\(oy)"
        let size = CGSize(width: 100, height: 72)
        let tex: SKTexture
        if let c = eggDraw.cache[key] { tex = c } else {
            let p = HousePixels(Int(size.width), Int(size.height))
            for l in Self.constLines { eggLine(p, P(l[0]), P(l[1]), [190, 205, 255], alpha: 0.16 * a, dx: ox - 2, dy: oy - 2) }
            tex = SKTexture(cgImage: p.image()); tex.filteringMode = .nearest
            eggDraw.cache[key] = tex
        }
        eggShow("const", tex, size, x: ox - 2, y: oy - 2, layer: layer, z: z)
        for (i, s) in Self.constStars.enumerated() {
            let q = P(s), x = HouseLight.round(q[0]), y = HouseLight.round(q[1]), tw = 0.6 + 0.4 * sin(t / 1300 + Double(i) * 2.1)
            sky.add([255, 248, 215], x - 1, y - 1, 2, 2, alpha: a * tw)
            if i < 6 {
                let f = a * tw * 0.4
                sky.add([255, 248, 215], x - 3, y - 1, 1, 2, alpha: f); sky.add([255, 248, 215], x + 2, y - 1, 1, 2, alpha: f)
                sky.add([255, 248, 215], x - 1, y - 3, 2, 1, alpha: f); sky.add([255, 248, 215], x - 1, y + 2, 2, 1, alpha: f)
            }
        }
    }

    private func eggWhale(_ e: HouseEggs, _ t: Double, sky: HouseRects, z: CGFloat) {
        guard let w = e.whale else { return }
        let k = S + 1, x = e.whaleX(w, at: t), flip = w.dir < 0
        let y = HouseLight.round(w.y + sin(t / 2600 + w.seed) * 3 * Double(S)), x0 = HouseLight.round(x - 20 * Double(k))
        let pal: [Character: [Int]] = ["b": litC("#5a7ec0"), "h": litC("#86a8e0"), "l": litC("#dce6f4"), "g": litC("#a8b8d8"), "e": litC("#141a2a"), "m": litC("#3a4e80"), "f": litC("#46669e")]
        let (tex, size) = eggStamp("whale\(flip)", Self.whaleRows, pal, flip: flip, k: k, line: litC("#2a1f2e"))
        eggShow("whale", tex, size, x: x0 - 1, y: y - 1, layer: root, z: z + 0.01)
        let sp = (t - w.t0).truncatingRemainder(dividingBy: 7000)
        if sp < 1800 {
            let hx = Double(x0) + (w.dir > 0 ? 30 : 9) * Double(k), q = sp / 1800
            for i in 0..<7 {
                let side = i % 2 != 0 ? 1.0 : -1.0, rise = min(1, q * 2) * Double(3 + (i >> 1) * 3) * Double(S), fall = max(0, q * 2 - 1) * 4 * Double(S)
                sky.add([220, 240, 255], HouseLight.round(hx + side * Double(i >> 1) * Double(S) * (0.5 + q)), HouseLight.round(Double(y) - rise + fall), S, S, alpha: (1 - q) * 0.9)
            }
        }
    }

    private func eggShades(_ s: [Double], _ r: HouseRects) {
        let x = Int(s[0]), y = Int(s[1]), d = [22, 18, 30], S = self.S
        r.add(d, x - 5 * S, y - 2 * S, 4 * S, 2 * S + 1); r.add(d, x + S, y - 2 * S, 4 * S, 2 * S + 1); r.add(d, x - S, y - 2 * S, 2 * S, S)
        r.add(d, x - 6 * S, y - 2 * S, S, 1); r.add(d, x + 5 * S, y - 2 * S, S, 1)
        r.add([255, 255, 255], x - 4 * S, y - 2 * S + 1, S, 1, alpha: 0.85); r.add([255, 255, 255], x + 2 * S, y - 2 * S + 1, S, 1, alpha: 0.85)
        let o = HouseLight.rgb("#d88a30")
        r.add(o, x - 2 * S, y + 2 * S, 4 * S, 1); r.add(o, x - 2 * S - 1, y + 2 * S - 1, 1, 1); r.add(o, x + 2 * S, y + 2 * S - 1, 1, 1)
    }

    private func eggRain(_ e: HouseEggs, _ t: Double, _ r: HouseRects) {
        let S = self.S
        for (i, until) in e.rain.sorted(by: { $0.key < $1.key }) {
            guard i < e.clouds.count, t <= until else { continue }
            let c = e.clouds[i], x = Int(c[0]), y = Int(c[1]), w = Int(c[2]), fade = min(1, (until - t) / 600)
            let body = [70, 76, 100]
            r.add(body, x, y, w, 5 * S, alpha: 0.38 * fade); r.add(body, x + 5 * S, y - 3 * S, w - 12 * S, 3 * S, alpha: 0.38 * fade)
            r.add(body, x + 9 * S, y - 5 * S, Int(Double(w) * 0.35), 2 * S, alpha: 0.38 * fade)
            var j = 0
            while Double(j) < Double(w) / Double(2 * S) - 1 {
                let k = (t / 700 + Self.scRnd(Double(j), Double(i))).truncatingRemainder(dividingBy: 1)
                let dx = x + 2 * S + j * 2 * S + HouseLight.round(Self.scRnd(Double(j), Double(i + 3)) * Double(S))
                let col = light.dark > 0.5 ? [170, 200, 245] : [60, 100, 190]
                r.add(col, dx, HouseLight.round(Double(y + 5 * S) + k * 60 * Double(S)), 1, 3 * S, alpha: fade * (1 - k * 0.7))
                j += 1
            }
        }
    }

    private func eggBats(_ t: Double, sky: HouseRects, z: CGFloat) {
        guard let roof = layout.rooms.first(where: { $0.key == "__roof" }) ?? layout.rooms.first else { return }
        let c = HouseRoomCanvas(rects: sky, scene: self, ox: roof.ox, oy: roof.oy).iso(roof.NX / 2, roof.NY / 2, 60), S = Double(self.S)
        for i in 0..<5 {
            let a = t / (2300 + Double(i) * 310) + Double(i) * 1.7
            let x = c[0] + cos(a) * (46 + Double(i) * 9) * S, y = c[1] + sin(a * 1.3) * 12 * S - Double(i) * 5 * S
            let f = Int(floor(t / 130 + Double(i))) % 2, X = HouseLight.round(x), Y = HouseLight.round(y)
            let (tex, size) = eggStamp("bat\(f)", Self.batRows[f], ["#": emiC("#4a3462")], k: self.S)
            eggShow("bat\(i)", tex, size, x: X - 3 * self.S, y: Y - 2 * self.S, layer: root, z: z + 0.02)
            sky.add(HouseLight.rgb("#ff6a40"), X - self.S + 1, Y, 1, 1); sky.add(HouseLight.rgb("#ff6a40"), X + self.S, Y, 1, 1)
        }
    }

    // MARK: over the house

    private func eggHearts(_ e: HouseEggs, _ t: Double, over: HouseRects, z: CGFloat) {
        for (i, h) in e.hearts.prefix(40).enumerated() {
            let ee = (t - h.t0) / h.life
            guard ee <= 1 else { continue }
            let a = ee > 0.7 ? (1 - ee) / 0.3 : 1
            let x = HouseLight.round(h.x - 3 + sin(ee * 6 + h.seed) * 3 * Double(S)), y = HouseLight.round(h.y - 3 - ee * (h.small ? 14 : 34) * Double(S))
            let (tex, size) = eggStamp("heart\(h.col)", Self.heartRows, ["r": litC(h.col), "w": emiC("#ffffff")], line: litC("#2a1f2e"))
            eggShow("heart\(i)", tex, size, x: x - 1, y: y - 1, alpha: a, layer: root, z: z + 0.03)
        }
        if t < e.purrUntil, let cat = behaviour?.sprites.first(where: { $0.kind == "cat" }), Int(floor(t / 140)) % 2 != 0, let p = e.position(cat) {
            let c = litC("#f8e4c8"), x = HouseLight.round(p[0]), y = HouseLight.round(p[1])
            over.add(c, x + 7, y - 5, 2, 1); over.add(c, x + 8, y - 3, 2, 1)
        }
    }

    private func eggStars(_ e: HouseEggs, _ t: Double, over: HouseRects, z: CGFloat) {
        for (i, s) in e.highFives.enumerated() {
            let ee = (t - s.t0) / 1500
            guard ee <= 1, let a = e.position(s.a), let b = e.position(s.b) else { continue }
            let x = (a[0] + b[0]) / 2, y = min(a[1], b[1]) - (s.a.small && s.b.small ? 14 : 22) * Double(S) - ee * 5 * Double(S)
            let k = ee > 0.12 && ee < 0.7 ? 2 : 1, al = ee > 0.75 ? (1 - ee) / 0.25 : 1
            let (tex, size) = eggStamp("star\(k)", Self.star5Rows, ["y": emiC("#ffe050")], k: k, line: litC("#2a1f2e"))
            eggShow("star\(i)", tex, size, x: HouseLight.round(x - 2.5 * Double(k)) - 1, y: HouseLight.round(y - 2.5 * Double(k)) - 1, alpha: al, layer: root, z: z + 0.04)
            for q in 0..<4 {
                let ang = Double(q) * Double.pi / 2 + Double.pi / 4, rr = (6 + ee * 10) * Double(S)
                over.add(emiC("#fff4b0"), HouseLight.round(x + cos(ang) * rr), HouseLight.round(y + sin(ang) * rr), S, S, alpha: al)
            }
        }
    }

    private func eggUFO(_ e: HouseEggs, _ t: Double, add: HouseRects, z: CGFloat) {
        guard let u = e.ufo, let at = u.at else { return }
        let S = Double(self.S)
        if u.beam > 0 {
            let top: [[Double]] = [[u.x - 5 * S, u.y + 6 * S], [u.x + 5 * S, u.y + 6 * S]], bot: [[Double]] = [[at[0] + 13 * S, at[1] + S], [at[0] - 13 * S, at[1] + S]]
            let sp = Self.eggSpans(top + bot)
            for (i, r) in sp.rows.enumerated() { if let r, r.1 > r.0 { add.add([150, 255, 190], r.0, sp.y0 + i, r.1 - r.0, 1, alpha: 0.2 * u.beam, blend: .add) } }
            for i in 0..<4 {
                let k = ((t / 900) + Double(i) / 4).truncatingRemainder(dividingBy: 1), y = u.y + 6 * S + k * (at[1] - u.y - 6 * S), hw = 5 * S + k * 8 * S
                add.add([200, 255, 220], HouseLight.round(u.x - hw), HouseLight.round(y), HouseLight.round(hw * 2), 1, alpha: 0.35 * u.beam * (1 - k), blend: .add)
            }
            eggGlow("ufoGlow", at[0], at[1], 18 * S, "#a0ffc0", 0.35 * u.beam, layer: root, z: z + 0.45)
        }
        let blink = Int(floor(t / 180)) % 3
        let pal: [Character: [Int]] = ["c": litC("#9ae8d0"), "w": emiC("#ffffff"), "m": litC("#9aa2b8"), "M": litC("#d0d6e4"), "d": litC("#5a6278"),
                                       "l": emiC(["#ff5a5a", "#ffd040", "#5ae0ff"][blink])]
        let (tex, size) = eggStamp("ufo\(blink)", Self.ufoRows, pal, k: self.S, line: litC("#2a1f2e"))
        eggShow("ufo", tex, size, x: HouseLight.round(u.x - 10 * S) - 1, y: HouseLight.round(u.y - 3 * S) - 1, layer: root, z: z + 0.05)
    }

    private func eggGhost(_ e: HouseEggs, _ t: Double, z: CGFloat) {
        guard let gh = e.ghost else { return }
        let ee = (t - gh.t0) / 26000, S = Double(self.S), W = Double(canvasW), H = Double(canvasH)
        guard ee <= 1 else { return }
        let span = W + 60 * S, x = gh.dir > 0 ? -30 * S + ee * span : W + 30 * S - ee * span, y = H * 0.42 + sin(t / 800) * 6 * S
        eggGlow("ghostGlow", x, y - 2 * S, 22 * S, "#b0c8ff", 0.18, layer: root, z: z + 0.45)
        let hem = Int(floor(t / 300)) % 2, flip = gh.dir < 0
        let (tex, size) = eggStamp("ghost\(hem)\(flip)", Self.ghostRows + [Self.ghostHem[hem]], ["w": emiC("#e4ecff"), "E": [26, 20, 36], "o": [26, 20, 36]], flip: flip, k: self.S)
        eggShow("ghost", tex, size, x: HouseLight.round(x - 6 * S), y: HouseLight.round(y - 9 * S), alpha: 0.5 + 0.12 * sin(t / 300), layer: root, z: z + 0.06)
    }

    private func eggLetter(_ e: HouseEggs, _ t: Double, z: CGFloat) {
        guard let l = e.letter, let mb = e.mailbox(), mb.room == l.room else { setEggCard(nil, x: 0, y: 0); return }
        let el = t - l.t0, S = Double(self.S)
        guard el <= 6500 else { setEggCard(nil, x: 0, y: 0); return }
        let cx = (mb.rect[0] + mb.rect[2]) / 2, rise = min(1, el / 450), ly = mb.rect[1] - 3 - rise * 9 * S + sin(el / 300) * S
        let (tex, size) = eggStamp("letter", Self.letterRows, ["e": litC("#f8f4e8"), "d": litC("#c0b0a0"), "r": litC("#e04040")], line: litC("#2a1f2e"))
        eggShow("letter", tex, size, x: HouseLight.round(cx - 4) - 1, y: HouseLight.round(ly) - 1, layer: root, z: z + 0.07)
        if el > 350 { setEggCard(l.tip, x: cx, y: ly) } else { setEggCard(nil, x: 0, y: 0) }
    }
}
