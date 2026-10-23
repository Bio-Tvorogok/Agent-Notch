import AppKit
import SpriteKit

/// room/atlas/parts.json (scripts/house-atlas/parts.js): the house cut into reusable parts, and the packed pages.
/// Everything is positioned against its own origin (a room's iso(0,0,0), the bathroom's for the village), so a renderer can
/// place it for any layout. Only the fields the scene reads are decoded.
struct HouseParts: Decodable {
    struct Pair: Decodable { let F: [Int]; let E: [Int] }
    struct Layer: Decodable {
        let kind: String?
        let dyn: Bool?
        let depth: Double?
        let tag: String?
        let sprite: Int?
        let x, y: Double?
        let pts: [[Double]]?
        let seed: Int?
        let floor: Int?
        let variant: String?
        let blend: String?
    }
    struct Light: Decodable { let sprite, r: Int; let x, y, a, b: Double; let blend: String? }
    struct Overlay: Decodable { let sprite: Int; let x, y: Double }
    struct RoomVariant: Decodable { let layers: [Layer]; let lights: [Light]; let overlay: [Overlay] }
    struct Clock: Decodable { let wall: String; let at, z: Double; let dark: Bool? }
    struct Room: Decodable {
        let theme: String
        let NX, NY: Double
        let floor, tower: Int
        let clock: Clock?
        let variants: [RoomVariant]
    }
    struct Part: Decodable { let layers: [Layer]; let lights: [Light] }
    struct LinkVariant: Decodable { let layers: [Layer]?; let lights: [Light]?; let down: Part?; let up: Part? }
    struct Link: Decodable {
        let kind: String
        let axis: String?
        let A, B: [Double]
        let pa, pb: String
        let variants: [LinkVariant]
    }
    struct Shaft: Decodable { let cx, cy, x0, x1, y0, y1: Double }
    struct LiftPiece: Decodable { let part: String; let shaft: Int; let key: Double; let sprite: Int; let x, y: Double }
    struct LiftFloor: Decodable { let level: Int; let room: String?; let z, zlo, zhi, depth: Double; let pieces: [LiftPiece] }
    struct LiftCage: Decodable { let shaft: Int; let part: String; let key: Double; let sprite: Int; let x, y: Double }
    struct LiftVariant: Decodable { let floors: [LiftFloor]; let cages: [LiftCage]; let rope: Pair }
    struct FloorRef: Decodable { let room: String; let yoff, z: Double }
    struct Lift: Decodable {
        let floors: Int
        let fl: [FloorRef]
        let shafts: [Shaft]
        let top, cageZ, cageH: Double
        let variants: [LiftVariant]
    }
    struct Village: Decodable { let links: [Link]; let lift: [String: Lift] }
    struct Board: Decodable { let rim, wood, edge, under, ink, inkEdge: Pair }
    struct SignVariant: Decodable { let sign, plaque: Board; let postRim, postWood: Pair; let shadow: String }
    struct Sign: Decodable { let font: [String: String]; let k, rows, post: Int; let variants: [SignVariant] }
    struct ClockCols: Decodable { let out, bg, fg: Pair }
    struct ClockVariant: Decodable { let light, dark: ClockCols }
    struct Cloud: Decodable { let i, w, y, sprite, dx, dy: Int }
    struct SkyPiece: Decodable { let sprite: Int; let x, y: Double }
    struct Bucket: Decodable { let sky: [String]; let dark: Double; let backdrop: SkyPiece?; let celestial: SkyPiece?; let clouds: [Cloud] }
    struct Sky: Decodable { let W, H, ground: Int; let buckets: [Bucket] }
    struct PoseLayer: Decodable { let sprite, ax, ay: Int; let blend: String? }
    struct Pose: Decodable { let layers: [PoseLayer] }
    /// A Clawd's geometry for the marks over it: w columns, rows body rows, legH leg rows, the arm row.
    /// body = the vendor's body colour, eyes = the [column, row] of every eye cell (the eyelids of a sleepy Clawd).
    struct Look: Decodable { let w, rows, legH, arm, lift: Int; let body: String; let eyes: [[Int]] }
    /// The desk lamp's glow sprite (additive), r its radius in canvas pixels.
    struct Lamp: Decodable { let sprite, r: Int }
    struct Poses: Decodable { let names: [String]; let variants: [[String: Pose]]; let looks: [String: Look]?; let lamp: Lamp? }
    struct Amb: Decodable { let hour: Double; let amb: [Double]; let sky: [String]; let dark: Double }
    struct PageInfo: Decodable { let file, fileE: String; let w, h: Int }
    struct Edges: Decodable { let hi: Double; let d: Double?; let exact: Bool? }
    struct LightInfo: Decodable { let variants: [Edges]; let fA: Double }

