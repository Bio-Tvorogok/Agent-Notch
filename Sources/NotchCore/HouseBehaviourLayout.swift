import Foundation

extension HouseBehaviour {
    func ensureRoom(_ project: String) -> String {
        let key = "p:" + project
        if layout.rooms.contains(where: { HouseRoutes.same($0.key,key) }) { return key }
        projects.append(project); born.append((key,time))
        let old = layout, oldLinks = sim.links, oldCabins = sim.cabins
        sim.layout = .make(projects: projects,layout: style,canvas: canvas,insets: insets,themes: themes)
        sim.links = layout.links.map { g in
            let l = HouseLinkState(g)
            if g.kind == "stair", let o = oldLinks.first(where: { HouseRoutes.same($0.geometry.id,g.id) }), o.geometry.kind == "stair", o.geometry.targets?.count == g.targets?.count {
                l.lift = o.lift; l.aim = o.aim; l.turn = o.turn; l.next = o.next
            }
            return l
        }
        sim.cabins = (layout.lift?.cabins ?? []).enumerated().map { i,g in
            let c = HouseCabinState(g)
            if oldCabins.indices.contains(i), let lift = layout.lift, lift.fl.indices.contains(oldCabins[i].level) {
                c.level = oldCabins[i].level; c.z = lift.liftZ(c.level); c.state = "open"; c.t = time
            }
            return c
        }
        let oldFloors = old.lift?.fl.map(\.room) ?? [], newFloors = layout.lift?.fl.map(\.room) ?? []
        if oldFloors != newFloors {
            for sp in sprites {
                let riding = sp.onBridge?.kind == "lift", waits = sp.path.contains { $0.lift != nil }
                if !riding && !waits { continue }
                let rawAt = riding ? (oldCabins.first { HouseRoutes.same($0.geometry.id,sp.onBridge?.pair) }?.level ?? 0) : sp.path.first { $0.lift != nil }!.lift!.from
                let at = rawAt < 0 ? 0 : rawAt
                let previous = oldFloors.indices.contains(at) ? oldFloors[at] : nil
                let to = riding || sp.room == nil ? (at == 0 || previous == nil ? (layout.yard.on ? "__yard" : "__bath") : previous!) : sp.room!
                sp.onBridge = nil; sp.path = []; sp.room = layout.rooms.contains { HouseRoutes.same($0.key,to) } || to == "__yard" ? to : sp.homeRoom
                if riding {
                    let p = sp.room == "__yard" ? layout.yard.YW[layout.yard.YGATE["tower"]!] : sim.hub(sp.room!)
                    sp.x = p[0]; sp.y = p[1]; sp.z = p.count > 2 ? p[2] : 0
                }
                if let goal = sp.goal { sim.setGoal(sp,goal) }
            }
        }
        for sp in sprites {
            guard let ob = sp.onBridge else { continue }
            let exists = ob.kind == "lift" ? sim.cabins.contains { HouseRoutes.same($0.geometry.id,ob.pair) } : sim.links.contains { HouseRoutes.same($0.geometry.id,ob.pair) }
            if !exists {
                let to = sp.path.first { $0.r != nil }?.r ?? sp.homeRoom
                sp.onBridge = nil; sp.room = to; let p = sim.hub(to); sp.x = p[0]; sp.y = p[1]; sp.z = 0; sp.path = []
                if let goal = sp.goal { sim.setGoal(sp,goal) }
            }
        }
        return key
    }
}
