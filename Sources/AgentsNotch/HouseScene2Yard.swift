import AppKit
import NotchCore
import SpriteKit

/// The page's drawing primitives (spans / poly / polyOutline / line / B / FX) on top of the rect pool, in the canvas pixels of one room's
/// frame: enough to redraw the few animated things of the yard that the atlas only holds at rest (the swing with someone on it, the
/// mailbox flag up).
struct HouseRoomCanvas {
    let rects: HouseRects, scene: HouseScene2, ox: Double, oy: Double
    func iso(_ x: Double, _ y: Double, _ z: Double) -> [Double] { [ox + (x - y) * 16, oy + (x + y) * 8 - z * 2] }
    func lit(_ hex: String, _ k: Double = 1) -> [Int] { scene.litC(hex, k) }

    func spans(_ pts: [[Double]]) -> (y0: Int, out: [(Int, Int)?]) {
        let P = pts.map { [HouseLight.round($0[0]), HouseLight.round($0[1])] }, n = P.count
        var y0 = Int.max, y1 = Int.min
        for p in P { y0 = min(y0, p[1]); y1 = max(y1, p[1]) }
        var out: [(Int, Int)?] = []
        if y0 >= y1 { return (y0, out) }
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
    func poly(_ pts: [[Double]], _ c: [Int]) {
        let s = spans(pts)
        for (i, o) in s.out.enumerated() { if let o, o.1 > o.0 { rects.add(c, o.0, s.y0 + i, o.1 - o.0, 1) } }
    }
    func polyOutline(_ pts: [[Double]], _ c: [Int]) {
        let s = spans(pts)
        for i in -1...s.out.count {
            var l = Int.max, r = Int.min
            for k in (i - 1)...(i + 1) where k >= 0 && k < s.out.count { if let o = s.out[k] { l = min(l, o.0); r = max(r, o.1) } }
            if l < r { rects.add(c, l - 1, s.y0 + i, r - l + 2, 1) }
        }
    }
    func line(_ a: [Double], _ b: [Double], _ c: [Int]) {
        let x0 = HouseLight.round(a[0]), y0 = HouseLight.round(a[1]), x1 = HouseLight.round(b[0]), y1 = HouseLight.round(b[1])
        if x0 == x1 && y0 == y1 { rects.add(c, x0, y0, 1, 1); return }
        if x0 == x1 || y0 == y1 { rects.add(c, min(x0, x1), min(y0, y1), abs(x1 - x0) + 1, abs(y1 - y0) + 1); return }
        let n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in 0...n { rects.add(c, HouseLight.round(Double(x0) + Double(x1 - x0) * Double(i) / Double(n)), HouseLight.round(Double(y0) + Double(y1 - y0) * Double(i) / Double(n)), 1, 1) }
    }
    /// B(): a box with a 1px dark outline and a light top edge.
    func box(_ x: Double, _ y: Double, _ z: Double, _ w: Double, _ d: Double, _ h: Double, _ c: String, noLine: Bool = false) {
        if !noLine { polyOutline([iso(x, y, z + h), iso(x + w, y, z + h), iso(x + w, y, z), iso(x + w, y + d, z), iso(x, y + d, z), iso(x, y + d, z + h)], lit("#2a1f2e")) }
        poly([iso(x + w, y, z), iso(x + w, y + d, z), iso(x + w, y + d, z + h), iso(x + w, y, z + h)], lit(c, 0.72))
        poly([iso(x, y + d, z), iso(x + w, y + d, z), iso(x + w, y + d, z + h), iso(x, y + d, z + h)], lit(c, 0.86))
        poly([iso(x, y, z + h), iso(x + w, y, z + h), iso(x + w, y + d, z + h), iso(x, y + d, z + h)], lit(c, 1))
        if !noLine && w > 0.25 && d > 0.25 {
            let hl = lit(c, 1.16)
            line(iso(x, y + d, z + h), iso(x + w, y + d, z + h), hl); line(iso(x + w, y, z + h), iso(x + w, y + d, z + h), hl)
        }
    }
    func fy(_ x0: Double, _ x1: Double, _ y: Double, _ z0: Double, _ z1: Double, _ c: [Int]) {
        poly([iso(x0, y, z0), iso(x1, y, z0), iso(x1, y, z1), iso(x0, y, z1)], c)
    }
    func fx(_ y0: Double, _ y1: Double, _ x: Double, _ z0: Double, _ z1: Double, _ c: String) {
        poly([iso(x, y0, z0), iso(x, y1, z0), iso(x, y1, z1), iso(x, y0, z1)], lit(c))
    }
}

extension HouseScene2 {
    /// The yard's swing with a Clawd on it, and the mailbox flag while it is up: redrawn here, the atlas layers hidden meanwhile.
    func updateYardDyn(_ b: HouseBehaviour, sim: HouseSim, simT: Double) {
        let layer = yardRects ?? { let r = HouseRects(); root.addChild(r); yardRects = r; return r }()
        if layer.parent !== root { layer.removeFromParent(); root.addChild(layer) }
        let up = simT - b.life.mailFlag < 15000
        let G = -parts.SLAB
        // each part redraws only when what it shows changes: the swing with its rider, the flag, the lit monitors
        func changed(_ k: String, _ sig: String) -> Bool { if yardSig[k] == sig { return false }; yardSig[k] = sig; return true }
        for (key, node) in dynNodes {
            switch key.name {
            case "swing":
                let sw = b.life.swinger.flatMap { id in sim.sprites.first { $0.id == id } }
                node.node.isHidden = sw != nil
                guard changed("swing", sw.map { "\($0.id) \($0.y) \($0.z)" } ?? "") else { continue }
                layer.begin(); defer { layer.end() }
                guard let sw, let r = roomFrame("__bath") else { continue }
                layer.zPosition = node.z
                let cv = HouseRoomCanvas(rects: layer, scene: self, ox: r.ox, oy: r.oy), dy = sw.y - 7.05, dz = sw.z - 4.5
                for x in [9.9, 11.5] { for y0 in [6.7, 7.4] {
                    cv.line(cv.iso(x, y0, G), cv.iso(x, 7.05, G + 22), cv.lit("#6a4228")); cv.line(cv.iso(x + 0.06, y0, G), cv.iso(x + 0.06, 7.05, G + 22), cv.lit("#8a5a36"))
                } }
                cv.box(9.82, 7.0, G + 22, 1.76, 0.1, 0.8, "#8a5a36")
                for x in [10.45, 10.95] { cv.line(cv.iso(x, 7.05, G + 22), cv.iso(x, 7.05 + dy, G + 4.6 + dz), cv.lit("#d8c8a0")) }
                cv.box(10.35, 6.92 + dy, G + 4 + dz, 0.7, 0.26, 0.5, "#c04848")
            case "flag", "flagK":
                node.node.isHidden = up
                guard changed(key.name, "\(up)") else { continue }
                guard up, let r = roomFrame(key.name == "flag" ? "__bath" : "__kitchen") else { let p = flagRects(key.name); p.begin(); p.end(); continue }
                let cv = HouseRoomCanvas(rects: flagRects(key.name), scene: self, ox: r.ox, oy: r.oy)
                cv.rects.zPosition = node.z
                cv.rects.begin()
                if key.name == "flag" { cv.box(4.36, 7.5, G + 12.5, 0.06, 0.06, 6, "#6a6a74", noLine: true); cv.fx(7.53, 7.8, 4.4, G + 16.5, G + 18.5, "#e04040") }
                else { cv.box(9.86, 2.75, 12.5, 0.06, 0.06, 6, "#6a6a74", noLine: true); cv.fx(2.78, 3.05, 9.9, 16.5, 18.5, "#e04040") }
                cv.rects.end()
            case "screen":
                guard let r = roomFrame(key.room), let room = layout.rooms.first(where: { $0.key == key.room }) else { continue }
                let work = sim.sprites.filter { $0.kind == "agent" && $0.goal?.room == key.room && $0.goal?.cat == "work" && $0.path.isEmpty && $0.state == "working" }
                let on0 = work.contains { $0.goal?.i == 0 }, on1 = work.contains { $0.goal?.i == 1 }
                let pool = flagRects("screen:" + key.room)
                let shift = Int(floor((roomClockOverride ?? simT) / 700))
                guard changed("screen:" + key.room, "\(on0) \(on1) \((on0 || on1) ? shift : 0)") else { continue }
                pool.zPosition = node.z
                pool.begin(); defer { pool.end() }
                let cv = HouseRoomCanvas(rects: pool, scene: self, ox: r.ox, oy: r.oy)
                var list: [(Double, Double, Double, Double, Double, Bool, Bool)] = []   // x0 x1 y z0 z1 on game
                switch room.theme {
                case "bedroom": list = [(6.1, 7.3, 0.501, 17, 24, on0, false), (7.7, 8.9, 0.501, 17, 24, on1, false)]
                case "server": list = [6.75, 7.65, 8.55].enumerated().map { ($1 + 0.07, $1 + 0.78, 0.501, 16, 22, $0 == 0 ? on0 : $0 == 2 ? on1 : (on0 || on1), false) }
                case "library": list = [(8.15, 8.95, 2.201, 14.5, 18.5, on0, false)]
                case "greenhouse": list = [(7.25, 8.05, 0.451, 15.5, 19.5, on0 || on1, false)]
                case "arcade": list = [(7.7, 9.4, 0.501, 16, 23, on0 || on1, true)]
                default: break
                }
                for (x0, x1, y, z0, z1, on, game) in list where on {
                    cv.fy(x0, x1, y, z0, z1, emiC(game ? "#1a2440" : "#13202a"))
                    let a = cv.iso(x0 + 0.1, y, z1 - 1)
                    var i = 0
                    while Double(i) < (z1 - z0 - 1.5) * 2 {
                        let w = Double((((i + shift) * 37) % 7)) / 10 + 0.2
                        let c = emiC((i + shift) % 5 != 0 ? "#7fe0a0" : (game ? "#ff7ac8" : "#f0d070"))
                        let wd = max(2, HouseLight.round(w * (x1 - x0 - 0.2) * 16))
                        pool.add(c, HouseLight.round(a[0] + Double((i * 5) % 3 * 2)), HouseLight.round(a[1] + Double(i) - x0.truncatingRemainder(dividingBy: 1)), wd, 1)
                        i += 3
                    }
                }
            default: break
            }
        }
    }

    func flagRects(_ k: String) -> HouseRects {
        if let r = flagPools[k], r.parent === root { return r }
        let r = HouseRects(); root.addChild(r); flagPools[k] = r; return r
    }
}
