import AppKit
import NotchCore
import SpriteKit

/// What the page knows about its window that the sky depends on: the city is planned from the canvas, the window's
/// CSS height and the Dock's inset, so it is drawn here from those numbers for any screen (no 2304x1490 cut).
struct HouseSkyEnv {
    var innerHeight: Double
    var insetBottom: Double
}

/// The city backdrop's plan: a port of cityPlan() (room/index.html), the same seeded draws in the same order.
final class HouseCityPlan {
    struct Win { var x, y, w, h: Int; var on, off, mOn, mOff: Double; var fl: Int; var col: [Int]; var frame = false }
    struct Far { var x, w, h, top, s: Int }
    struct Mid {
        var x, w, h, pal: Int; var glass: Bool; var roof: String
        var wins: [Win] = []
        var board: Int?
        var boardAt: (Int, Int, Int)?
        var neon: Neon?
        var mast = 0, mastX = 0, towerX = 0
    }
    struct Neon { var txt: String; var col: [Int]; var x, y, w, h: Int }
    struct Near { var x, w, h: Int; var shop: Bool; var col: Int; var roofC: Int; var pitch, chim: Bool; var wins: [Win]; var awn: Int }
    struct Tree { var x, h: Int; var s: Double }
    struct Ant { var x, y: Int; var ph: Double }

    static let midPal = [["#b4765e", "#8e5a48", "#d8a088"], ["#8e94ac", "#6e7490", "#b4bad0"], ["#c9b08a", "#a48c6a", "#e6d2b0"],
                         ["#7c8c98", "#5e6c78", "#a4b4c0"], ["#d2c6b4", "#aca08e", "#ece4d6"], ["#9a6a7a", "#7a4e5e", "#c094a2"]]
    static let nearPal = ["#e8c4a0", "#c8705a", "#7aa0c0", "#a8c890", "#f0dca0", "#d8a0b0", "#b0a8c8"]
    static let roofPal = ["#7a4a40", "#4a5a7a", "#5a6a4a", "#8a5a3a", "#5a4a5a"]
    static let neonList: [(String, String)] = [("КИНО", "#ff5a8a"), ("БАР", "#5ae0ff"), ("КАФЕ", "#ffd040"), ("24/7", "#a0ff70"), ("JAZZ", "#c080ff"), ("ОТЕЛЬ", "#ff8040"), ("PIZZA", "#ff5a5a")]
    static let boards: [(String, String, String)] = [("CLAWD", "#d97757", "#fff4e0"), ("CODEX", "#2a2f45", "#eef0f6"), ("ЧАЙ", "#58b070", "#ffffff"), ("NOTCH", "#4a80d8", "#ffffff")]
    static let winCols = ["#ffd47a", "#ffe2a0", "#ffc66a", "#ffdc90"]
    static let awnCols = ["#e05a4a", "#4a80d8", "#58b070", "#f0a030"]
    static let roofKinds = ["flat", "tower", "antenna", "garden", "step", "pitch", "board", "flat"]

    var aw = 0, sc = 1.0
    var far: [Far] = [], mid: [Mid] = [], near: [Near] = [], trees: [Tree] = [], lamps: [Int] = [], pillars: [Int] = [], ants: [Ant] = [], neon: [Neon] = []
    var farTop = 0, midTop = 0, nearTop = 0, deck = 0

    /// cityRnd: mulberry32.
    final class Rnd {
        var s: UInt32
        init(_ seed: Int) { s = UInt32(truncatingIfNeeded: seed) }
        func next() -> Double {
            s = s &+ 0x6D2B79F5
            var x = (s ^ (s >> 15)) &* (1 | s)
            x = (x &+ ((x ^ (x >> 7)) &* (61 | x))) ^ x
            return Double((x ^ (x >> 14))) / 4294967296
        }
    }

