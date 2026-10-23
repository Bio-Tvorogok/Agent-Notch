import AppKit
import NotchCore
import SpriteKit

/// The few things the page draws live that the parts leave to the renderer, painted on the CPU into small images
/// (signs, clock faces, window panes) and the sky gradient. Pixel-exact fills, as the page's rect()/poly().
final class HousePixels {
    let w: Int, h: Int
    let ctx: CGContext
    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    init(_ w: Int, _ h: Int) {
        self.w = max(1, w); self.h = max(1, h)
        ctx = CGContext(data: nil, width: self.w, height: self.h, bitsPerComponent: 8, bytesPerRow: 0, space: Self.space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(self.h)); ctx.scaleBy(x: 1, y: -1) // y down, as the page
        ctx.setShouldAntialias(false)
        ctx.interpolationQuality = .none
    }

    func color(_ c: [Int], _ alpha: Double = 1) {
        ctx.setFillColor(CGColor(colorSpace: Self.space, components: [CGFloat(c[0]) / 255, CGFloat(c[1]) / 255, CGFloat(c[2]) / 255, CGFloat(alpha)])!)
    }
    /// What has been drawn so far (for cropping a mostly empty image); `mark` adds an area drawn some other way.
    private(set) var dirty: CGRect?
    func mark(_ r: CGRect) { dirty = dirty.map { $0.union(r) } ?? r }
    func fill(_ c: [Int], _ x: Int, _ y: Int, _ w: Int, _ h: Int, alpha: Double = 1) {
        guard w > 0, h > 0 else { return }
        mark(CGRect(x: x, y: y, width: w, height: h))
        color(c, alpha); ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }
    func image() -> CGImage { ctx.makeImage()! }

    /// The page's spans()/poly(): a polygon on integer scanlines (rounded vertices, rounded edge crossings at the row's middle).
    func poly(_ pts: [[Double]], _ c: [Int], dx: Int, dy: Int) {
        let p = pts.map { [HouseLight.round($0[0]), HouseLight.round($0[1])] }, n = p.count
        guard let y0 = p.map({ $0[1] }).min(), let y1 = p.map({ $0[1] }).max() else { return }
        color(c)
        for y in y0..<max(y0, y1) {
            let yc = Double(y) + 0.5
            var l = Double.infinity, r = -Double.infinity
            for i in 0..<n {
                let a = p[i], b = p[(i + 1) % n]
                if (a[1] <= Int(yc) && Double(a[1]) <= yc && Double(b[1]) > yc) || (Double(b[1]) <= yc && Double(a[1]) > yc) {
                    let x = Double(a[0]) + (yc - Double(a[1])) * Double(b[0] - a[0]) / Double(b[1] - a[1])
                    l = min(l, x); r = max(r, x)
                }
            }
            if l < r {
                let a = HouseLight.round(l), b = HouseLight.round(r)
                if b > a { ctx.fill(CGRect(x: a - dx, y: y - dy, width: b - a, height: 1)) }
            }
        }
    }
}


/// Everything the page paints live on a canvas and the renderer paints on the CPU (signs, clock faces, window panes, the sky and the
/// city): pure functions of these inputs, so a job can run on a background queue while the scene keeps drawing.
/// One painter is used by one job at a time.
final class HousePainter {
    struct Star { var x, y, b: Double; var big: Bool; var sp, ph: Double; var c: [Int] }
    let parts: HouseParts
    var layout: HouseLayout
    var env: HouseSkyEnv?
    var light: HouseLightState
    var hour = 12.0, clockHM = (12, 0), colon = true, clockMillis = 100_000.0
    var stars: [Star] = [], starKey = ""
    var cityPlan: HouseCityPlan?, cityPlanKey = "", cityLightKey = ""
    var cityImages: [CGImage] = [], cityBoards: [Int: (Int, Int, Int)] = [:]
    var extraScreen = false
    var canvasW: Int { Int(layout.view.width) }
    var canvasH: Int { Int(layout.view.height) }

