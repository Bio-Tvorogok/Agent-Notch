import SpriteKit
import NotchCore

/// The page's eggLook(): golden Clawds (and their sparkles), raised arms on a high five and the April 1 eyes on the side a walker came from.
/// The bodies come from the atlas (gold.*, arms.*, eyep/eyen.*); the sparkles are drawn here.
extension HouseScene2 {
    /// The eggLook pose in place of a plain stand, walk or work pose of an agent; the plain name when none applies.
    func eggPoseName(_ sp: HouseSprite, name: String) -> String {
        guard sp.kind == "agent", let b = behaviour, let e = b.eggs, e.enabled, let slash = name.firstIndex(of: "/") else { return name }
        let p = String(name[..<slash]), rest = name[name.index(after: slash)...]
        guard let dot = rest.firstIndex(of: ".") else { return name }
        let kind = String(rest[..<dot]), idx = String(rest[rest.index(after: dot)...])
        if kind == "stand", e.highFives.contains(where: { ($0.a === sp || $0.b === sp) && b.time < $0.t0 + 1500 }) { return p + "/arms.stand.0" }
        if kind == "walk", e.holidays.fools, let d = eggFoolsDir(sp) { return p + (d > 0 ? "/eyen.walk." : "/eyep.walk.") + idx }
        if sp.eggs.golden { return p + "/gold.\(kind).\(idx)" } // poses without a gold cut fall back to the plain one
        return name
    }

    /// The side a walker came from (the page's eggLook): the eyes sit there, as it walks backwards.
    private func eggFoolsDir(_ sp: HouseSprite) -> Int? {
        guard sp.moving else { return nil }
        var dir = 0.0
        if let ob = sp.onBridge {
            if let L = layout.links.first(where: { $0.id == ob.pair }) {
                let d = (L.B[0] - L.B[1]) - (L.A[0] - L.A[1])
                dir = (d > 0 ? 1 : d < 0 ? -1 : 0) * (ob.forward == true ? 1 : -1)
            }
        } else if let n = sp.path.first, let q = n.p, n.r == sp.room {
            let d = (q[0] - sp.x) - (q[1] - sp.y)
            dir = d > 0 ? 1 : d < 0 ? -1 : 0
        }
        return dir == 0 ? nil : Int(dir)
    }

    /// eggAfter: the golden Clawd's glow and three sparkles.
    func eggGold(_ sp: HouseSprite, at: (x: Double, y: Double, z: CGFloat), look lk: HouseLook, t: Double) {
        guard let g = parts.poses.looks?[lookKey(sp, lk)] else { return }
        let s = 2.0, x = Double(HouseLight.round(at.x)), y = Double(HouseLight.round(at.y))
        let hop = sp.moving ? Double(Int(floor(t / 110)) % 2) * s : 0
        let top = Double(HouseLight.round(y - Double(g.rows + g.legH) * s - hop)), left = Double(HouseLight.round(x - Double(g.w) * s / 2)), bw = Double(g.w) * s
        let z = at.z + 0.05
        eggGlow("gold-glow-\(sp.id)", x, top + 4 * s, 12 * s, "#ffc830", 0.12 + 0.4 * light.dark, layer: root, z: z)
        for i in 0..<3 {
            let ph = t / 900 + Double(i) / 3 + sp.seed * 3, k = ph - floor(ph), j = Int(floor(ph)), a = sin(k * .pi)
            let fx = Double((j * 7 + i * 5) % 9) / 8, fy = Double((j * 3 + i * 11) % 7) / 6
            let sx: Int = HouseLight.round(left - 2 * s + fx * (bw + 4 * s))
            let sy: Int = HouseLight.round(top - 2 * s + fy * 12 * s)
            let (tex, size) = eggStamp("spark\(a > 0.75 ? 1 : 0)", [".p.", a > 0.75 ? "pwp" : "ppp", ".p."], ["p": emiC("#fff4b4"), "w": emiC("#ffffff")])
            eggShow("gold-spark-\(sp.id)-\(i)", tex, size, x: sx - 1, y: sy - 1, alpha: a, layer: root, z: z + 0.01)
        }
    }
}