    init(width W: Int, ground: Int, innerHeight: Double, base: Double, dpr: Double, fontWidth: (String) -> Int) {
        let S = 2, BD_M = 8 * S
        let r = Rnd(2026)
        func R() -> Double { r.next() }
        func I(_ v: Double) -> Int { Int(v) } // `| 0` of a non-negative value
        aw = Int((Double(W + 2 * BD_M) / Double(S)).rounded(.up))
        let Hb = innerHeight * dpr / (base == 0 ? 3 : base) / Double(S)
        sc = min(max(Hb / 300, 0.75), 1.5)
        let round = HouseLight.round
        var x = -2
        while x < aw + 2 {
            let w = 8 + I(R() * 16)
            let h = HouseLight.round((26 + R() * 52) * sc), top = I(R() * 6), s = I(R() * 1e9)
            far.append(Far(x: x, w: w, h: h, top: top, s: s))
            x += w + (R() < 0.5 ? 0 : 1 + I(R() * 3))
        }
        var ni = 0, bi = 0
        x = -3
        while x < aw + 3 {
            let w = 12 + I(R() * 17), h = round((20 + R() * 34) * sc)
            let pal = I(R() * 6), glass = R() < 0.14, roof = Self.roofKinds[I(R() * 8)]
            var b = Mid(x: x, w: w, h: h, pal: pal, glass: glass, roof: roof)
            if b.roof == "board" && w < 18 { b.roof = "antenna" }
            if b.roof == "board" { b.board = bi % Self.boards.count; bi += 1 }
            mid.append(b)
            x += w + (R() < 0.35 ? 0 : 1 + I(R() * 3))
        }
        func winSched(_ shop: Bool) -> (on: Double, off: Double, mOn: Double, mOff: Double, fl: Int, col: [Int]) {
            let k = R()
            var mOn = 99.0, mOff = 0.0
            let fl = R() < 0.05 ? 1 + I(R() * 40) : 0
            var col = R() < 0.07 ? "#a8d0ff" : Self.winCols[I(R() * 4)]
            var on = 0.0, off = 0.0
            if shop { on = 16.5 + R() * 2; off = 21 + R() * 2.5; col = "#ffe6b0" }
            else if k < 0.08 { on = 99; off = 0 }
            else if k < 0.14 { on = 17 + R() * 2; off = 30.5 }
            else {
                on = 16.8 + R() * 4.4; off = max(on + 0.8, 21.3 + R() * 5.2)
                if R() < 0.4 { mOn = 5.1 + R() * 1.5; mOff = mOn + 0.5 + R() * 1.4 }
            }
            return (on, off, mOn, mOff, shop ? 0 : fl, HouseLight.rgb(col))
        }
        func win(_ x: Int, _ y: Int, _ w: Int, _ h: Int, shop: Bool = false, frame: Bool = false) -> Win {
            let s = winSched(shop)
            return Win(x: x, y: y, w: w, h: h, on: s.on, off: s.off, mOn: s.mOn, mOff: s.mOff, fl: s.fl, col: s.col, frame: frame)
        }
        for i in mid.indices {
            var b = mid[i]
            let wx0 = b.x + 2, wx1 = b.x + b.w - 3, top = b.h - (b.roof == "step" ? 9 : 3)
            if b.glass {
                var y = 15
                while y + 2 < top { var xx = wx0; while xx + 2 <= wx1 + 1 { b.wins.append(win(xx, y, 2, 2)); xx += 3 }; y += 4 }
            } else {
                var y = 14
                while y + 3 < top { var xx = wx0; while xx + 2 <= wx1 + 1 { b.wins.append(win(xx, y, 2, 3)); xx += 4 }; y += 5 }
            }
            if !b.glass && ni < Self.neonList.count * 2 && R() < 0.4 {
                let (txt, col) = Self.neonList[(ni * 3 + I(R() * 2)) % Self.neonList.count], tw = fontWidth(txt)
                if tw + 4 <= b.w - 2 && b.h > 22 {
                    let n = Neon(txt: txt, col: HouseLight.rgb(col), x: b.x + round(Double(b.w - tw - 4) / 2), y: round(Double(b.h) * (0.45 + R() * 0.3)), w: tw + 4, h: 10)
                    b.neon = n; neon.append(n); ni += 1
                    b.wins = b.wins.filter { $0.y + $0.h < n.y - n.h - 1 || $0.y > n.y + 1 }
                }
            }
            if b.roof == "antenna" {
                b.mast = 7 + I(R() * 9); b.mastX = b.x + 3 + I(R() * Double(b.w - 6))
                ants.append(Ant(x: b.mastX, y: b.h + b.mast, ph: R() * 3))
            }
            if b.roof == "tower" { b.towerX = b.x + 2 + I(R() * Double(max(1, b.w - 10))) }
            mid[i] = b
        }
        x = -3
        while x < aw + 3 {
            if R() < 0.22 { trees.append(Tree(x: x + 4, h: 6 + I(R() * 4), s: R() * 9)); x += 9; continue }
            let w = 14 + I(R() * 11), shop = R() < 0.35, h = (shop ? 13 : 11) + I(R() * 8)
            let col = I(R() * 7), roofC = I(R() * 5), pitch = R() < 0.6, chim = R() < 0.5, awn = I(R() * 4)
            var d = Near(x: x, w: w, h: h, shop: shop, col: col, roofC: roofC, pitch: pitch, chim: chim, wins: [], awn: awn)
            var y = shop ? 9 : 4
            while y + 4 <= h - 2 {
                var wx = x + 2
                while wx + 3 <= x + w - 2 {
                    if !(y < 8 && abs(Double(wx) + 1.5 - (Double(x) + Double(w) / 2)) < 2.5) { d.wins.append(win(wx, y, 3, 4, frame: true)) }
                    wx += 5
                }
                y += 6
            }
            if shop { d.wins.append(win(x + 2, 1, max(4, w - 9), 4, shop: true)) }
            near.append(d)
            x += w + (R() < 0.5 ? 0 : 1)
        }
        x = 10 + I(R() * 20)
        while x < aw { lamps.append(x); x += 44 + I(R() * 16) }
        farTop = (far.map(\.h).max() ?? 0) + 8
        midTop = (mid.map { $0.h + $0.mast + ($0.roof == "tower" ? 14 : 12) }.max() ?? 0) + 2
        nearTop = max(near.map { $0.h + ($0.pitch ? Int((Double($0.w) / 2).rounded(.up)) + 3 : 4) }.max() ?? 0, trees.map { $0.h + 8 }.max() ?? 0) + 2
        deck = round(26 * min(1.2, sc))
        x = 6 + I(R() * 30)
        while x < aw { pillars.append(x); x += 46 }
        _ = ground
    }
}

extension HousePainter {
    static let outC = "#2a2438"

    var skyEnv: HouseSkyEnv { env ?? HouseSkyEnv(innerHeight: floor(Double(canvasH) * layout.view.PXD / layout.view.DPR), insetBottom: 0) }

    /// bdGround(H - insetBottom()), from the same numbers the painter has.
    var ground: Int { Self.groundOf(layout: layout, env: skyEnv) }
    static func groundOf(layout: HouseLayout, env: HouseSkyEnv?) -> Int { max(0, groundRaw(layout: layout, env: env)) }
    /// Negative on a canvas too short for the Dock's inset: the page would draw nothing sensible there, so the app uses the page.
    static func groundRaw(layout: HouseLayout, env: HouseSkyEnv?) -> Int {
        let H = Int(layout.view.height)
        let e = env ?? HouseSkyEnv(innerHeight: floor(Double(H) * layout.view.PXD / layout.view.DPR), insetBottom: 0)
        let ib = HouseLight.round(e.insetBottom * layout.view.DPR / layout.view.PXD)
        return (Int(floor(Double(H - ib) / 2)) - 14) * 2
    }

