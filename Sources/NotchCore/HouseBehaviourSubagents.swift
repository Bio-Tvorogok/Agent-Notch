import Foundation

extension HouseBehaviour {
    func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double { max(lo,min(hi,value)) }
    func puff(_ sp: HouseSprite) {
        if let room = sp.room, sp.onBridge == nil {
            puffs.append(.init(room: room,x: sp.x,y: sp.y,z: sp.z,t0: time,col: "#ffffff",seed: sim.random()*6))
        }
    }
    func startHandover(_ sp: HouseSprite, _ parent: HouseSprite, vanish: Bool) {
        guard let key = parent.room else { return }
        let b = sp.behaviour, r = sim.room(key)
        b.handover = .init(parent: parent.id,vanish: vanish,t0: time,errand: b.errand)
        b.errand = nil; sp.state = "idle"
        sim.setGoal(sp,.init(room: r.key,p: [clamp(parent.x+0.8,0.4,r.NX-0.4),clamp(parent.y+0.6,0.4,r.NY-0.4),0],cat: "handover"))
    }
    func releaseHandover(_ sp: HouseSprite) {
        let b = sp.behaviour
        guard let h = b.handover else { return }
        b.handover = nil
        if let a = b.agent {
            sp.state = a.state
            if let e = h.errand, a.state == "done" { b.errand = e; e.until = max(e.until,time+8000) }
            let (room,cat) = b.errand.map { ($0.room,$0.cat) } ?? placeFor(sp)
            sim.setGoal(sp,pickSpot(sp,room,cat))
        }
    }
    func trackSubagent(_ sp: HouseSprite, _ a: HouseAgentRow, _ prev: String?) -> Bool {
        let b = sp.behaviour, parentId = a.parentId.flatMap { $0.isEmpty ? nil : $0 }
        if prev == nil || prev == "", let parentId, !b.popped {
            b.popped = true
            if let p = find(parentId), let key = p.room, p.onBridge == nil, p.alpha > 0.5 {
                let r = sim.room(key)
                sp.room = key; sp.x = clamp(p.x+0.9,0.4,r.NX-0.4); sp.y = clamp(p.y+0.6,0.4,r.NY-0.4)
                sp.z = 0; sp.path = []; sp.alpha = 0; puff(sp)
            }
        }
        if let h = b.handover, h.vanish || a.state != "done" { releaseHandover(sp) }
        if b.handover == nil, let prev, !prev.isEmpty, prev != "done", a.state == "done",
           let parentId, let p = find(parentId), p.room != nil, !b.handed { startHandover(sp,p,vanish: false) }
        if b.handover != nil { sp.state = "idle"; return true }
        return false
    }
    func leaveSubagent(_ sp: HouseSprite) -> Bool {
        let b = sp.behaviour
        guard let id = b.agent?.parentId, !id.isEmpty else { return false }
        if let h = b.handover { h.vanish = true; return true }
        if !b.handed, let p = find(id), p.room != nil, !p.leaving, p.onBridge == nil { startHandover(sp,p,vanish: true); return true }
        puff(sp); sp.alpha = 0; sp.fade = 0; return true
    }
    func stepHandover(_ sp: HouseSprite) {
        guard let h = sp.behaviour.handover else { return }
        sp.state = "idle"
        let parent = find(h.parent)
        if h.stage == "walk" {
            let arrived = sp.path.isEmpty && sp.onBridge == nil && sp.goal != nil && HouseRoutes.same(sp.room,sp.goal?.room)
            if arrived || time-h.t0 > 25000 || parent == nil {
                h.stage = "give"; h.t1 = time
                if let parent, parent.room != nil, HouseRoutes.same(parent.room,sp.room) { papers.append(.init(from: sp,to: parent,t0: time)) }
            }
        } else if time - (h.t1 ?? .nan) > 1100 {
            sp.behaviour.handed = true
            if h.vanish { puff(sp); sp.behaviour.handover = nil; sp.alpha = 0; sp.fade = 0 }
            else { releaseHandover(sp) }
        }
    }
}