    init(parts: HouseParts, layout: HouseLayout) {
        self.parts = parts; self.layout = layout
        light = HouseLight.state(parts, hour: 12)
    }

    /// The inputs of a frame; set before painting.
    struct Inputs {
        var light: HouseLightState, hour: Double, clockHM: (Int, Int), colon: Bool, clockMillis: Double
        var layout: HouseLayout, env: HouseSkyEnv?
        /// An extra screen leaves the sun and the moon to the main one (the page's `SCENE !== 'extra'`).
        var extraScreen = false
    }
    func set(_ i: Inputs) {
        light = i.light; hour = i.hour; clockHM = i.clockHM; colon = i.colon; clockMillis = i.clockMillis
        if i.layout.view.width != layout.view.width || i.layout.view.height != layout.view.height { cityPlanKey = "" }
        layout = i.layout; env = i.env; extraScreen = i.extraScreen
    }
}

extension HousePainter {
    // MARK: sign

    static func fitText(_ s: String) -> String {
        let t = s.uppercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let chars = Array(t)
        return chars.count > 18 ? String(chars[0..<17]) + "…" : t
    }

    func glyph(_ ch: Character) -> [String] {
        let f = parts.sign.font
        return (f[String(ch)] ?? f[String(ch).uppercased()] ?? f["?"] ?? ".").split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    }

    /// The page's signImage + drawSign for a room at an hour's light: the image and where its top-left lies on the canvas.
    /// The page's r.signHit: [x, y, w, h] of a room's sign in canvas pixels (the post counts for a sign on the grass).
    func signHit(room r: HouseLayout.Room, name: String, vi: Int) -> [Double] {
        let S = 2, k = parts.sign.k, plaque = r.floor > 0
        let chars = Array(Self.fitText(name))
        let tw = chars.enumerated().reduce(0) { $0 + glyph($1.element)[0].count + ($1.offset > 0 ? 1 : 0) } * k
        let iw = tw + 8 + 2, ih = parts.sign.rows * k + 6 + 2
        if plaque {
            let px = r.ox + (r.NX * 0.78 - r.NY) * 8 * Double(S), py = r.oy + (r.NX * 0.78 + r.NY) * 4 * Double(S) + parts.SLAB / 2 * Double(S)
            return [Double(HouseLight.round(px - Double(iw) / 2)), Double(HouseLight.round(py - Double(ih) / 2)), Double(iw), Double(ih)]
        }
        let px = r.ox + (r.NX + 0.55 - (r.NY + 0.55)) * 8 * Double(S), py = r.oy + (r.NX + 0.55 + r.NY + 0.55) * 4 * Double(S) + parts.SLAB * Double(S)
        let X = HouseLight.round(px), Y = HouseLight.round(py), sx = X - (iw >> 1), sy = Y - parts.sign.post - ih + 2 * S
        return [Double(sx), Double(sy), Double(iw), Double(Y - sy)]
    }