    // MARK: colours (lit / emi / haze of the page)

    private func css(_ v: [Double]) -> [Int] { v.map { Int(min(255, $0)) } }
    func lit(_ hex: String, _ k: Double = 1) -> [Int] {
        let c = HouseLight.rgb(hex); return css((0..<3).map { Double(c[$0]) * light.amb[$0] * k })
    }
    func haze(_ hex: String, _ a: Double, _ k: Double = 1) -> [Int] {
        let c = HouseLight.rgb(hex), s = light.skyBottom
        return css((0..<3).map { Double(c[$0]) * light.amb[$0] * k * (1 - a) + Double(s[$0]) * a })
    }
    func mixHex(_ a: String, _ b: String, _ t: Double) -> [Int] {
        let A = HouseLight.rgb(a), B = HouseLight.rgb(b)
        return (0..<3).map { HouseLight.round(Double(A[$0]) + Double(B[$0] - A[$0]) * t) }
    }
    func hexOf(_ c: [Int]) -> String { "#" + c.map { String(format: "%02x", $0) }.joined() }

    private func text(_ p: HousePixels, _ s: String, _ x: Int, _ y: Int, _ col: [Int], _ k: Int) {
        var cx = x
        for ch in s {
            let gl = glyph(ch)
            for (r, row) in gl.enumerated() { for (c, v) in row.enumerated() where v == "#" { p.fill(col, cx + c * k, y + r * k, k, k) } }
            cx += ((gl.first?.count ?? 0) + 1) * k
        }
    }
    func fontWidth(_ s: String) -> Int {
        var w = 0
        for (i, ch) in s.enumerated() { w += (glyph(ch).first?.count ?? 0) + (i > 0 ? 1 : 0) }
        return w
    }

    // MARK: city layers (paintFar / paintMid / paintRail / paintNear / paintRoad, autumn, clear)

    private func cF(_ p: HousePixels, _ c: [Int], _ x: Int, _ y: Int, _ w: Int, _ h: Int, alpha: Double = 1) { p.fill(c, x * 2, y * 2, w * 2, h * 2, alpha: alpha) }

    private func paintFar(_ C: HouseCityPlan, _ T: Int) -> HousePixels {
        let S = 2, p = HousePixels(C.aw * S, (T + 4) * S)
        let a = 0.58, body = haze("#7a84a8", a), rim = haze("#9aa4c4", a), dark = haze("#6a7298", a)
        let winA = max(0, light.dark - 0.3) * 1.3
        for b in C.far {
            let y = T - b.h
            cF(p, body, b.x, y, b.w, b.h + 4); cF(p, rim, b.x, y, b.w, 1); cF(p, dark, b.x + b.w - 2, y + 1, 2, b.h + 3)
            let mid = b.x + (b.w >> 1)
            switch b.top {
            case 1: cF(p, body, mid - 1, y - 6, 2, 6); cF(p, body, mid, y - 11, 1, 5)
            case 2: cF(p, body, b.x + 2, y - 4, b.w - 4, 4); cF(p, body, b.x + 4, y - 7, max(1, b.w - 8), 3)
            case 3: for i in 0..<4 { cF(p, body, mid - 3 + (i >> 1), y - 1 - i, 6 - (i >> 1) * 2 + 1, 1) }
            case 4: cF(p, body, b.x + 2, y - 8, 1, 8)
            default: break
            }
            if winA > 0 {
                let rr = HouseCityPlan.Rnd(b.s), wc = [255, 214, 140]
                var yy = y + 3
                while yy < T - 1 {
                    var xx = b.x + 1
                    while xx < b.x + b.w - 1 { if rr.next() < 0.22 { p.fill(wc, xx * S, yy * S, S, S, alpha: min(0.85, winA)) }; xx += 2 }
                    yy += 3
                }
            }
        }
        return p
    }

