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
    struct Poses: Decodable { let names: [String]; let variants: [[String: Pose]] }
    struct Amb: Decodable { let hour: Double; let amb: [Double]; let sky: [String]; let dark: Double }
    struct PageInfo: Decodable { let file, fileE: String; let w, h: Int }
    struct Edges: Decodable { let hi: Double }
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

    /// The variant for a DARK: the first whose upper edge is not below it.
    func variant(dark: Double) -> Int {
        var i = 0
        while i < light.variants.count - 1 && dark > light.variants[i].hi { i += 1 }
        return i
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
    private let sparsePages: Set<Int>
    private var unusedSky = Set<Int>()
    private var cutPages = Set<Int>()
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
        for p in parts.pages {
            guard FileManager.default.fileExists(atPath: dir.appendingPathComponent(p.file).path),
                  FileManager.default.fileExists(atPath: dir.appendingPathComponent(p.fileE).path) else { return nil }
        }
    }

    private func load(_ name: String) -> SKTexture? {
        autoreleasepool {
            guard let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(name) as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            let t = SKTexture(cgImage: img)
            t.filteringMode = .nearest
            return t
        }
    }

    func fPage(_ i: Int) -> SKTexture {
        if let t = f[i] { return t }
        let t = load(parts.pages[i].file) ?? SKTexture()
        f[i] = t
        return t
    }

    func ePage(_ i: Int) -> SKTexture {
        if let t = e[i] { return t }
        let t = load(parts.pages[i].fileE) ?? SKTexture()
        e[i] = t
        return t
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
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
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
        let s = rect(id)
        if sparsePages.contains(s.page) { cutOut(page: s.page); if let t = subs[id] { return t } }
        let pg = parts.pages[s.page], pw = Double(pg.w), ph = Double(pg.h)
        let t = SKTexture(rect: CGRect(x: Double(s.x) / pw, y: 1 - Double(s.y + s.h) / ph, width: Double(s.w) / pw, height: Double(s.h) / ph),
                          in: fPage(s.page))
        t.filteringMode = .nearest
        subs[id] = t
        return t
    }
}