    let S: Int
    let WH, SLAB, FLOOR_STEP: Double
    let buckets: [Double]
    let ambk: [Amb]
    let rooms: [String: Room]
    let village: Village
    let sign: Sign
    let sky: Sky
    let poses: Poses
    let pages: [PageInfo]
    let clockColors: [ClockVariant]
    let clockFont: [String: String]
    let light: LightInfo
    /// [page, x, y, w, h, flag] by sprite id; flag 0 general, 1 E is black, 2 constant.
    let sprites: [[Int]]

    var variantCount: Int { light.variants.count }

    /// The variant for a DARK: the one marked exact at DARK == its value (the page mixes > .3 and >= .3), else the first
    /// non-exact one whose upper edge is not below it.
    func variant(dark: Double) -> Int {
        let v = light.variants
        if let e = v.firstIndex(where: { $0.exact == true && abs(dark - ($0.d ?? $0.hi)) < 1e-9 }) { return e }
        var last = 0
        for (i, x) in v.enumerated() where x.exact != true {
            last = i
            if dark <= x.hi { return i }
        }
        return last
    }

    /// Why the atlas cannot be drawn, nil when every per-variant list is as long as the scene indexes it.
    func problem() -> String? {
        let n = light.variants.count
        if n == 0 { return "no light variants" }
        if buckets.isEmpty || ambk.count < 2 { return "no hour table" }
        if sky.ground < 0 || sky.W <= 0 || sky.H <= 0 { return "bad sky size/ground \(sky.ground)" }
        if sky.buckets.isEmpty { return "no sky buckets" }
        if clockColors.count < n || sign.variants.count < n || poses.variants.count < n { return "variant arrays shorter than \(n)" }
        for (k, r) in rooms where r.variants.count < n { return "room \(k) has \(r.variants.count) of \(n) variants" }
        for l in village.links where l.variants.count < n { return "link \(l.pa)-\(l.pb) has \(l.variants.count) of \(n) variants" }
        for (k, l) in village.lift where l.variants.count < n { return "lift \(k) has \(l.variants.count) of \(n) variants" }
        for a in ambk where a.amb.count < 3 || a.sky.count < 2 { return "bad hour row \(a.hour)" }
        for (i, s) in sprites.enumerated() where s.count < 6 || s[0] < 0 || s[0] >= pages.count || s[3] <= 0 || s[4] <= 0 { return "bad sprite \(i)" }
        return nil
    }
}

/// The packed pages as SpriteKit textures, loaded on first use: an F page when a sprite on it is first drawn, an E page only for
/// a page that holds flag-0 sprites (flag 1 shades against black, flag 2 is constant, so their E pages are never read).
/// The decoded image is not kept: only the texture holds the pixels.
final class HousePages {
    let parts: HouseParts
    let dir: URL
    private var f: [Int: SKTexture] = [:], e: [Int: SKTexture] = [:]
    private var subs: [Int: SKTexture] = [:]
    /// Pages with at least one flag-0 sprite: the only ones whose E page is ever loaded.
    let needsE: Set<Int>
    let sparsePages: Set<Int>
    private var unusedSky = Set<Int>()
    private var cutPages = Set<Int>()
    /// The page every kept sprite is drawn from: the shaded page, grown at runtime to also hold the sprites of the sparse pages and
    /// a block of white for the plain rectangles (`ink`). One texture pair and one shader for the whole house: SpriteKit draws the
    /// house in a few batches instead of one per change of texture. nil when the atlas has no shaded page.
    let main: Int?
    /// Where a sparse page's sprite lies in the main page, and the main page's height with them.
    private(set) var moved: [Int: (x: Int, y: Int)] = [:]
    private(set) var mainH = 0
    private var whiteAt = (x: 0, y: 0)
    /// The moved sprites' pixels while the main page's F and E are being composed.
    private var movedImages: [Int: CGImage]?
    /// For measurements: the pages loaded so far.
    var loaded: (f: [Int], e: [Int]) { (f.keys.sorted(), e.keys.sorted()) }