    private func paintMid(_ C: HouseCityPlan, _ T: Int, boardAt: inout [Int: (Int, Int, Int)]) -> HousePixels {
        let S = 2, p = HousePixels(C.aw * S, (T + 4) * S)
        let a = 0.22, out = haze(Self.outC, a), glass = haze("#4e5e80", a), glint = haze("#9cb4d4", a)
        let leaves = ["#d8702e", "#f0b040", "#b85a2a"].map { haze($0, a) }
        for (bi, b) in C.mid.enumerated() {
            let pal = HouseCityPlan.midPal[b.pal].map { haze($0, a) }, wall = pal[0], shade = pal[1], trim = pal[2], y = T - b.h, x = b.x
            cF(p, out, x - 1, y - 1, b.w + 2, b.h + 5); cF(p, wall, x, y, b.w, b.h + 4); cF(p, shade, x + b.w - 3, y, 3, b.h + 4)
            if b.glass {
                cF(p, glass, x + 1, y + 2, b.w - 4, b.h + 2)
                var yy = y + 4; while yy < T { cF(p, wall, x + 1, yy, b.w - 4, 1); yy += 4 }
                cF(p, glint, x + 2, y + 3, 1, min(10, b.h - 4))
            } else {
                for w in b.wins { cF(p, glass, w.x, T - w.y - w.h, w.w, w.h); cF(p, glint, w.x, T - w.y - w.h, 1, 1) }
            }
            cF(p, trim, x - 1, y, b.w + 2, 1)
            if b.roof == "step" {
                let sx = x + 3, sw = b.w - 6
                cF(p, out, sx - 1, y - 7, sw + 2, 7); cF(p, wall, sx, y - 6, sw, 6); cF(p, shade, sx + sw - 2, y - 6, 2, 6); cF(p, trim, sx - 1, y - 6, sw + 2, 1)
            }
            if b.roof == "tower" {
                let tx = b.towerX, wood = haze("#9a6a44", a), band = haze("#6e4a30", a), cone = haze("#5a4a48", a)
                cF(p, out, tx, y - 4, 1, 4); cF(p, out, tx + 5, y - 4, 1, 4); cF(p, out, tx, y - 2, 6, 1)
                cF(p, out, tx - 1, y - 11, 8, 8); cF(p, wood, tx, y - 10, 6, 6); cF(p, band, tx, y - 8, 6, 1); cF(p, band, tx, y - 6, 6, 1); cF(p, haze("#7a5236", a), tx + 4, y - 10, 2, 6)
                for i in 0..<4 { cF(p, cone, tx + 3 - i - (i == 3 ? 1 : 0), y - 14 + i, 2 + i * 2 + (i == 3 ? 2 : 0), 1) }
            }
            if b.roof == "antenna" { cF(p, out, b.mastX, y - b.mast, 1, b.mast); cF(p, out, b.mastX - 2, y - b.mast + 3, 5, 1); cF(p, out, b.mastX - 1, y - b.mast + 6, 3, 1) }
            if b.roof == "garden" {
                let box = haze("#7a5a3a", a)
                cF(p, out, x + 1, y - 2, b.w - 2, 2); cF(p, box, x + 2, y - 2, b.w - 4, 1)
                var bx = x + 2
                while bx + 3 <= x + b.w - 2 { cF(p, leaves[2], bx, y - 4, 3, 2); cF(p, leaves[0], bx, y - 5, 3, 2); cF(p, leaves[1], bx + 1, y - 5, 1, 1); bx += 4 }
            }
            if b.roof == "flat" && b.w > 14 {
                let hut = haze("#8a8a94", a)
                cF(p, out, x + b.w - 8, y - 5, 5, 5); cF(p, hut, x + b.w - 7, y - 4, 3, 4)
                cF(p, out, x + 2, y - 2, 4, 2); cF(p, haze("#b0b4bc", a), x + 3, y - 2, 2, 1)
            }
            if b.roof == "pitch" {
                let rc = haze("#5a5068", a)
                var i = 0
                while i < 6 && b.w - 2 - i * 4 > 1 { cF(p, out, x - 1 + i * 2, y - 1 - i, b.w + 2 - i * 4, 1); cF(p, rc, x + i * 2, y - 1 - i, b.w - i * 4, 1); i += 1 }
            }
            if let bd = b.board {
                let (txt, bg, fg) = HouseCityPlan.boards[bd], tw = fontWidth(txt), bw = tw + 6, bx = x + HouseLight.round(Double(b.w - bw) / 2), by = y - 13
                cF(p, out, bx + 2, by + 9, 1, 4); cF(p, out, bx + bw - 3, by + 9, 1, 4); cF(p, out, bx - 1, by - 1, bw + 2, 11); cF(p, haze(bg, a), bx, by, bw, 9)
                text(p, txt, (bx + 3) * S, (by + 2) * S, haze(fg, a), S)
                boardAt[bi] = (bx, by, bw)
            }
            if let n = b.neon {
                cF(p, out, n.x - 1, T - n.y - 1, n.w + 2, n.h - 1); cF(p, haze("#3a3048", a), n.x, T - n.y, n.w, n.h - 3)
                text(p, n.txt, (n.x + 2) * S, (T - n.y + 1) * S, haze(hexOf(mixHex(hexOf(n.col), "#c8c8d0", 0.55)), a), S)
            }
        }
        return p
    }

    private func paintRail(_ C: HouseCityPlan, _ T: Int) -> HousePixels {
        let S = 2, p = HousePixels(C.aw * S, (T + 4) * S)
        let a = 0.14, out = haze(Self.outC, a), deck = haze("#a8a2ae", a), under = haze("#6e6878", a), pil = haze("#948ea0", a), pilS = haze("#7a7486", a), rail = haze("#4a4452", a)
        let y = T - C.deck
        for x in C.pillars { cF(p, out, x - 1, y + 3, 6, C.deck + 2); cF(p, pil, x, y + 3, 4, C.deck + 2); cF(p, pilS, x + 3, y + 3, 1, C.deck + 2); cF(p, out, x - 2, y + 3, 8, 2); cF(p, pil, x - 1, y + 3, 6, 1) }
        cF(p, out, 0, y - 1, C.aw, 6); cF(p, deck, 0, y, C.aw, 3); cF(p, under, 0, y + 3, C.aw, 1); cF(p, rail, 0, y - 1, C.aw, 1)
        var x = 1; while x < C.aw { cF(p, rail, x, y - 3, 1, 2); x += 6 }
        cF(p, rail, 0, y - 3, C.aw, 1)
        return p
    }

