import Foundation

extension HouseBehaviour {
    public func categoryFor(_ sp: HouseSprite) -> String {
        guard let a = sp.behaviour.agent else { return "work" }
        if a.state == "waiting" { return "wait" }
        if a.state == "done" { return "sleep" }
        if a.state == "error" { return "pace" }
        let act = (a.activity ?? "").lowercased()
        if ["read","grep","glob","ls"].contains(where: { act.hasPrefix($0) }) { return "read" }
        if act.hasPrefix("web") || act.contains("fetch") || act.contains("search") { return "web" }
        if act.hasPrefix("task") || act.hasPrefix("agent") { return "task" }
        return "work"
    }
    func goalCount(_ sp: HouseSprite, _ room: String, _ cat: String) -> Int {
        sprites.filter { $0 !== sp && HouseRoutes.same($0.goal?.room,room) && $0.goal?.cat == cat }.count
    }
    public func placeFor(_ sp: HouseSprite) -> (room: String, cat: String) {
        let cat = categoryFor(sp), home = sp.homeRoom, b = sp.behaviour
        if cat == "wait" { return ("__kitchen","wait") }
        if cat == "sleep" && b.restOnRoof { return ("__roof","sleep") }
        if cat == "sleep" && b.restInYard && layout.yard.on { return ("__yard","sleep") }
        if ["work","read","web","task"].contains(cat) {
            let spots = sim.spots(home), own = spots[cat] ?? []
            if !own.isEmpty && goalCount(sp,home,cat) >= own.count {
                if let g = sp.goal, g.cat == "seat", HouseRoutes.same(g.room,home), g.i >= 0 { return (home,"seat") }
                if goalCount(sp,home,"seat") < (spots["seat"] ?? []).count { return (home,"seat") }
                func free(_ key: String) -> Bool {
                    guard let cowork = sim.spots(key)["cowork"] else { return false }
                    return goalCount(sp,key,"cowork") < cowork.count
                }
                if let g = sp.goal, g.cat == "cowork", free(g.room) { return (g.room,"cowork") }
                if let key = (["__kitchen","__roof"] + (layout.yard.on ? ["__yard"] : [])).first(where: free) { return (key,"cowork") }
            }
        }
        return (home,cat)
    }
    public func pickSpot(_ sp: HouseSprite, _ key: String, _ cat: String) -> HouseGoal {
        let spots = sim.spots(key), list = spots[cat] ?? spots["wait"] ?? [sim.hub(key)]
        let taken = sprites.filter { $0 !== sp && HouseRoutes.same($0.goal?.room,key) && $0.goal?.cat == cat }.compactMap { $0.goal?.i }
        let free = list.indices.first { !taken.contains($0) }, i = free ?? Int(floor(sp.seed * Double(list.count)))
        var p = list[i]
        if free == nil { p[0] += (sp.seed - 0.5)*0.9; p[1] += 0.6; p[2] = 0 }
        return .init(room: key,p: p,cat: cat,i: free == nil ? -1 : i)
    }
    func updateErrands() {
        for sp in sprites {
            guard let e = sp.behaviour.errand else { continue }
            let arrived = sp.path.isEmpty && HouseRoutes.same(sp.room,sp.goal?.room)
            if let dur = e.dur, dur != 0, e.t0 == nil || e.t0 == 0 {
                if arrived { e.t0 = time; e.until = time + dur }
                else if time - (e.since ?? .nan) > 120000 { e.until = time; e.lost = true }
            }
            if arrived { sp.state = e.cat == "shower" ? "shower" : e.cat == "dry" ? "dry" : e.cat == "sleep" ? "idle-sleep" : "idle" }
            if time > e.until && (arrived || e.lost) {
                sp.behaviour.errand = nil
                if e.cat == "shower", let t0 = e.t0, t0 != 0 {
                    sp.behaviour.errand = .init(room: e.room,cat: "dry",dur: 2800,since: time); sp.state = "idle"
                    sim.setGoal(sp,pickSpot(sp,e.room,"dry")); continue
                }
                if e.cat == "dry" { sp.behaviour.towel = time + 3500 }
                if let a = sp.behaviour.agent {
                    sp.state = a.state; let (room,cat) = placeFor(sp); sim.setGoal(sp,pickSpot(sp,room,cat))
                } else { sp.state = "idle"; sim.setGoal(sp,.init(room: sp.homeRoom,p: sim.hub(sp.homeRoom))) }
            }
        }
    }
    func updateYard() {
        var swinger = false
        let sw = sim.spots("__yard")["swing"]![0]
        for sp in sprites where sp.room == "__yard" {
            if !layout.yard.on {
                sp.room = "__bath"; let p = sim.hub("__bath"); sp.x = p[0]; sp.y = p[1]; sp.z = p[2]; sp.path = []
                if sp.goal?.room == "__yard" { sp.goal = nil }; continue
            }
            if sp.path.isEmpty, let g = sp.goal, g.room == "__yard", abs(g.p[0]-sw[0]) < 0.01, abs(g.p[1]-sw[1]) < 0.01, !swinger {
                let a = sp.state == "done" || sp.state == "idle-sleep" ? 0.12 : 0.32, ph = time/700 + sp.seed*6
                sp.y = sw[1] + sin(ph)*a; sp.z = sw[2] + abs(sin(ph))*a*3; swinger = true
            }
        }
    }
}
