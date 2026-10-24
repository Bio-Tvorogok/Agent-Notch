import Foundation

extension HouseSim {
    /// `now` is the clock of the substep that ends here (the page's `t - left`).
    func updateLifts(_ dt: Double, now: Double? = nil) {
        let now = now ?? time
        guard let lift = layout.lift else { return }
        let all = sprites
        func inCab(_ c: HouseCabinState) -> [HouseSprite] {
            all.filter { HouseRoutes.same($0.onBridge?.pair, c.geometry.id) }
        }
        func trip(_ sp: HouseSprite) -> HouseLiftTrip? { sp.path.first?.lift }
        let waiting = all.filter { trip($0) != nil && $0.onBridge == nil }
        for c in cabins {
            if c.state == "move" {
                guard let stop = c.stop else { c.state = "idle"; continue }
                let z = lift.liftZ(stop), dz = z-c.z, v = dt/1000*70
                if abs(dz) <= v { c.z = z; c.level = stop; c.state = "open"; c.t = now }
                else { c.z += (dz > 0 ? 1 : -1)*v }
                continue
            }
            if c.state == "open" {
                for sp in inCab(c) {
                    // A rider without a trip (a reroute dropped it) has nothing to ride for.
                    guard let t = trip(sp) else { sp.onBridge = nil; continue }
                    if t.to == c.level { sp.onBridge = nil; sp.path.removeFirst() }
                }
                if now-c.t > 500 {
                    for sp in waiting {
                        guard let n = sp.path.first, let t = n.lift else { continue }
                        if sp.onBridge != nil || t.from != c.level || (n.cab != nil && !HouseRoutes.same(n.cab, c.geometry.id)) { continue }
                        if inCab(c).count >= 3 { break }
                        sp.onBridge = .init(kind: "lift", pair: c.geometry.id, u: 0); sp.room = nil; n.cab = c.geometry.id
                    }
                }
                if now-c.t > 1700 {
                    let stops = inCab(c).compactMap { trip($0)?.to }
                    if !stops.isEmpty {
                        // First on equal distances, as with JS's stable sort.
                        c.stop = stops.enumerated().min { a,b in
                            let da = abs(lift.liftZ(a.element)-c.z), db = abs(lift.liftZ(b.element)-c.z)
                            return da == db ? a.offset < b.offset : da < db
                        }?.element
                        c.state = c.stop == nil ? "idle" : "move"
                    } else { c.state = "idle" }
                    for sp in waiting where HouseRoutes.same(sp.path.first?.cab,c.geometry.id) && sp.onBridge == nil { sp.path.first?.cab = nil }
                }
                continue
            }
            let free = waiting.filter { $0.onBridge == nil && $0.path.first?.cab == nil }.enumerated().sorted { a,b in
                let sa = a.element.path.first?.since ?? 0, sb = b.element.path.first?.since ?? 0
                return sa == sb ? a.offset < b.offset : sa < sb
            }.map(\.element)
            guard let want = free.first.flatMap(trip)?.from else { continue }
            func distance(_ other: HouseCabinState) -> Double { abs(other.z-lift.liftZ(want)) }
            if cabins.contains(where: { $0 !== c && $0.state == "idle" && distance($0) < distance(c) }) { continue }
            for sp in free where trip(sp)?.from == want { sp.path.first?.cab = c.geometry.id }
            if distance(c) < 0.5 { c.state = "open"; c.t = now }
            else { c.stop = want; c.state = "move" }
        }
    }

    public func stairTurn(_ link: HouseLinkState, to: Int) {
        link.turn = .init(a0: link.lift, a1: to == 1 ? 1 : 0, to: to, t0: time, ms: 1800); link.aim = -1
    }
    func updateStairs() {
        for l in links where l.geometry.kind == "stair" {
            if let turn = l.turn {
                let k = min(1,(time-turn.t0)/turn.ms), e = k < 0.5 ? 2*k*k : 1-pow(2-2*k,2)/2
                l.lift = turn.a0 + (turn.a1-turn.a0)*e
                if k >= 1 { l.lift = turn.a1; l.aim = turn.to; l.turn = nil; l.since = time }
                continue
            }
            var aboard = false, call: HouseRouteNode?
            for sp in sprites {
                if HouseRoutes.same(sp.onBridge?.pair,l.geometry.id) { aboard = true }
                if let n = sp.path.first, HouseRoutes.same(n.call,l.geometry.id), n.aim != l.aim,
                   call == nil || (n.since ?? 0) < (call?.since ?? 0) { call = n }
            }
            if aboard { continue }
            if let call { stairTurn(l,to: call.aim ?? 0); continue }
            if l.next == 0 { l.next = time + 20000 + random()*40000 }
            let since = (l.since ?? 0) == 0 ? time : l.since ?? time
            if l.aim == 1 && time-since > 15000 + Double(l.geometry.id.utf16.count % 7)*2000 { stairTurn(l,to: 0) }
            else if l.aim == 0 && time > l.next && !sprites.contains(where: { sp in
                sp.path.contains { HouseRoutes.same($0.call,l.geometry.id) || HouseRoutes.same($0.bridge,l.geometry.id) }
            }) { stairTurn(l,to: 1); l.next = time + 40000 + random()*40000 }
        }
    }
}