    private func paintNear(_ C: HouseCityPlan, _ T: Int) -> HousePixels {
        let S = 2, p = HousePixels(C.aw * S, (T + 4) * S)
        let a = 0.06, out = haze(Self.outC, a), frame = haze("#f4efe6", a), glass = haze("#506080", a), glint = haze("#a8c0dc", a), door = haze("#6a4430", a)
        let leaves = ["#d8702e", "#f0b040", "#b85a2a"].map { haze($0, a) }, trunk = haze("#6a4a2a", a)
        for tr in C.trees {
            let x = tr.x, top = T - tr.h
            cF(p, out, x - 1, top, 3, tr.h + 4); cF(p, trunk, x, top, 1, tr.h + 4)
            cF(p, out, x - 4, top - 6, 9, 7); cF(p, out, x - 3, top - 8, 7, 10); cF(p, leaves[2], x - 3, top - 5, 7, 5); cF(p, leaves[0], x - 2, top - 7, 5, 7); cF(p, leaves[1], x - 1, top - 6, 2, 2); cF(p, leaves[1], x + 1, top - 3, 1, 1)
        }
        for d in C.near {
            let x = d.x, y = T - d.h, wall = haze(HouseCityPlan.nearPal[d.col], a)
            let shade = haze(hexOf(mixHex(HouseCityPlan.nearPal[d.col], "#000000", 0.2)), a)
            let roofHex = HouseCityPlan.roofPal[d.roofC], roof = haze(roofHex, a), roofL = haze(hexOf(mixHex(roofHex, "#ffffff", 0.2)), a)
            cF(p, out, x - 1, y - 1, d.w + 2, d.h + 5); cF(p, wall, x, y, d.w, d.h + 4); cF(p, shade, x + d.w - 2, y, 2, d.h + 4)
            if d.pitch {
                let rows = Int((Double(d.w) / 2).rounded(.up)) + 1
                for i in 0..<rows {
                    let rw = d.w + 2 - i * 2; if rw < 2 { break }
                    cF(p, out, x - 2 + i, y - 1 - i, rw + 2, 1); cF(p, i % 2 == 1 ? roof : roofL, x - 1 + i, y - 1 - i, rw, 1)
                }
                if d.chim { cF(p, out, x + d.w - 6, y - 7, 4, 6); cF(p, haze("#9a5a48", a), x + d.w - 5, y - 6, 2, 5) }
            } else { cF(p, out, x - 2, y - 2, d.w + 4, 3); cF(p, roof, x - 1, y - 1, d.w + 2, 1) }
            for w in d.wins {
                let wy = T - w.y - w.h
                if w.frame { cF(p, frame, w.x - 1, wy - 1, w.w + 2, w.h + 2); cF(p, glass, w.x, wy, w.w, w.h); cF(p, glint, w.x, wy, 1, 1); cF(p, frame, w.x + 1, wy, 1, w.h) }
                else { cF(p, out, w.x - 1, wy - 1, w.w + 2, w.h + 2); cF(p, glass, w.x, wy, w.w, w.h); cF(p, glint, w.x + 1, wy, w.w - 2, 1) }
            }
            let dx = d.shop ? x + d.w - 6 : x + (d.w >> 1) - 1
            cF(p, out, dx - 1, T - 7, 4, 7); cF(p, door, dx, T - 6, 2, 6); cF(p, haze("#e8c060", a), dx + 1, T - 3, 1, 1)
            if d.shop {
                let aw2 = d.w - 2, ay = T - 8, awn = HouseCityPlan.awnCols[d.awn]
                cF(p, out, x, ay - 1, aw2 + 1, 4)
                for i in 0..<max(0, aw2) { cF(p, haze(i % 4 < 2 ? awn : "#f6f0e4", a), x + 1 + i, ay, 1, 2) }
                var i = 0; while i < aw2 { cF(p, haze(awn, a), x + 1 + i, ay + 2, 1, 1); i += 2 }
            }
        }
        return p
    }

    private func paintRoad(_ C: HouseCityPlan, _ T: Int) -> HousePixels {
        let S = 2, BD_M = 16, rows = Int((Double(BD_M) / Double(S)).rounded(.up)) + 14, W = C.aw
        let p = HousePixels(W * S, (16 + 14) * S + BD_M * 2)
        let walk = lit("#c2b8ae"), joint = lit("#a49a90"), curb = lit("#8a8484"), road = lit("#4c4c58"), dash = lit("#e8dca0"), out = lit(Self.outC)
        cF(p, walk, 0, T, W, 3)
        var x = 0; while x < W { cF(p, joint, x, T + 1, 1, 2); x += 6 }
        cF(p, curb, 0, T + 3, W, 1); cF(p, road, 0, T + 4, W, 9); cF(p, curb, 0, T + 13, W, 1); cF(p, walk, 0, T + 14, W, rows)
        x = 0; while x < W { cF(p, dash, x, T + 8, 4, 1); x += 8 }
        let r = HouseCityPlan.Rnd(9), cols = ["#d8702e", "#f0b040", "#b85a2a"]
        var i = 0
        while Double(i) < Double(W) / 5 {
            let c = lit(cols[i % 3]), px = Int(r.next() * Double(W)), py = T + Int(r.next() * 3)
            cF(p, c, px, py, 1, 1); i += 1
        }
        let post = lit("#3a3a48"), lamp = lit("#d8d4c0")
        for x in C.lamps {
            cF(p, out, x - 1, T - 14, 3, 15); cF(p, post, x, T - 13, 1, 14); cF(p, out, x - 1, T - 15, 5, 3); cF(p, post, x, T - 14, 3, 1); cF(p, lamp, x + 1, T - 13, 2, 1)
        }
        return p
    }

    private func winsLit(_ wins: [HouseCityPlan.Win], hm: Int) -> [Bool] {
        let h = hour, e = h < 12 ? h + 24 : h
        return wins.map { w in
            var on = (e >= w.on && e < w.off) || (h >= w.mOn && h < w.mOff)
            if on && w.fl != 0 && (hm + w.fl * 7) % 47 < 5 { on = false }
            return on
        }
    }

    private func paintWins(_ wins: [(HouseCityPlan.Win, Int)], top: Int, C: HouseCityPlan, hm: Int) -> HousePixels {
        let S = 2, p = HousePixels(C.aw * S, (top + 4) * S)
        let on = winsLit(wins.map(\.0), hm: hm)
        for (i, (w, _)) in wins.enumerated() where on[i] {
            let lx = w.x * S, ly = (top - w.y - w.h) * S
            p.fill(w.col, lx, ly, w.w * S, w.h * S)
            if w.frame { p.fill([60, 40, 40], lx + S, ly, S, w.h * S, alpha: 0.55) }
        }
        return p
    }

