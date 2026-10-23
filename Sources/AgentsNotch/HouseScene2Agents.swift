import AppKit
import NotchCore
import SpriteKit

/// The real agents: a HouseBehaviour (NotchCore) owns the simulation and the layout; the scene advances it with the frame delta,
/// follows its layout (a project joining relays the house out) and draws what it holds. Rows arrive through `deliver`.
extension HouseScene2 {
    /// The agents as the page's `room.setAgents` takes them; applied before the next advance, only the latest delivery counts.
    func deliver(_ rows: [HouseAgentRow]) {
        // A covered house draws nothing, but like the page it takes every delivery: an agent that comes and goes still counts for growth.
        if covered, let b = behaviour { pendingRows = nil; b.setAgents(rows); onDelivered?(); return }
        pendingRows = rows
        stir()
    }

    /// Hands the scene a behaviour that is already laid out: the scene is built for its rooms and growth levels at once.
    func attach(_ b: HouseBehaviour) {
        behaviour = b
        installSkyLife(b)
        builtProjects = b.projects.count
        growth = growthLevels(b)
    }

    func growthLevels(_ b: HouseBehaviour) -> [String: Int] {
        var lv: [String: Int] = [:]
        for g in b.growth where g.level > 0 { lv["p:" + g.project] = g.level }
        return lv
    }

    /// One advance of the simulation by `ms` (the real frame delta; the behaviour clamps it and steps in 50 ms substeps), then the
    /// layout follows. Called by `update`; the harness calls it by hand.
    func advanceBehaviour(ms: Double) {
        guard let b = behaviour else { return }
        let rows = pendingRows
        pendingRows = nil
        b.advance(frame: ms, agents: rows)
        followBehaviour(b)
        if rows != nil { onDelivered?() }
    }

    /// The rooms the behaviour has now (and how far each has grown) are the rooms the scene has.
    func followBehaviour(_ b: HouseBehaviour) {
        let lv = growthLevels(b)
        if b.projects.count == builtProjects { setGrowth(lv); return }
        builtProjects = b.projects.count
        growth = lv
        setLayout(b.layout)
    }

    /// Where a falling sprite is on the canvas: the behaviour's world position moved by the house's view offset.
    func fallPlace(_ sp: HouseSprite) -> (x: Double, y: Double, z: CGFloat, p: HouseParachute)? {
        guard let p = behaviour?.parachute(sp), let b = layout.rooms.first else { return nil }
        return (p.position[0] + b.ox - (b.wx ?? 0), p.position[1] + b.oy - (b.wy ?? 0), topZ + 6, p)
    }

    /// The parachute canopy of a faller (the page's drawFallers), painted small and cached by size and light.
    func canopy(x: Double, y: Double, open: Double, vendor: String) -> (SKTexture, CGPoint, CGSize)? {
        let S = 2.0
        guard open > 0 else { return nil }
        let w = HouseLight.round((10 + 12 * open) * S), h = HouseLight.round(9 * S * open), cx = HouseLight.round(x), top = HouseLight.round(y - 30 * S)
        guard h > 0 else { return nil }
        let sy = HouseLight.round(y - 9 * S)
        let key = "\(w),\(h),\(vendor),\(sy - top),\(Int(light.amb[0] * 255)),\(Int(light.amb[1] * 255)),\(Int(light.amb[2] * 255))"
        let origin = CGPoint(x: cx - w - 2, y: top)
        let size = CGSize(width: 2 * w + 4, height: sy - top + 2)
        if let t = canopyCache[key] { return (t, origin, size) }
        func lit(_ hex: String) -> [Int] {
            let c = HouseLight.rgb(hex); return (0..<3).map { Int(min(255, Double(c[$0]) * light.amb[$0])) }
        }
        let p = HousePixels(Int(size.width), Int(size.height)), ox = cx - w - 2, oy = top
        let (c1, c2) = vendor == "codex" ? ("#5aa0f0", "#ffffff") : ("#e86a4a", "#fff4e0")
        let out = lit("#2a1f2e")
        for r in 0..<h {
            let k = Double(h - r) / Double(h)
            let half = HouseLight.round(Double(w) * sqrt(max(0, 1 - k * k)))
            p.fill(out, cx - half - 1 - ox, top + r - (r == 0 ? 1 : 0) - oy, half * 2 + 2, r == 0 ? 2 : 1)
            var i = -half
            while i < half {
                let stripe = (Double(i + w) / (3 * S)).truncatingRemainder(dividingBy: 2) < 1
                p.fill(lit(stripe ? c1 : c2), cx + i - ox, top + r - oy, min(Int(3 * S), half - i), 1)
                i += Int(3 * S)
            }
        }
        p.fill(out, cx - w - 1 - ox, top + h - oy, w * 2 + 2, 1)
        let rope = lit("#f4f0e8")
        for ex in [-w + 1, -HouseLight.round(Double(w) / 3), HouseLight.round(Double(w) / 3), w - 2] {
            let x0 = cx + ex, y0 = top + h, x1 = cx + (ex < 0 ? -1 : ex > 0 ? 1 : 0) * Int(5 * S), y1 = sy
            let n = max(abs(x1 - x0), abs(y1 - y0), 1)
            for i in 0...n {
                p.fill(rope, HouseLight.round(Double(x0) + Double(x1 - x0) * Double(i) / Double(n)) - ox, HouseLight.round(Double(y0) + Double(y1 - y0) * Double(i) / Double(n)) - oy, 1, 1)
            }
        }
        let t = SKTexture(cgImage: p.image())
        t.filteringMode = .nearest
        if canopyCache.count > 96 { canopyCache.removeAll() }
        canopyCache[key] = t
        return (t, origin, size)
    }
}
