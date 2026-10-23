import AppKit
import NotchCore
import SpriteKit

/// The page's drawSeason: snow on the wall tops and the roof edge, the grass strips in front of the ground floor (snow in winter, flowers
/// in spring), and the leaves or petals drifting down around each island in autumn and spring. The still part is drawn once per light;
/// only the drifting part is redrawn each frame.
extension HouseScene2 {
    /// seasonNow() by the calendar; `month0` counts from January = 0.
    static func seasonOf(month0 m: Int) -> String { m >= 8 && m <= 10 ? "autumn" : (m == 11 || m <= 1) ? "winter" : m <= 4 ? "spring" : "summer" }

    func setSeason(_ s: String) {
        guard s != season else { return }
        season = s; seasonSig = ""
        if painted { repaint(sync: false) }
    }

    func updateSeason(t: Double) {
        let S = 2.0, WH = 60.0, slab = parts.SLAB
        let root = self.movers
        let still = seasonStill ?? { let r = rectPool(); root.addChild(r); seasonStill = r; return r }()
        let drift = seasonDrift ?? { let r = rectPool(); root.addChild(r); seasonDrift = r; return r }()
        if still.parent !== root { still.removeFromParent(); root.addChild(still) }
        if drift.parent !== root { drift.removeFromParent(); root.addChild(drift) }
        still.zPosition = topZ + 3; drift.zPosition = topZ + 3.2
        let se = season, winter = se == "winter" && weather != "snow"
        let hasYard = layout.yard.on
        func canvas(_ r: HouseLayout.Room, _ rects: HouseRects) -> HouseRoomCanvas { HouseRoomCanvas(rects: rects, scene: self, ox: r.ox, oy: r.oy) }
        let sig = "\(se)|\(weather)|\(light.amb)|\(layout.rooms.count)|\(hasYard)"
        if sig != seasonSig {
            seasonSig = sig
            still.begin()
            if winter {
                let white = litC("#f4f8ff")
                for r in layout.rooms where r.theme != "roof" && !layout.rooms.contains(where: { $0.tower == r.tower && $0.floor == r.floor + 1 }) {
                    let cv = canvas(r, still)
                    cv.poly([cv.iso(0, 0, WH), cv.iso(0, r.NY, WH), cv.iso(-0.45, r.NY, WH), cv.iso(-0.45, -0.45, WH)], white)
                    cv.poly([cv.iso(0, 0, WH), cv.iso(r.NX, 0, WH), cv.iso(r.NX, -0.45, WH), cv.iso(-0.45, -0.45, WH)], white)
                }
                if let roof = layout.rooms.first(where: { $0.key == "__roof" }) {
                    let cv = canvas(roof, still)
                    for (a, b) in [([0.0, 8.0], [10.0, 8.0]), ([10.0, 0.0], [10.0, 8.0])] {
                        let p = cv.iso(a[0], a[1], 11.5), q = cv.iso(b[0], b[1], 11.5)
                        cv.line(p, q, white); cv.line([p[0], p[1] - 1], [q[0], q[1] - 1], white)
                    }
                }
            }
            if se != "summer" {
                for r in layout.rooms where r.floor == 0 {
                    let yd = r.key == "__bath" && hasYard
                    guard (winter || se == "spring") && !yd else { continue }
                    let cv = canvas(r, still), NX = r.NX, NY = r.NY, seed = Double(r.seed)
                    for i in 0..<44 {
                        let front = i % 2 == 1, u = Self.scRnd(Double(i), seed), v = Self.scRnd(Double(i), seed + 7)
                        let p = front ? cv.iso(-1.2 + u * (NX + 2.4), NY + 0.1 + v * 1.05, -slab) : cv.iso(NX + 0.1 + v * 1.05, -1.2 + u * (NY + 2.4), -slab)
                        let x = HouseLight.round(p[0]), y = HouseLight.round(p[1])
                        if winter {
                            let w = 3 + (i % 3) * 2
                            still.add(litC("#f4f8ff"), x - 2, y, w, 2); still.add(litC("#d8e2f0"), x - 2, y + 2, w, 1)
                        } else if i % 3 != 0 {
                            still.add(litC(i % 4 != 0 ? "#f8a8c8" : "#ffffff"), x, y, 2, 2); still.add(litC("#f0d040"), x, y, 1, 1)
                        }
                    }
                    if winter {
                        let w = litC("#f4f8ff")
                        cv.line(cv.iso(-1.2, NY + 1.2, -slab), cv.iso(NX + 1.2, NY + 1.2, -slab), w)
                        cv.line(cv.iso(NX + 1.2, -1.2, -slab), cv.iso(NX + 1.2, NY + 1.2, -slab), w)
                    }
                }
            }
            still.end()
        }
        drift.begin()
        if se == "autumn" || se == "spring" {
            let cols = se == "autumn" ? ["#e8803a", "#d0502a", "#f0b040", "#b86a30"] : ["#f8b0c8", "#fff0f4", "#f490b0"]
            let n = se == "autumn" ? 9 : 6
            for r in layout.rooms where r.floor == 0 {
                let cv = canvas(r, drift), seed = Double(r.seed)
                let top = cv.iso(r.NX / 2, r.NY / 2, WH)[1] - 30 * S, bot = cv.iso(r.NX + 1.2, r.NY + 1.2, -slab)[1] + 50 * S
                let L = cv.iso(0, r.NY + 1.2, 0)[0] - 14 * S, Rr = cv.iso(r.NX + 1.2, 0, 0)[0] + 14 * S
                for i in 0..<n {
                    let k = (t / (9000 + Double((i * 1373) % 5000)) + Self.scRnd(Double(i), seed + 3)).truncatingRemainder(dividingBy: 1)
                    let x = L + Self.scRnd(Double(i), seed + 5) * (Rr - L) + sin(t / 900 + Double(i) * 2) * 8 * S, y = top + k * (bot - top)
                    let a = k < 0.1 ? k * 10 : k > 0.85 ? (1 - k) / 0.15 : 1, c = litC(cols[i % cols.count])
                    let xr = HouseLight.round(x), yr = HouseLight.round(y)
                    if Int(floor(t / 260 + Double(i))) % 2 != 0 { drift.add(c, xr, yr, 2, 1, alpha: a); drift.add(c, xr + 1, yr + 1, 1, 1, alpha: a) }
                    else { drift.add(c, xr, yr, 1, 2, alpha: a); drift.add(c, xr + 1, yr, 1, 1, alpha: a) }
                }
            }
        }
        drift.end()
    }
}