    func signImage(room r: HouseLayout.Room, name: String, vi: Int) -> (CGImage, CGPoint, CGSize) {
        let S = 2, b = parts.sign.variants[vi], plaque = r.floor > 0, board = plaque ? b.plaque : b.sign, k = parts.sign.k
        let text = Self.fitText(name)
        let c = { (p: HouseParts.Pair) in HouseLight.mix(p, self.light.amb, fa: self.parts.light.fA) }
        let rim = c(board.rim), wood = c(board.wood), edge = c(board.edge), under = c(board.under), ink = c(board.ink), inkEdge = c(board.inkEdge)
        let chars = Array(text)
        let tw = chars.enumerated().reduce(0) { $0 + glyph($1.element)[0].count + ($1.offset > 0 ? 1 : 0) } * k
        let w = tw + 8, h = parts.sign.rows * k + 6, iw = w + 2, ih = h + 2
        func boardPixels(_ p: HousePixels, _ ox: Int, _ oy: Int) {
            p.fill(rim, ox, oy + 1, w + 2, h); p.fill(rim, ox + 1, oy, w, h + 2); p.fill(wood, ox + 1, oy + 1, w, h)
            p.fill(edge, ox + 2, oy + 1, w - 2, 1); p.fill(under, ox + 2, oy + h, w - 2, 1)
            func stamp(_ dx: Int, _ dy: Int, _ col: [Int]) {
                var x = 5 + dx
                for ch in chars {
                    let gl = glyph(ch)
                    for (row, line) in gl.enumerated() { for (q, cell) in line.enumerated() where cell == "#" {
                        p.fill(col, ox + x + q * k, oy + 4 + dy + row * k, k, k) } }
                    x += (gl[0].count + 1) * k
                }
            }
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)] { stamp(dx, dy, inkEdge) }
            stamp(0, 0, ink)
        }
        if plaque {
            let px = r.ox + (r.NX * 0.78 - r.NY) * 8 * Double(S), py = r.oy + (r.NX * 0.78 + r.NY) * 4 * Double(S) + parts.SLAB / 2 * Double(S)
            let p = HousePixels(iw, ih)
            boardPixels(p, 0, 0)
            return (p.image(), CGPoint(x: Double(HouseLight.round(px - Double(iw) / 2)), y: Double(HouseLight.round(py - Double(ih) / 2))), CGSize(width: iw, height: ih))
        }
        let px = r.ox + (r.NX + 0.55 - (r.NY + 0.55)) * 8 * Double(S), py = r.oy + (r.NX + 0.55 + r.NY + 0.55) * 4 * Double(S) + parts.SLAB * Double(S)
        let X = HouseLight.round(px), Y = HouseLight.round(py), post = parts.sign.post
        let bx = -(iw >> 1), by = -post - ih + 2 * S
        let minX = min(-S - 1, -3 * S, bx), maxX = max(S + 1, 3 * S, bx + iw), minY = min(-post - 1, by), maxY = 1
        let p = HousePixels(maxX - minX, maxY - minY)
        p.fill(c(b.postRim), -S - 1 - minX, -post - 1 - minY, 2 * S + 2, post + 2)
        p.fill(c(b.postWood), -S - minX, -post - minY, 2 * S, post)
        p.fill([0, 0, 0], -3 * S - minX, -minY, 6 * S, 1, alpha: 0.18)
        boardPixels(p, bx - minX, by - minY)
        return (p.image(), CGPoint(x: X + minX, y: Y + minY), CGSize(width: maxX - minX, height: maxY - minY))
    }

    // MARK: clock

    func clockImage(room r: HouseLayout.Room, clock c: HouseParts.Clock, vi: Int) -> (CGImage, CGPoint, CGSize) {
        let S = 2, cc = c.dark == true ? parts.clockColors[vi].dark : parts.clockColors[vi].light
        let m = { (p: HouseParts.Pair) in HouseLight.mix(p, self.light.amb, fa: self.parts.light.fA) }
        let text = String(format: "%02d", clockHM.0) + (colon ? ":" : " ") + String(format: "%02d", clockHM.1)
        func at(_ col: Double, _ row: Double) -> [Double] {
            let x: Double, y: Double, z = c.z - row
            if c.wall == "L" { x = 0.03; y = c.at - col / 8 } else { x = c.at + col / 8; y = 0.03 }
            return [r.ox + (x - y) * 8 * Double(S), r.oy + (x + y) * 4 * Double(S) - z * Double(S)]
        }
        let outer = [at(-2, -2), at(20, -2), at(20, 7), at(-2, 7)], inner = [at(-1, -1), at(19, -1), at(19, 6), at(-1, 6)]
        let xs = outer.map { HouseLight.round($0[0]) }, ys = outer.map { HouseLight.round($0[1]) }
        let x0 = xs.min()!, y0 = ys.min()!
        let p = HousePixels(xs.max()! - x0 + 1, ys.max()! - y0 + 1)
        p.poly(outer, m(cc.out), dx: x0, dy: y0); p.poly(inner, m(cc.bg), dx: x0, dy: y0)
        var col = 0.0
        let fg = m(cc.fg)
        for ch in text {
            guard let f = parts.clockFont[String(ch)] else { continue }
            let cells = Array(f)
            for row in 0..<5 { for k in 0..<3 where cells[row * 3 + k] == "1" {
                let q = at(col + Double(k), Double(row))
                p.fill(fg, HouseLight.round(q[0]) - x0, HouseLight.round(q[1]) - y0, S, S) } }
            col += ch == ":" || ch == " " ? 3 : 4
        }
        return (p.image(), CGPoint(x: x0, y: y0), CGSize(width: p.w, height: p.h))
    }

    // MARK: pane

    /// The page's pane(): the sky outside (vertical gradient SKY[0] -> SKY[1] over the polygon's bounds), stars at night, a reflection.
    func paneImage(room r: HouseLayout.Room, layer l: HouseParts.Layer) -> (CGImage, CGPoint, CGSize)? {
        guard let pts0 = l.pts, !pts0.isEmpty else { return nil }
        let S = 2, pts = pts0.map { [$0[0] + r.ox, $0[1] + r.oy] }
        let top = pts.map { $0[1] }.min()!, bot = pts.map { $0[1] }.max()!, lft = pts.map { $0[0] }.min()!, rgt = pts.map { $0[0] }.max()!
        let x0 = Int(floor(lft)), y0 = Int(floor(top)), w = Int(ceil(rgt)) - x0, h = Int(ceil(bot)) - y0
        let p = HousePixels(w, h), ctx = p.ctx
        ctx.setShouldAntialias(true)
        ctx.saveGState()
        let path = CGMutablePath()
        for (i, q) in pts.enumerated() {
            let pt = CGPoint(x: q[0] - Double(x0), y: q[1] - Double(y0))
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        path.closeSubpath()
        ctx.addPath(path); ctx.clip()
        func col(_ c: [Int]) -> CGColor { CGColor(colorSpace: HousePixels.space, components: [CGFloat(c[0]) / 255, CGFloat(c[1]) / 255, CGFloat(c[2]) / 255, 1])! }
        let grad = CGGradient(colorsSpace: HousePixels.space, colors: [col(light.skyTop), col(light.skyBottom)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: top - Double(y0)), end: CGPoint(x: 0, y: bot - Double(y0)), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        if light.dark > 0.55 {
            let n = Int(ceil((rgt - lft) / 4)), ww = Int(rgt - lft), hh = Int(bot - top)
            for i in 0..<n where ww > 0 && hh > 0 {
                let x = lft + Double((i * 37 + r.seed) % ww), y = top + Double((i * 53 + r.seed) % hh)
                p.fill([255, 255, 255], HouseLight.round(x) - x0, HouseLight.round(y) - y0, S, S, alpha: 0.5 + 0.4 * sin(clockMillis / 1500 + Double(i)))
            }
        }
        p.color([255, 255, 255], 0.18)
        ctx.fill(CGRect(x: lft + (rgt - lft) * 0.15 - Double(x0), y: top - Double(y0), width: 3, height: bot - top))
        ctx.restoreGState()
        return (p.image(), CGPoint(x: x0, y: y0), CGSize(width: w, height: h))
    }

    // MARK: sky

    static let bands = ["#ffe8a0", "#ffc878", "#ff9e6e", "#f27a84", "#c46a9e", "#7c5ca8"]

    /// sunGlow(hr) with clear weather.
    static func sunGlow(_ hr: Double) -> Double {
        func b(_ c: Double, _ w: Double) -> Double { max(0, 1 - abs(hr - c) / w) }
        let v = max(b(6.2, 1.4), b(19.3, 1.5))
        return v * v * (3 - 2 * v)
    }
}