    // MARK: the sky, as layers (drawSky + drawCelestial + drawClouds): a 1 px column of the gradient, one image of the glow, the bands,
    // the stars, the moon and the sun cropped to what they cover, the city's layers and the clouds.

    static func sunX(_ k: Double, _ W: Double) -> Double { W * (0.08 + 0.84 * k) }

    struct SkyPiece {
        var key: String
        var image: CGImage?
        var tex: SKTexture?
        var color: [Int]?
        var x: Int, y: Int, w: Int, h: Int
        var z: CGFloat
        var alpha = 1.0
        var ant: Double?
    }
    struct SkyBundle {
        var pieces: [SkyPiece] = []
        var clouds: [(i: Int, tex: SKTexture, w: Int)] = []
        var reset = false
    }

    private func texture(_ img: CGImage) -> SKTexture {
        let t = SKTexture(cgImage: img)
        t.filteringMode = .nearest
        return t
    }

    func celestialImage() -> (CGImage, Int, Int)? {
        let S = 2, W = canvasW, H = canvasH, gnd = Double(ground)
        let p = HousePixels(W, H), ctx = p.ctx
        func col(_ c: [Int], _ a: Double = 1) -> CGColor { CGColor(colorSpace: HousePixels.space, components: [CGFloat(c[0]) / 255, CGFloat(c[1]) / 255, CGFloat(c[2]) / 255, CGFloat(a)])! }
        func radial(_ c: [Int], _ a0: Double, _ x: Double, _ y: Double, _ r: Double, clip: CGRect) {
            let g = CGGradient(colorsSpace: HousePixels.space, colors: [col(c, a0), col(c, 0)] as CFArray, locations: [0, 1])!
            ctx.saveGState(); ctx.clip(to: clip); ctx.setShouldAntialias(true)
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
            ctx.restoreGState()
            p.mark(clip)
        }
        let w = Self.sunGlow(hour)
        if w >= 0.02 {
            let evening = hour > 12, sx = Self.sunX(evening ? 1 : 0, Double(W)), unit = max(2, HouseLight.round(Double(H) / 300)) * S
            radial([255, 160, 100], 0.75 * w, sx, gnd, Double(W) * 0.55, clip: CGRect(x: 0, y: 0, width: W, height: H))
            var y = Int(gnd) + 4 * S
            for (i, hex) in Self.bands.enumerated() {
                let h = (3 + i * 2) * unit
                y -= h
                let a = w * (0.8 - Double(i) * 0.1), c = HouseLight.rgb(hex)
                p.fill(c, 0, y, W, h, alpha: a); p.fill(c, 0, y - S, W, S, alpha: a * 0.5)
            }
        }
        let dark = light.dark
        if dark >= 0.45 {
            let key = "\(W)x\(Int(gnd))"
            if starKey != key {
                starKey = key
                let r = HouseCityPlan.Rnd(77)
                stars = (0..<HouseLight.round(Double(W) * gnd / 9000)).map { _ in
                    let b = r.next()
                    let x = r.next() * Double(W), y = pow(r.next(), 1.4) * gnd * 0.85
                    let sp = 1200 + r.next() * 2400, ph = r.next() * 7
                    let c = r.next() < 0.2 ? [200, 215, 255] : r.next() < 0.15 ? [255, 236, 200] : [255, 255, 255]
                    return Star(x: x, y: y, b: 0.35 + b * 0.65, big: b > 0.93, sp: sp, ph: ph, c: c)
                }
            }
            let a0 = min(1, (dark - 0.45) * 2)
            for s in stars {
                let a = a0 * s.b * (0.62 + 0.38 * sin(clockMillis / s.sp + s.ph)); if a < 0.05 { continue }
                let al = Double(HouseLight.round(a * 20)) / 20, x = HouseLight.round(s.x), y = HouseLight.round(s.y), sz = s.b > 0.7 ? S : 1
                p.fill(s.c, x, y, sz, sz, alpha: al)
                if s.big {
                    p.fill(s.c, x, y, S, S, alpha: al)
                    for (dx, dy) in [(-S, 0), (S, 0), (0, -S), (0, S)] { p.fill(s.c, x + dx, y + dy, S, S, alpha: al * 0.45) }
                }
            }
        }
        func arc(_ k: Double) -> Double { gnd + 5 * Double(S) - sin(Double.pi * k) * (gnd - Double(H) * 0.1) }
        let km = (hour >= 12 ? hour - 19.5 : hour + 4.5) / 10.5
        if km > -0.08 && km < 1.08 {
            let ph = moonPhase(), lum = 1 - abs(ph - 0.5) * 2
            let mx = HouseLight.round(Self.sunX(km, Double(W))), my = HouseLight.round(arc(km))
            if lum > 0.04 {
                let gk = 0.22 * lum * max(0.3, dark)
                radial([220, 226, 255], gk, Double(mx), Double(my), Double(22 * S), clip: CGRect(x: mx - 22 * S, y: my - 22 * S, width: 44 * S, height: 44 * S))
                ctx.setShouldAntialias(false)
            }
            let q = HouseLight.round(ph * 48) % 48, cs = cos(Double(q) / 48 * Double.pi * 2), waxing = q <= 24, R0 = 6.0
            let craters = [(3, 4), (7, 3), (5, 7), (8, 8), (4, 9)]
            for j in 0..<12 { for i in 0..<12 {
                let nx = (Double(i) + 0.5 - R0) / R0, ny = (Double(j) + 0.5 - R0) / R0
                if nx * nx + ny * ny > 1 { continue }
                let hw = (1 - ny * ny).squareRoot(), on = waxing ? nx > hw * cs : nx < -hw * cs, edge = nx * nx + ny * ny > 0.72
                let isCrater = craters.contains { $0.0 == i && $0.1 == j }
                if on { p.fill(HouseLight.rgb(isCrater ? "#d4d2c4" : edge ? "#e6e4d2" : "#f6f4e4"), mx - 6 * S + i * S, my - 6 * S + j * S, S, S) }
                else { p.fill([70, 80, 120], mx - 6 * S + i * S, my - 6 * S + j * S, S, S, alpha: 0.5) }
            } }
        }
        let k = (hour - 6) / 13.5
        if k > -0.08 && k < 1.08 {
            let low = 1 - min(1, max(0, sin(Double.pi * k)) * 3.2), x = HouseLight.round(Self.sunX(k, Double(W))), y = HouseLight.round(arc(k))
            let core = mixHex("#fff4c0", "#ff9a50", low), halo = mixHex("#fff0b4", "#ff8a50", low)
            radial(halo, 0.55 + low * 0.2, Double(x), Double(y), (26 + low * 14) * Double(S), clip: CGRect(x: x - 40 * S, y: y - 40 * S, width: 80 * S, height: 80 * S))
            ctx.setShouldAntialias(false)
            p.fill(core, x - 4 * S, y - 5 * S, 8 * S, 10 * S); p.fill(core, x - 5 * S, y - 4 * S, 10 * S, 8 * S)
            p.fill(core, x - 3 * S, y - 6 * S, 6 * S, 12 * S); p.fill(core, x - 6 * S, y - 3 * S, 12 * S, 6 * S)
            p.fill(mixHex(hexOf(core), "#ffffff", 0.5), x - 3 * S, y - 4 * S, 3 * S, 2 * S)
        }
        guard let b = p.dirty else { return nil }
        let r = b.intersection(CGRect(x: 0, y: 0, width: W, height: H)).integral
        guard !r.isEmpty, let img = p.ctx.makeImage()?.cropping(to: r) else { return nil }
        return (img, Int(r.minX), Int(r.minY))
    }

