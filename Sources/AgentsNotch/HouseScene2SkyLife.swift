import AppKit
import NotchCore
import SpriteKit

/// The page's drawSkyLife: flocks of birds, a plane with its trail, a hot-air balloon. The schedule and the positions are
/// NotchCore.HouseSkyLife (the same random numbers as the page); this draws them from the page's pixel rows with the page's palette,
/// lit by the hour, as small cached textures on pooled nodes (the pool is made once, so a steady house makes no nodes). The layer sits above the
/// clouds and below the house, like the page's call after drawBackground. It does not keep the house awake: the page's sky life only
/// moves on frames drawn for other reasons either.
final class HouseSkyLifeLayer: SKNode {
    static let S = 2
    static let bird: [[String]] = [["#.....#", ".#...#.", "..#.#..", "...#..."], ["...#...", ".##.##.", "#.....#"]]
    static let plane = ["tt...........", "ttbbbbbbbbbb.", ".bwbwbwbwbwbn", "..bbbbbbbbbb.", "......ww....."]
    static let balloon: [String] = {
        var rows: [String] = []
        for r in 0..<12 {
            let k = (Double(r) - 5.5) / 6.2
            let half = r < 10 ? Int(floor(sqrt(max(0, 1 - k * k)) * 6.5 + 0.5)) : 2 - (r - 10)
            var s = ""
            for c in 0..<13 { s += abs(c - 6) <= half ? ((c + 1) / 2 % 2 != 0 ? "a" : "b") : "." }
            rows.append(s)
        }
        return rows + ["....l...l....", ".....l.l.....", "....kkkkk....", "....kkkkk...."]
    }()

    private var birdNodes: [SKSpriteNode] = [], planeNode: SKSpriteNode?, balloonNode: SKSpriteNode?
    private var cache: [String: SKTexture] = [:]
    private var cacheAmb = ""

    private func node() -> SKSpriteNode {
        let n = SKSpriteNode(); n.anchorPoint = CGPoint(x: 0, y: 1); n.isHidden = true; addChild(n); HouseRects.created += 1; return n
    }

    /// Everything the layer will ever show, made once (3 flocks of at most 5, one plane, one balloon).
    private func prepare() {
        guard planeNode == nil else { return }
        birdNodes = (0..<15).map { _ in node() }
        planeNode = node(); balloonNode = node()
    }

    private func texture(_ key: String, _ w: Int, _ h: Int, _ paint: (HousePixels) -> Void) -> SKTexture {
        if let t = cache[key] { return t }
        let p = HousePixels(w, h)
        paint(p)
        let t = SKTexture(cgImage: p.image()); t.filteringMode = .nearest
        if cache.count > 64 { cache.removeAll() }
        cache[key] = t
        return t
    }

    /// pxStamp(x0, y0, rows, pal, flip, k, noLine) onto a texture whose origin is (ox, oy).
    private func stamp(_ p: HousePixels, _ x0: Int, _ y0: Int, _ rows: [String], _ pal: [Character: [Int]], flip: Bool, k: Int, line: [Int]?) {
        let w = rows[0].count
        func X(_ c: Int) -> Int { x0 + (flip ? w - 1 - c : c) * k }
        let cells = rows.map { Array($0) }
        if let line {
            for (r, row) in cells.enumerated() { for c in 0..<w where row[c] != "." { p.fill(line, X(c) - 1, y0 + r * k - 1, k + 2, k + 2) } }
        }
        for (r, row) in cells.enumerated() { for c in 0..<w { if row[c] != ".", let col = pal[row[c]] { p.fill(col, X(c), y0 + r * k, k, k) } } }
    }

