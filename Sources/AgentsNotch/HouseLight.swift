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

    static func rgb(_ hex: String) -> [Int] {
        let n = Int(hex.dropFirst(), radix: 16) ?? 0
        return [n >> 16, n >> 8 & 255, n & 255]
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
final class HouseShaders {
    let amb = SKUniform(name: "u_amb", vectorFloat3: vector_float3(1, 1, 1))
    private var general: [Int: SKShader] = [:]
    private let pages: HousePages, generalSource: String
    let eBlack: SKShader

    init(pages: HousePages, fa: Double) {
        func source(_ black: Bool) -> String {
            """
            void main() {
                vec4 f = texture2D(u_texture, v_tex_coord);
                vec3 fc = f.a > 0.0 ? f.rgb / f.a : vec3(0.0);
                \(black ? "vec3 ec = vec3(0.0); float ea = f.a;" : """
                vec4 e = texture2D(u_e, v_tex_coord);
                vec3 ec = e.a > 0.0 ? e.rgb / e.a : vec3(0.0); float ea = e.a;
                """)
                vec3 o = clamp(ec + (fc - ec) * u_amb / \(fa), 0.0, 1.0);
                float a = clamp(ea + (f.a - ea) * u_amb.r / \(fa), 0.0, 1.0) * v_color_mix.a;
                gl_FragColor = vec4(o * a, a);
            }
            """
        }
        let u = amb, src = source(false)
        self.pages = pages; generalSource = src
        eBlack = SKShader(source: source(true), uniforms: [u])
    }

    func set(_ a: SIMD3<Double>) { amb.vectorFloat3Value = vector_float3(Float(a.x), Float(a.y), Float(a.z)) }

    /// The shader for a sprite of this page and flag; nil for a constant sprite (flag 2).
    func shader(page: Int, flag: Int) -> SKShader? {
        if flag == 1 { return eBlack }
        guard flag == 0 else { return nil }
        if let s = general[page] { return s }
        let s = SKShader(source: generalSource, uniforms: [amb, SKUniform(name: "u_e", texture: pages.ePage(page))])
        general[page] = s
        return s
    }
}