    init?(parts: HouseParts, dir: URL) {
        self.parts = parts; self.dir = dir
        needsE = Set(parts.sprites.filter { $0[5] == 0 }.map { $0[0] })
        // The sky pieces cut into the parts (backdrops, celestials, clouds) are drawn natively now: never requested.
        var unused = Set<Int>()
        defer { unusedSky = unused }
        for b in parts.sky.buckets {
            if let x = b.backdrop { unused.insert(x.sprite) }
            if let x = b.celestial { unused.insert(x.sprite) }
            for c in b.clouds { unused.insert(c.sprite) }
        }
        // A page that is mostly such pieces is not kept whole: its other sprites are cut out into small textures.
        var sparse = Set<Int>()
        for (i, p) in parts.pages.enumerated() where !needsE.contains(i) {
            let used = parts.sprites.enumerated().filter { $0.element[0] == i && !unused.contains($0.offset) }.reduce(0) { $0 + $1.element[3] * $1.element[4] }
            if Double(used) < 0.4 * Double(p.w * p.h) { sparse.insert(i) }
        }
        sparsePages = sparse
        // the main page: the shaded page with the most sprites; the free rows under its sprites (and more rows if need be) take a 4x4
        // white block and every sprite of the sparse pages that is ever drawn, packed on shelves with 2 px between them
        let shaded = needsE.subtracting(sparse)
        let mainPage = shaded.max { a, b in parts.sprites.filter { $0[0] == a }.count < parts.sprites.filter { $0[0] == b }.count }
        main = mainPage
        if let m = mainPage {
            let pg = parts.pages[m], pad = 2
            let top = (parts.sprites.filter { $0[0] == m }.map { $0[2] + $0[4] }.max() ?? 0) + pad
            whiteAt = (pad, top)
            var x = pad + 4 + pad, y = top, shelf = 4
            let ids = parts.sprites.indices.filter { sparse.contains(parts.sprites[$0][0]) && !unused.contains($0) && parts.sprites[$0][3] + 2 * pad <= pg.w }
            for id in ids.sorted(by: { parts.sprites[$0][4] > parts.sprites[$1][4] }) {
                let w = parts.sprites[id][3], h = parts.sprites[id][4]
                if x + w + pad > pg.w { x = pad; y += shelf + pad; shelf = 0 }
                moved[id] = (x, y)
                x += w + pad; shelf = max(shelf, h)
            }
            mainH = max(pg.h, ((y + shelf + pad + 63) / 64) * 64)
        }
        for p in parts.pages {
            // the header of every page must be a PNG of the size parts.json says (the pixels are decoded on first use)
            for name in [p.file, p.fileE] {
                guard let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(name) as CFURL, nil),
                      CGImageSourceGetCount(src) > 0,
                      let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                      props[kCGImagePropertyPixelWidth] as? Int == p.w, props[kCGImagePropertyPixelHeight] as? Int == p.h else { return nil }
            }
        }
    }

    /// Called once, on the main thread, when a page cannot be decoded: the scene is blank where it is used, so the owner falls back.
    var onFailure: ((String) -> Void)?
    private var failed = false
    private func fail(_ name: String) {
        guard !failed else { return }
        failed = true
        NSLog("agents-notch: house page \(name) cannot be decoded")
        onFailure?(name)
    }

    private func load(_ name: String) -> SKTexture? {
        autoreleasepool {
            guard let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(name) as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fail(name); return nil }
            let t = SKTexture(cgImage: img)
            t.filteringMode = .nearest
            return t
        }
    }

    func fPage(_ i: Int) -> SKTexture {
        if let t = f[i] { return t }
        if i == main {
            // Every rectangle on the main page is measured against mainH rows, so the bare page file cannot stand in for it.
            let t = composed(i, e: false) ?? { fail("\(parts.pages[i].file) (composed)"); return SKTexture() }()
            f[i] = t
            if e[i] != nil { movedImages = nil }
            return t
        }
        let t = load(parts.pages[i].file) ?? SKTexture()
        f[i] = t
        return t
    }

    /// The page a sprite is drawn from (its own, or the main page for a moved sprite) and the size of that page's texture.
    func drawPage(_ id: Int) -> Int { moved[id] != nil ? main! : parts.sprites[id][0] }
    func dims(_ page: Int) -> (w: Int, h: Int) { (parts.pages[page].w, page == main ? mainH : parts.pages[page].h) }

    func ePage(_ i: Int) -> SKTexture {
        if let t = e[i] { return t }
        if i == main {
            let t = composed(i, e: true) ?? { fail("\(parts.pages[i].fileE) (composed)"); return SKTexture() }()
            e[i] = t
            if f[i] != nil { movedImages = nil }
            return t
        }
        let t = (unifies(i) ? unifiedE(i) : nil) ?? load(parts.pages[i].fileE) ?? SKTexture()
        e[i] = t
        return t
    }

    /// A plain rectangle drawn like the parts: the centre texel of the main page's white block, for a sprite tinted by its colour
    /// (colorBlendFactor 1) with the main page's shader. nil without a main page.
    func ink() -> SKTexture? {
        guard let m = main else { return nil }
        if let t = inkTexture { return t }
        let d = dims(m), x = Double(whiteAt.x + 1), y = Double(whiteAt.y + 1)
        let t = SKTexture(rect: CGRect(x: x / Double(d.w), y: 1 - (y + 1) / Double(d.h), width: 1 / Double(d.w), height: 1 / Double(d.h)), in: fPage(m))
        t.filteringMode = .nearest
        inkTexture = t
        return t
    }
    private var inkTexture: SKTexture?

    /// The main page grown to `mainH` rows: its own F (or E, made like unifiedE), the moved sprites under it (in E: black of their
    /// alpha for flag 1, themselves for flag 2) and the white block.
    private func composed(_ i: Int, e: Bool) -> SKTexture? {
        autoreleasepool {
            let pg = parts.pages[i], H = mainH
            guard let base: CGImage = e ? unifiedEImage(i) : decode(pg.file),
                  let ctx = CGContext(data: nil, width: pg.w, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: base.colorSpace ?? HousePixels.space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.interpolationQuality = .none
            ctx.setBlendMode(.copy)
            ctx.draw(base, in: CGRect(x: 0, y: H - pg.h, width: pg.w, height: pg.h))
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: whiteAt.x, y: H - whiteAt.y - 4, width: 4, height: 4))
            if movedImages == nil { movedImages = cutMoved() }
            for (id, at) in moved {
                guard let img = movedImages?[id] else { continue }
                let s = parts.sprites[id], dst = CGRect(x: at.x, y: H - at.y - s[4], width: s[3], height: s[4])
                ctx.setBlendMode(.copy)
                // Edge texels repeated one pixel into the padding, as the clamp of a standalone texture did: at fractional zoom a
                // fragment on a sprite's edge can sample just outside it.
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)] { ctx.draw(img, in: dst.offsetBy(dx: CGFloat(dx), dy: CGFloat(dy))) }
                ctx.draw(img, in: dst)
                if e && s[5] == 1 { ctx.setBlendMode(.sourceAtop); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(dst.insetBy(dx: -1, dy: -1)) }
            }
            guard let img = ctx.makeImage() else { return nil }
            let t = SKTexture(cgImage: img)
            t.filteringMode = .nearest
            return t
        }
    }

    private func decode(_ name: String) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(name) as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fail(name); return nil }
        return img
    }

    /// The moved sprites' F pixels, each copied out of its decoded page so that the page itself is not kept.
    private func cutMoved() -> [Int: CGImage] {
        var out: [Int: CGImage] = [:]
        for page in Set(moved.keys.map { parts.sprites[$0][0] }) {
            guard let img = decode(parts.pages[page].file) else { continue }
            for id in moved.keys where parts.sprites[id][0] == page {
                let s = parts.sprites[id]
                guard let c = img.cropping(to: CGRect(x: s[1], y: s[2], width: s[3], height: s[4])),
                      let ctx = CGContext(data: nil, width: s[3], height: s[4], bitsPerComponent: 8, bytesPerRow: 0, space: c.colorSpace ?? HousePixels.space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
                ctx.setBlendMode(.copy)
                ctx.draw(c, in: CGRect(x: 0, y: 0, width: s[3], height: s[4]))
                out[id] = ctx.makeImage()
            }
        }
        return out
    }

    /// A page drawn with one shader for all its sprites: it holds flag-0 sprites (so its E page is loaded anyway) and is kept whole.
    func unifies(_ i: Int) -> Bool { needsE.contains(i) && !sparsePages.contains(i) }

    /// The E page with the flag-1 and flag-2 sprites filled in so that the flag-0 shader draws them as their own shaders would:
    /// black of F's alpha under a flag-1 sprite (E black), F itself under a flag-2 sprite (constant). Every sprite of the page then
    /// shares one shader and one texture pair, so SpriteKit draws runs of them as one batch whatever their flags.
    private func unifiedE(_ i: Int) -> SKTexture? {
        autoreleasepool {
            guard let img = unifiedEImage(i) else { return nil }
            let t = SKTexture(cgImage: img)
            t.filteringMode = .nearest
            return t
        }
    }

    private func unifiedEImage(_ i: Int) -> CGImage? {
        autoreleasepool {
            let pg = parts.pages[i]
            guard let es = CGImageSourceCreateWithURL(dir.appendingPathComponent(pg.fileE) as CFURL, nil), let eImg = CGImageSourceCreateImageAtIndex(es, 0, nil),
                  let fs = CGImageSourceCreateWithURL(dir.appendingPathComponent(pg.file) as CFURL, nil), let fImg = CGImageSourceCreateImageAtIndex(fs, 0, nil),
                  let ctx = CGContext(data: nil, width: pg.w, height: pg.h, bitsPerComponent: 8, bytesPerRow: 0, space: fImg.colorSpace ?? HousePixels.space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.interpolationQuality = .none
            ctx.draw(eImg, in: CGRect(x: 0, y: 0, width: pg.w, height: pg.h))
            for s in parts.sprites where s[0] == i && s[5] != 0 {
                let src = CGRect(x: s[1], y: s[2], width: s[3], height: s[4]), dst = CGRect(x: s[1], y: pg.h - s[2] - s[4], width: s[3], height: s[4])
                guard let f = fImg.cropping(to: src) else { continue }
                ctx.setBlendMode(.copy)
                ctx.draw(f, in: dst)
                if s[5] == 1 { ctx.setBlendMode(.sourceAtop); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(dst) }
            }
            return ctx.makeImage()
        }
    }

    func rect(_ id: Int) -> (page: Int, x: Int, y: Int, w: Int, h: Int, flag: Int) {
        let s = parts.sprites[id]
        return (s[0], s[1], s[2], s[3], s[4], s[5])
    }

    /// Decodes a sparse page once, cuts every sprite that is not an unused sky piece into its own texture and drops the page.
    private func cutOut(page i: Int) {
        guard cutPages.insert(i).inserted else { return }
        autoreleasepool {
            guard let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(parts.pages[i].file) as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fail(parts.pages[i].file); return }
            for (id, s) in parts.sprites.enumerated() where s[0] == i && !unusedSky.contains(id) {
                guard let c = img.cropping(to: CGRect(x: s[1], y: s[2], width: s[3], height: s[4])) else { continue }
                let t = SKTexture(cgImage: c)
                t.filteringMode = .nearest
                subs[id] = t
            }
        }
    }

    /// The sprite's rectangle of its F page (nearest filtering, y up in texture space).
    func texture(_ id: Int) -> SKTexture {
        if let t = subs[id] { return t }
        var s = rect(id)
        if let at = moved[id] { s.page = main!; s.x = at.x; s.y = at.y } // a sparse page's sprite, moved into the main page
        else if sparsePages.contains(s.page) { cutOut(page: s.page); if let t = subs[id] { return t } }
        let d = dims(s.page), pw = Double(d.w), ph = Double(d.h)
        let t = SKTexture(rect: CGRect(x: Double(s.x) / pw, y: 1 - Double(s.y + s.h) / ph, width: Double(s.w) / pw, height: Double(s.h) / ph),
                          in: fPage(s.page))
        t.filteringMode = .nearest
        subs[id] = t
        return t
    }
}