    func update(_ sky: HouseSkyLife, t: Double, ambKey: String, lit: (String) -> [Int]) {
        prepare() // the pool exists from the first frame: a flock arriving later makes no nodes
        guard sky.active || birdNodes.contains(where: { !$0.isHidden }) || planeNode?.isHidden == false || balloonNode?.isHidden == false else { return }
        if ambKey != cacheAmb { cache.removeAll(); cacheAmb = ambKey }
        let S = Self.S, Sd = Double(S)
        let ink = lit("#3a3448"), out = lit("#2a1f2e")
        // birds
        var used = 0
        for f in sky.birds {
            for i in 0..<f.n where used < birdNodes.count {
                let rank = Double((i + 1) / 2), side = i % 2 != 0 ? 1.0 : -1.0
                let bx = f.x - f.dir * rank * 7 * Sd, by = f.y + side * rank * 4 * Sd + sin(t / 700 + Double(i) + f.seed) * Sd
                let frame = Int(floor((t + f.seed + Double(i) * 97) / 160)) % 2
                let rows = Self.bird[frame]
                let tex = texture("b\(frame)", 7, rows.count) { p in self.stamp(p, 0, 0, rows, ["#": ink], flip: false, k: 1, line: nil) }
                let n = birdNodes[used]; used += 1
                if n.texture !== tex { n.texture = tex; n.size = CGSize(width: 7, height: rows.count) }
                n.position = CGPoint(x: Double(HouseLight.round(bx - 3)), y: -Double(HouseLight.round(by - 2)))
                n.isHidden = false
            }
        }
        for i in used..<birdNodes.count where !birdNodes[i].isHidden { birdNodes[i].isHidden = true }
        // the plane: the contrail (daylight only), the body, the night lights
        if let pl = sky.plane, let n = planeNode {
            let rx = HouseLight.round(pl.x), ry = HouseLight.round(pl.y), dir = Int(pl.dir)
            let trail = sky.dark < 0.5, blink = sky.dark >= 0.3 && Int(floor(t / 500)) % 2 != 0
            let key = "p\(dir)\(trail)\(blink)"
            let lx = rx - 140, ly = ry - 6 // the texture's origin; it is 280 x 14
            let tex = texture(key, 280, 14) { p in
                if trail { for i in 0..<40 { p.fill([255, 255, 255], 140 - dir * (8 + i * 3), 6 + 1, 3, 1, alpha: 0.5 * (1 - Double(i) / 40)) } }
                self.stamp(p, 140 - 6, 6 - 2, Self.plane, ["t": lit("#c84a4a"), "b": lit("#e8ecf2"), "w": lit("#5a7aa8"), "n": lit("#c0c8d4")], flip: dir < 0, k: 1, line: out)
                if blink {
                    p.fill([255, 64, 64], 140 - dir * 6, 6 - 2, 1, 1)
                    p.fill([255, 255, 255], 140 + dir * 1, 6 + 2, 1, 1)
                }
            }
            if n.texture !== tex { n.texture = tex; n.size = CGSize(width: 280, height: 14) }
            n.position = CGPoint(x: Double(lx), y: -Double(ly)); n.isHidden = false
        } else { planeNode?.isHidden = true }
        // the balloon
        if let b = sky.balloon, let n = balloonNode {
            let x0 = HouseLight.round(b.x - 6 * Sd), y0 = HouseLight.round(b.y + sin(t / 1500 + b.seed) * 2 * Sd)
            let rows = Self.balloon, w = rows[0].count * S + 2, h = rows.count * S + 2
            let tex = texture("balloon", w, h) { p in
                self.stamp(p, 1, 1, rows, ["a": lit("#e85a5a"), "b": lit("#f4d050"), "l": lit("#6a5040"), "k": lit("#a0703a")], flip: false, k: S, line: out)
            }
            if n.texture !== tex { n.texture = tex; n.size = CGSize(width: w, height: h) }
            n.position = CGPoint(x: Double(x0 - 1), y: -Double(y0 - 1)); n.isHidden = false
        } else { balloonNode?.isHidden = true }
    }
}

extension HouseScene2 {
    /// Installs the page's sky life on the behaviour (the schedule and its random numbers) and lets the sim know the hour.
    func installSkyLife(_ b: HouseBehaviour) { b.enableSkyLife(); feedLife(hour: hour, dark: light.dark, exact: false) }

    /// The page's hour for the residents (getHours + minutes) and DARK for the pets and the night lamps, taken from the scene's own clock.
    func feedLife(hour: Double, dark: Double, exact: Bool) {
        guard let b = behaviour else { return }
        b.life.hour = exact ? hour : floor(hour * 60 + 1e-6) / 60
        b.life.dark = dark
    }

    func updateSkyLife(t: Double) {
        guard let sky = behaviour?.skyLife else { return }
        if skyLifeLayer.parent !== root { skyLifeLayer.removeFromParent(); skyLifeLayer.zPosition = -46_500; root.addChild(skyLifeLayer) }
        let k = "\(Int(light.amb[0] * 255)),\(Int(light.amb[1] * 255)),\(Int(light.amb[2] * 255))"
        skyLifeLayer.update(sky, t: t, ambKey: k, lit: { self.litC($0) })
    }
}
