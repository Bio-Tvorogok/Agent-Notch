import AppKit
import NotchCore
import SpriteKit

/// The life layer's sprites (HouseLife*.swift): the cat and the dog in all their poses, and what rides on a Clawd (the letter, the
/// paper, the extinguisher, the mug, the watering can, the book, the fire). Both are atlas pieces chosen here from the page's own rules.
extension HouseScene2 {
    private func idx(_ n: Int, _ period: Double, _ t: Double) -> Int {
        let k = (t / period).truncatingRemainder(dividingBy: 1)
        return min(n - 1, Int(floor(k * Double(n))))
    }

    /// drawCat / drawDog: the pose from the behaviour's life state (`frame.pose`: walk, sit, nap, bark), the frame by the page's timing.
    func petPoseName(_ sp: HouseSprite, face: Int, t: Double, frame: HouseBehaviourFrame?) -> String {
        let f = face >= 0 ? "r" : "l"
        let pose = frame?.pose ?? (sp.moving ? "walk" : sp.life.pose ?? "sit")
        if sp.kind == "cat" {
            switch pose {
            case "walk": return "cat/walk\(Int(floor(t / 120)) % 2 + 1).\(f)"
            case "nap": return "cat/nap.\(f)"
            default: return "cat/\(Int(floor(t / 700 + sp.seed * 7)) % 6 == 0 ? "sit2" : "sit1").\(f)"
            }
        }
        let ball = (frame?.carryingBall ?? sp.life.ball) ? "ball" : ""
        let wag = (frame?.wagging ?? sp.life.wag) || pose == "bark"
        switch pose {
        case "walk": return "dog/walk\(Int(floor(t / ((sp.speed ?? 1) > 1 ? 90 : 120))) % 2 + 1)\(ball).\(f)"
        case "nap": return "dog/nap.\(f)"
        case "bark": return "dog/bark.\(f).\(Int(floor(t / 260)) % 4)"
        default:
            let two = wag ? Int(floor(t / 140 + sp.seed * 7)) % 2 == 0 : Int(floor(t / 900 + sp.seed * 7)) % 6 == 0
            return "dog/\(two ? "sit2" : "sit1")\(ball).\(f)"
        }
    }

    /// Extra layers over a Clawd's body pose: what drawProps draws for the life layer (letter, paper, extinguisher, mug, can,
    /// book, fire). `glow` is the alpha of the fire's additive layer (the page's .22 + .08 sin(t/90) over the cut's .30).
    func overlayLayers(_ sp: HouseSprite, look: HouseLook, frame: HouseBehaviourFrame?, t: Double, simT: Double, vi: Int) -> (layers: [(HouseParts.PoseLayer, Bool)], glow: Double?) {
        guard let fr = frame, sp.kind == "agent" || sp.kind == "home" else { return ([], nil) }
        let vars = parts.poses.variants[vi], L = lookKey(sp, look)
        let tag = sp.moving ? "w\(Int(floor(t / 110)) % 2)" : "s"
        var names: [String] = [], glow: Double?
        if let fire = fr.fireSince {
            let foamed = fr.foamedAt.map { simT - $0 < 1500 } ?? false
            _ = fire
            names.append("\(L)/o.\(foamed ? "fireS" : "fire").\(Int(floor(t / 130 + sp.seed * 5)) % 2)")
            glow = (0.22 + 0.08 * sin(t / 90)) / 0.30
        }
        switch fr.prop {
        case "letter": names.append("\(L)/o.mail.\(tag)")
        case "paper": names.append("\(L)/o.handover.\(tag)")
        case "ext": names.append("\(L)/o.\(fr.propFacing < 0 ? "extL" : "ext").\(tag)")
        case "mug": names.append(sp.moving ? "home/o.mug.\(tag)" : "home/o.mug.s\(idx(4, 1100, t))")
        case "can": names.append(fr.pouring ? "home/o.can.p\(idx(3, 600, t))" : sp.moving ? "home/o.can.\(tag)" : "home/o.can.s")
        case "book": names.append("home/o.book.\((t / 2600 + sp.seed).truncatingRemainder(dividingBy: 1) < 0.12 ? 1 : 0)")
        default: break
        }
        var out: [(HouseParts.PoseLayer, Bool)] = []
        for n in names { if let p = vars[n] { for ly in p.layers { out.append((ly, ly.blend == "add")) } } }
        return (out, glow)
    }
}