    /// 0 new, .5 full: the page's moonPhase() for the date the sky shows.
    func moonPhase() -> Double {
        var d = Date()
        let c = Calendar.current
        d = c.date(bySettingHour: Int(floor(hour)), minute: Int(floor(hour.truncatingRemainder(dividingBy: 1) * 60)), second: 0, of: d) ?? d
        let days = (d.timeIntervalSince1970 * 1000 - 947182440000) / 864e5 // Date.UTC(2000, 0, 6, 18, 14)
        let f = (days / 29.530588853).truncatingRemainder(dividingBy: 1)
        return (f + 1).truncatingRemainder(dividingBy: 1)
    }

    func cloudImage(i: Int) -> (CGImage, Int) {
        let S = 2, cw = (26 + (i * 17) % 30) * S
        let a = 0.82 - light.dark * 0.4, w = Self.sunGlow(hour)
        let body = lit("#f6f8fc"), shade = lit("#d4dcec"), warm = mixHex("#ffb27a", "#ff7a8a", hour > 12 ? 0.4 : 0.1)
        let p = HousePixels(cw, 10 * S), oy = 5 * S
        p.fill(body, 0, oy, cw, 5 * S, alpha: a); p.fill(body, 5 * S, oy - 3 * S, cw - 12 * S, 3 * S, alpha: a); p.fill(body, 9 * S, oy - 5 * S, Int(Double(cw) * 0.35), 2 * S, alpha: a)
        p.fill(shade, S, oy + 4 * S, cw - 2 * S, S, alpha: a)
        if w > 0.05 {
            p.fill(warm, S, oy + 3 * S, cw - 2 * S, 2 * S, alpha: a * w); p.fill(warm, 6 * S, oy - S, cw - 14 * S, S, alpha: a * w)
            p.fill([255, 224, 176], 9 * S, oy - 5 * S, Int(Double(cw) * 0.35), S, alpha: a * w * 0.5)
        }
        return (p.image(), cw)
    }

