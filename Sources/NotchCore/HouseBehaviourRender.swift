import Foundation

/// Renderer-facing state. position is [world art-pixel X,Y]; localPosition is
/// [tile x,y,height z], with room nil during transit/fall. Canvas/camera transforms
/// belong to the renderer. Agent art is front-facing (facing = 1 in the page).
public struct HouseBehaviourFrame: Sendable {
    public let id: String, room: String?, vendor: String, small: Bool
    public let pose: String, facing: Int, animationTime: Double
    public let position, localPosition: [Double], alpha: Double
    public let parachutePhase: String?, parachuteOpen: Double
    public let seated, waving: Bool, towelUntil: Double?
}
public struct HouseParachute: Sendable {
    public let phase: String, open: Double, position: [Double]
}

extension HouseBehaviour {
    public func parachute(_ sp: HouseSprite) -> HouseParachute? {
        guard let f = sp.fall else { return nil }
        let age = (time-f.t0)/1000
        var x = f.x, y = f.y, open = 0.0
        let phase: String
        if age < 0.35 { phase = "hop"; y -= sin(age/0.35 * .pi)*20 }
        else if age < 0.75 { phase = "freefall"; y += pow((age-0.35)/0.4,2)*28 }
        else {
            open = min(1,(age-0.75)/0.3); phase = age < 1.05 ? "opening" : "parachute"
            y += 28 + (age-0.75)*32; x += sin((age-0.75)*1.6+f.seed*6)*16
        }
        return .init(phase: phase,open: open,position: [x,y])
    }
    func updateFallers() {
        let lift = houseRound((insets.top-insets.bottom)/2 * layout.view.DPR/layout.view.base)
        let h = ceil(canvas.height*layout.view.DPR/layout.view.base)
        let gone = layout.view.home[1] + h/2 - lift + 120
        for sp in sprites {
            if let f = parachute(sp), !(f.position[0].isFinite && f.position[1].isFinite) || f.position[1] > gone { sim.removeSprite(sp) }
        }
    }
    /// Read after step(). Pure: repeated reads never advance RNG or lifecycle.
    public func renderFrames() -> [HouseBehaviourFrame] {
        sprites.map { sp in
            let fall = parachute(sp), b = sp.behaviour
            let position = (fall?.position ?? worldPosition(sp)).map { $0.isFinite ? $0 : 0 }
            let pose: String
            if sp.state == "fall" { pose = "fall" }
            else if sp.moving { pose = "walk" }
            else if sp.state == "shower" || sp.state == "dry" { pose = sp.state ?? "stand" }
            else if sp.state == "done" || sp.state == "idle-sleep" { pose = "sleep" }
            else if sp.state == "waiting" { pose = "wait" }
            else if sp.state == "error" { pose = "error" }
            else if sp.state == "working" && sp.seated == true { pose = "work" }
            else { pose = "stand" }
            return .init(id: sp.id,room: sp.room,vendor: b.vendor,small: sp.small,pose: pose,facing: 1,
                         animationTime: (sp.context ?? 0) >= 0.9 ? time*0.5 : time,position: position,
                         localPosition: [sp.x,sp.y,sp.z].map { $0.isFinite ? $0 : 0 },alpha: sp.alpha,parachutePhase: fall?.phase,
                         parachuteOpen: fall?.open ?? 0,seated: sp.seated ?? false,waving: sp.waving ?? false,towelUntil: b.towel)
        }
    }
    func worldPosition(_ sp: HouseSprite) -> [Double] {
        func iso(_ x: Double, _ y: Double, _ z: Double) -> [Double] { [(x-y)*16,(x+y)*8-z*2] }
        if let ob = sp.onBridge {
            let w = (sp.seed-0.5)*0.36
            if ob.kind == "lift", let c = sim.cabins.first(where: { HouseRoutes.same($0.geometry.id,ob.pair) }) {
                return iso(c.geometry.sh.cx+w*1.4,c.geometry.sh.cy-w*0.8,c.z)
            }
            if let l = sim.links.first(where: { HouseRoutes.same($0.geometry.id,ob.pair) })?.geometry {
                if l.kind == "stair", let ang = l.ang, let steps = l.steps, steps > 0, let z0 = l.z0, let rise = l.rise {
                    let c = cos(ang), s = sin(ang), d = ob.u*l.len
                    let k = min(Double(steps),max(0,ceil(ob.u*Double(steps)-0.2)))
                    return iso(l.A[0]+c*d-s*w,l.A[1]+s*d+c*w,z0+k*rise/Double(steps))
                }
                let x = l.A[0]+(l.B[0]-l.A[0])*ob.u, y = l.A[1]+(l.B[1]-l.A[1])*ob.u
                return iso(x+(l.axis == "x" ? 0 : w),y+(l.axis == "x" ? w : 0),(l.z ?? 0)-6)
            }
        }
        guard let key = sp.room else { return [0,0] }
        let r = sim.room(key), p = iso(sp.x,sp.y,sp.z)
        guard let bath = layout.rooms.first else { return [0,0] }
        // YARD's origin is one slab below the bathroom, and so is its world position.
        return [p[0]+r.ox-bath.ox+(bath.wx ?? 0),p[1]+r.oy-bath.oy+(bath.wy ?? 0)+r.drop]
    }
}
