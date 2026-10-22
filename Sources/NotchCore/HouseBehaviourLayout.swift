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
        // The lift's floors are numbered from the bathroom up: when a project
        // joins the tower the numbers shift, so whoever waits for a cage or rides
        // one starts the trip over from the floor it stands on.
        let oldFloors = old.lift?.fl.map(\.room) ?? [], newFloors = layout.lift?.fl.map(\.room) ?? []
        if oldFloors != newFloors {
            for sp in sprites {
                let riding = sp.onBridge?.kind == "lift", waiting = sp.path.first { $0.lift != nil }
                if !riding && waiting == nil { continue }
                let rawAt = riding ? (oldCabins.first { HouseRoutes.same($0.geometry.id,sp.onBridge?.pair) }?.level ?? 0) : waiting?.lift?.from ?? 0
                let at = rawAt < 0 ? 0 : rawAt
                let previous = oldFloors.indices.contains(at) ? oldFloors[at] : nil
                let to = riding || sp.room == nil ? (at == 0 ? (layout.yard.on ? "__yard" : "__bath") : previous ?? (layout.yard.on ? "__yard" : "__bath")) : sp.room ?? sp.homeRoom
                sp.onBridge = nil; sp.path = []; sp.room = sim.hasRoom(to) ? to : sp.homeRoom
                if riding, let key = sp.room {
                    let yard = layout.yard
                    let p = key == "__yard" ? (yard.YW.indices.contains(yard.YGATE["tower"] ?? -1) ? yard.YW[yard.YGATE["tower"] ?? 0] : sim.hub(key)) : sim.hub(key)
                    sp.x = p[0]; sp.y = p[1]; sp.z = p.count > 2 ? p[2] : 0
                }
                if let goal = sp.goal { sim.setGoal(sp,goal) }
            }
        }
        // A walker halfway across keeps going on the same bridge, stair or cage
        // when it still exists (ids are stable, nothing to rebind); when it is
        // gone the walker lands where its path was headed. A walker still on the
        // ground heading for a vanished link replans from where it stands (the
        // page leaves it waving at the dead link for good).
        for sp in sprites {
            if let ob = sp.onBridge {
                let exists = ob.kind == "lift" ? sim.cabins.contains { HouseRoutes.same($0.geometry.id,ob.pair) } : sim.link(ob.pair) != nil
                if exists { sp.path.removeAll { n in (n.bridge ?? n.call).map { sim.link($0) == nil } ?? false }; continue }
                let to = sp.path.first { $0.r != nil }?.r ?? sp.homeRoom
                let key = sim.hasRoom(to) ? to : sp.homeRoom, p = sim.hub(key)
                sp.onBridge = nil; sp.room = key; sp.x = p[0]; sp.y = p[1]; sp.z = 0; sp.path = []
                if let goal = sp.goal { sim.setGoal(sp,goal) }
            } else if sp.path.contains(where: { n in (n.bridge ?? n.call).map { sim.link($0) == nil } ?? false }) {
                if let goal = sp.goal { sim.setGoal(sp,goal) }
                else { sp.path.removeAll { n in (n.bridge ?? n.call).map { sim.link($0) == nil } ?? false } }
            }
        }
        for sp in sprites where sp.onBridge == nil {
            for n in sp.path { if let c = n.cab, !sim.cabins.contains(where: { HouseRoutes.same($0.geometry.id,c) }) { n.cab = nil } }
        }
        return key
    }
}