    /// The whole sky for the current inputs; heavy, so it can run off the main thread (the painter is only ever used by one job at a time).
    func paintSky() -> SkyBundle {
        let S = 2, W = canvasW, H = canvasH
        var out = SkyBundle()
        func add(_ key: String, _ img: CGImage?, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ z: CGFloat, alpha: Double = 1) {
            var pc = SkyPiece(key: key, image: img, tex: nil, color: nil, x: x, y: y, w: w, h: h, z: z, alpha: alpha)
            if let img { pc.tex = texture(img) }
            out.pieces.append(pc)
        }
        func swatch(_ c: [Int], _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ z: CGFloat, alpha: Double, ant: Double? = nil) {
            out.pieces.append(SkyPiece(key: "", image: nil, tex: nil, color: c, x: x, y: y, w: w, h: h, z: z, alpha: alpha, ant: ant))
        }
        // the gradient: one column, stretched
        let gcol = HousePixels(1, H)
        do {
            func col(_ c: [Int]) -> CGColor { CGColor(colorSpace: HousePixels.space, components: [CGFloat(c[0]) / 255, CGFloat(c[1]) / 255, CGFloat(c[2]) / 255, 1])! }
            let g = CGGradient(colorsSpace: HousePixels.space, colors: [col(light.skyTop), col(light.skyBottom)] as CFArray, locations: [0, 1])!
            gcol.ctx.setShouldAntialias(true)
            gcol.ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: H), options: [])
        }
        add("grad", gcol.image(), 0, 0, W, H, -50_000)
        if let (img, x, y) = celestialImage() { add("cel", img, x, y, img.width, img.height, -49_900) }

        let gy = ground
        let key = "\(W)x\(H)|\(Int(skyEnv.innerHeight))"
        if cityPlan == nil || cityPlanKey != key {
            cityPlanKey = key; cityLightKey = ""; out.reset = true
            cityPlan = HouseCityPlan(width: W, ground: gy, innerHeight: skyEnv.innerHeight, base: layout.view.base, dpr: layout.view.DPR, fontWidth: { self.fontWidth($0) })
        }
        let C = cityPlan!
        let lightKey = [light.amb.x, light.amb.y, light.amb.z].map { "\(HouseLight.round($0 * 60))" }.joined(separator: ",") + "|\(HouseLight.round(light.dark * 20))"
        var fresh = false
        if lightKey != cityLightKey {
            cityLightKey = lightKey; fresh = true; out.reset = true
            var boardAt: [Int: (Int, Int, Int)] = [:]
            cityImages = [paintFar(C, C.farTop).image(), paintMid(C, C.midTop, boardAt: &boardAt).image(), paintRail(C, C.deck + 6).image(),
                          paintNear(C, C.nearTop).image(), paintRoad(C, 16).image()]
            cityBoards = boardAt
        }
        // city layers keep their texture between minutes: only a new light key sends images
        func layer(_ n: Int, _ x: Int, _ y: Int, _ z: CGFloat) { add("city\(n)", fresh ? cityImages[n] : nil, x, y, cityImages[n].width, cityImages[n].height, z) }
        let X = -16, night = max(0, min(1, (light.dark - 0.08) * 3)), hm = Int(floor(hour * 60))
        layer(0, X, gy - C.farTop * S, -49_500)
        let mx = X, my = gy - C.midTop * S
        layer(1, mx, my, -49_490)
        if night > 0 {
            let wins = C.mid.flatMap { $0.wins }.map { ($0, 0) }
            let wi = paintWins(wins, top: C.midTop, C: C, hm: hm).image()
            add("midwin", wi, mx, my, wi.width, wi.height, -49_480, alpha: night)
            for (bi, (bx, by, bw)) in cityBoards.sorted(by: { $0.key < $1.key }) where bi < C.mid.count {
                swatch([255, 240, 200], mx + bx * S, my + by * S, bw * S, 9 * S, -49_475, alpha: night * 0.35)
                swatch([255, 244, 208], mx + (bx + 2) * S, my + (by - 2) * S, S, S, -49_475, alpha: night)
                swatch([255, 244, 208], mx + (bx + bw - 3) * S, my + (by - 2) * S, S, S, -49_475, alpha: night)
            }
            for n in C.neon {
                let img = neonImage(n)
                add("neon\(C.neon.firstIndex(where: { $0.x == n.x && $0.y == n.y }) ?? 0)", img, mx + (n.x - 3) * S, my + (C.midTop - n.y - 3) * S, img.width, img.height, -49_470, alpha: night)
            }
            for an in C.ants {
                let x = mx + an.x * S, y = my + (C.midTop - an.y - 1) * S
                swatch([255, 60, 50], x - S, y - S, 3 * S, 3 * S, -49_460, alpha: 0.25 * night, ant: an.ph)
                swatch([255, 64, 48], x, y, S, S, -49_459, alpha: 1, ant: an.ph)
            }
        }
        layer(2, X, gy - (C.deck + 6) * S, -49_450)
        let ny = gy - C.nearTop * S
        layer(3, X, ny, -49_440)
        if night > 0 {
            let wins = C.near.flatMap { $0.wins }.map { ($0, 0) }
            let wi = paintWins(wins, top: C.nearTop, C: C, hm: hm).image()
            add("nearwin", wi, X, ny, wi.width, wi.height, -49_430, alpha: night)
        }
        let sy = gy - 16 * S
        layer(4, X, sy, -49_420)
        if light.dark > 0.3 {
            let a = min(1, (light.dark - 0.3) * 3), img = lampGlow()
            for x in C.lamps {
                add("lampglow", x == C.lamps.first ? img : nil, X + (x + 2) * S - 18 * S, sy + 3 * S - 4 * S, img.width, img.height, -49_410, alpha: a)
                swatch([255, 244, 200], X + (x + 1) * S, sy + 3 * S, 2 * S, S, -49_405, alpha: 1)
            }
        }
        for i in 0..<3 {
            let (img, cw) = cloudImage(i: i)
            out.clouds.append((i, texture(img), cw))
        }
        return out
    }

    func neonImage(_ n: HouseCityPlan.Neon) -> CGImage {
        let S = 2, p = HousePixels((n.w + 6) * S, (n.h + 6) * S), ctx = p.ctx
        func glyphs(_ col: [Int]) { text(p, n.txt, 5 * S, 4 * S, col, S) }
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: CGFloat(4 * S), color: CGColor(colorSpace: HousePixels.space, components: [CGFloat(n.col[0]) / 255, CGFloat(n.col[1]) / 255, CGFloat(n.col[2]) / 255, 1])!)
        glyphs(n.col)
        ctx.restoreGState()
        glyphs(mixHex(hexOf(n.col), "#ffffff", 0.45))
        return p.image()
    }

    func lampGlow() -> CGImage {
        let S = 2, p = HousePixels(36 * S, 30 * S), ctx = p.ctx
        let col = { (a: Double) in CGColor(colorSpace: HousePixels.space, components: [255 / 255, 220 / 255, 140 / 255, CGFloat(a)])! }
        let g = CGGradient(colorsSpace: HousePixels.space, colors: [col(0.45), col(0)] as CFArray, locations: [0, 1])!
        ctx.setShouldAntialias(true)
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 18 * S, y: 4 * S), startRadius: 0, endCenter: CGPoint(x: 18 * S, y: 4 * S), endRadius: CGFloat(18 * S), options: [])
        return p.image()
    }
}
