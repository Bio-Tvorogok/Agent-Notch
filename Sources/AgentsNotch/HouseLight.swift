import AppKit
import SpriteKit
import simd

/// The page's light for an hour (setTime over AMBK) and the SKShader that applies it to the parts:
/// out.rgb = clamp(E + (F - E) * AMB / FA), out.a = Ea + (Fa - Ea) * AMB.r / FA, FA = parts.json light.fA.
struct HouseLightState {
    var amb: SIMD3<Double>
    var skyTop: [Int], skyBottom: [Int]
    var dark: Double
    var variant: Int
}

enum HouseLight {
    /// JS Math.round: halves go up.
    static func round(_ v: Double) -> Int { Int(floor(v + 0.5)) }

    nonisolated(unsafe) private static var rgbCache: [String: [Int]] = [:]
    private static let rgbLock = NSLock()
    static func rgb(_ hex: String) -> [Int] {
        rgbLock.lock(); defer { rgbLock.unlock() } // also called off the main thread
        if let c = rgbCache[hex] { return c }
        let n = Int(hex.dropFirst(), radix: 16) ?? 0
        let v = [n >> 16, n >> 8 & 255, n & 255]
        if rgbCache.count < 4096 { rgbCache[hex] = v }
        return v
    }

    /// setTime(hour): AMB, DARK and SKY mixed linearly between the two AMBK rows around the hour (row 24 repeats row 0).
    static func state(_ parts: HouseParts, hour: Double) -> HouseLightState {
        var rows = parts.ambk
        if let first = rows.first { rows.append(HouseParts.Amb(hour: 24, amb: first.amb, sky: first.sky, dark: first.dark)) }
        var i = 0
        while i + 2 < rows.count && rows[i + 1].hour <= hour { i += 1 }
        let a = rows[i], b = rows[i + 1], t = (hour - a.hour) / (b.hour - a.hour)
        let amb = SIMD3((0..<3).map { a.amb[$0] + (b.amb[$0] - a.amb[$0]) * t })
        func mix(_ x: String, _ y: String) -> [Int] {
            let p = rgb(x), q = rgb(y)
            return (0..<3).map { round(Double(p[$0]) + Double(q[$0] - p[$0]) * t) }
        }
        let dark = a.dark + (b.dark - a.dark) * t
        return HouseLightState(amb: amb, skyTop: mix(a.sky[0], b.sky[0]), skyBottom: mix(a.sky[1], b.sky[1]), dark: dark, variant: parts.variant(dark: dark))
    }

    /// mixCol of the parts' compositor: a (F, E) colour pair under the current AMB, clamped.
    static func mix(_ p: HouseParts.Pair, _ amb: SIMD3<Double>, fa: Double) -> [Int] {
        (0..<3).map { max(0, min(255, round(Double(p.E[$0]) + Double(p.F[$0] - p.E[$0]) * amb[$0] / fa))) }
    }
}

/// One uniform per scene, shared by every shader, so a new AMB is one assignment.
/// A page kept whole draws all its sprites with one shader (HousePages.unifies: its E page stands in for the flag-1 and flag-2 shaders),
/// and no sprite carries an attribute: the texel grid the shader snaps to is a constant of the shader. Runs of sprites in draw order
/// then share shader, textures and uniforms, which SpriteKit draws as one batch.
final class HouseShaders {
    let amb = SKUniform(name: "u_amb", vectorFloat3: vector_float3(1, 1, 1))
    private var general: [Int: SKShader] = [:]
    private var black: [String: SKShader] = [:]
    private let pages: HousePages, fa: Double

    init(pages: HousePages, fa: Double) { self.pages = pages; self.fa = fa }

    /// The light of the parts: out.rgb = clamp(E + (F - E) * AMB / FA), out.a = Ea + (Fa - Ea) * AMB.r / FA. A custom shader samples
    /// linearly whatever the texture's filtering says, so the shader snaps the coordinate to the centre of a texel of the `w` x `h`
    /// texture the coordinate runs over (the whole page for a cut of a page, the sprite itself for a sparse page's standalone texture);
    /// zoomed in, the art stays pixel art.
    private func source(black: Bool, w: Int, h: Int) -> String {
        """
        void main() {
            vec2 dim = vec2(\(w).0, \(h).0);
            vec2 tc = (floor(v_tex_coord * dim) + 0.5) / dim;
            vec4 f = texture2D(u_texture, tc);
            vec3 fc = f.a > 0.0 ? f.rgb / f.a : vec3(0.0);
            \(black ? "vec3 ec = vec3(0.0); float ea = f.a;" : """
            vec4 e = texture2D(u_e, tc);
            vec3 ec = e.a > 0.0 ? e.rgb / e.a : vec3(0.0); float ea = e.a;
            """)
            vec3 o = clamp(ec + (fc - ec) * u_amb / \(fa), 0.0, 1.0);
            float a = clamp(ea + (f.a - ea) * u_amb.r / \(fa), 0.0, 1.0) * v_color_mix.a;
            gl_FragColor = vec4(o * a, a);
        }
        """
    }

    func set(_ a: SIMD3<Double>) { amb.vectorFloat3Value = vector_float3(Float(a.x), Float(a.y), Float(a.z)) }

    /// Shades a sprite with its page's shader (none for a constant sprite of a page that is not unified).
    func apply(to n: SKSpriteNode, id: Int) {
        if let sh = shader(id) { n.shader = sh }
    }

    /// The shader for a sprite: its page's for any sprite of a unified page, otherwise E black for flag 1 and nil for flag 2.
    func shader(_ id: Int) -> SKShader? {
        let r = pages.rect(id), pg = pages.parts.pages[r.page]
        if pages.unifies(r.page) {
            if let s = general[r.page] { return s }
            let s = SKShader(source: source(black: false, w: pg.w, h: pg.h), uniforms: [amb, SKUniform(name: "u_e", texture: pages.ePage(r.page))])
            general[r.page] = s
            return s
        }
        guard r.flag == 1 else { return nil }
        let (w, h) = pages.sparsePages.contains(r.page) ? (r.w, r.h) : (pg.w, pg.h)
        if let s = black["\(w)x\(h)"] { return s }
        let s = SKShader(source: source(black: true, w: w, h: h), uniforms: [amb])
        black["\(w)x\(h)"] = s
        return s
    }
}
