import Foundation

extension HouseBehaviour {
    // Drawing on the page remembers the last pet direction. Update once per
    // simulation frame so renderer reads remain pure and cannot consume RNG.
    func updateLifeFacing() {
        for sp in sprites where sp.kind == "cat" || sp.kind == "dog" {
            if let ob = sp.onBridge { sp.life.face = ob.forward == true ? 1 : -1 }
            else {
                let p = sp.path.first?.p ?? (sp.kind == "dog" ? sp.life.look : nil)
                if let p, p.count >= 2 {
                    let dx = (p[0]-sp.x)-(p[1]-sp.y)
                    if abs(dx) > 0.05 { sp.life.face = dx > 0 ? 1 : -1 }
                }
            }
        }
    }
    func lifeProp(_ sp: HouseSprite) -> String? {
        if let h = sp.life.hold { if h.kind == "ext" { return "ext" }; if h.kind == "mail" && h.stage == "go" { return "letter" } }
        if sp.behaviour.handover?.stage == "walk" { return "paper" }
        if sp.kind == "home" {
            return sp.life.scene == "coffee" ? "mug" : sp.life.scene == "water" ? "can" : sp.life.scene == "read" && scArrived(sp) && sp.goal?.cat == "read" ? "book" : nil
        }
        return nil
    }
}
