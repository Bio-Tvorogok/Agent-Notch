import Foundation

extension HouseBehaviour {
    func updateResidents() {
        for r in layout.rooms where !r.key.hasPrefix("__") {
            let roomID = Array(r.key.utf16)
            let busy = sprites.contains { $0.kind == "agent" && HouseRoutes.same($0.homeRoom,r.key) && !$0.leaving }
            if busy { life.quietSince[roomID] = nil }
            else if life.quietSince[roomID] == nil { life.quietSince[roomID] = time }
            let id = "home:"+r.key
            var home = find(id)
            if home == nil, !busy, time-(life.quietSince[roomID] ?? time) > 2500 {
                let h = sim.spawn(id: id,room: r.key,kind: "home",small: true)
                h.behaviour.vendor = "home"; h.state = "idle"; h.life.next = time+1500; home = h
            }
            guard let h = home else { continue }
            h.fade = busy ? 0 : 1
            if busy, h.alpha <= 0.01 { sim.removeSprite(h); continue }
            if !busy, h.path.isEmpty, h.behaviour.errand == nil, time > h.life.next {
                let roll = sim.random()
                func visit(_ key: String, _ cat: String, _ ms: Double) {
                    h.behaviour.errand = .init(room: key,cat: cat,until: time+ms)
                    sim.setGoal(h,pickSpot(h,key,cat)); h.state = "idle"
                }
                if roll < 0.12, let key = shared("bath") { visit(key,"wash",5000) }
                else if roll < 0.24, let key = shared("kitchen") { visit(key,"wait",7000) }
                else if roll < 0.34, let key = shared("roof") { visit(key,"look",8000) }
                else if roll < 0.46, sitOnStair(h,r) { }
                else {
                    let cat = scPick(["read","web","sleep","task","pace"]) ?? "pace"
                    sim.setGoal(h,pickSpot(h,r.key,cat)); h.state = cat == "sleep" ? "idle-sleep" : "idle"
                }
                h.life.next = time+8000+sim.random()*9000
            }
        }
    }
    // Equivalent to walkOut/walkIn for the island stair outing. Ordinary
    // destinations still use the shared HouseRoutes route planner.
    func sitOnStair(_ h: HouseSprite, _ r: HouseLayout.Room) -> Bool {
        let stairs = layout.links.filter { $0.kind == "stair" && HouseRoutes.same($0.lo,r.key) }
        guard !stairs.isEmpty, HouseRoutes.same(h.room,r.key), let l = scPick(stairs) else { return false }
        let q = l.pa.q
        var nodes: [HouseRouteNode] = []
        func far(_ a: [Double], _ b: [Double]) -> Bool { houseBehaviourHypot([a[0]-b[0],a[1]-b[1]]) > 2.2 }
        func front(_ p: [Double]) -> Bool { p[1] > r.NY+0.05 }
        func entry(_ front: Bool) -> (i: [Double],s: [Double]) {
            let fx = r.theme == "library" ? 6.4 : r.NX*0.6
            let ry = r.theme == "server" ? 4.25 : r.theme == "library" ? 5 : r.theme == "kitchen" ? 4.5 : r.NY*0.45
            return front ? ([fx,r.NY-0.45,0],[fx,r.NY+0.3,-3]) : ([r.NX-0.45,ry,0],[r.NX+0.3,ry,-3])
        }
        func grass(_ a: [Double], _ b: [Double]) {
            let la = front(a), lb = front(b)
            func onto(_ p: [Double], _ f: Bool) -> [Double] { f ? [p[0],r.NY+1,-6] : [r.NX+1,p[1],-6] }
            nodes.append(.init(r: r.key,p: onto(a,la)))
            if la != lb { nodes.append(.init(r: r.key,p: [r.NX+1.5,r.NY+1.5,-6])) }
            nodes.append(.init(r: r.key,p: onto(b,lb)))
        }
        var at = [h.x,h.y,h.z]
        if at[0] > -0.05 && at[0] < r.NX+0.05 && at[1] > -0.05 && at[1] < r.NY+0.05 {
            let e = entry(front(q))
            if far(at,sim.hub(r.key)) && far(at,e.i) { nodes.append(.init(r: r.key,p: sim.hub(r.key))) }
            nodes += [.init(r: r.key,p: e.i),.init(r: r.key,p: e.s)]; at = e.s
        }
        grass(at,q); nodes.append(.init(r: r.key,p: [q[0],q[1],-6]))
        nodes += [.init(call: l.id,aim: 0,side: "lo"),.init(bridge: l.id,to: 0.25+sim.random()*0.4),.init(wait: 9000+sim.random()*9000),.init(bridge: l.id,to: 0),.init(r: r.key,p: [q[0],q[1],-6],jump: true)]
        let e = entry(front(q)); grass([q[0],q[1],-6],e.s)
        nodes += [.init(r: r.key,p: e.s),.init(r: r.key,p: e.i)]
        if far(e.i,sim.hub(r.key)) { nodes.append(.init(r: r.key,p: sim.hub(r.key))) }
        h.path = nodes; h.goal = .init(room: r.key,p: sim.hub(r.key)); h.state = "idle"
        return true
    }
    func yardVisit(_ h: HouseSprite, _ when: String) -> Bool {
        guard layout.yard.on else { return false }
        let cat = when == "morning" ? "water" : scPick(when == "evening" ? ["bench","bench","look","swing"] : ["stroll","bench","swing","look","water"]) ?? "water"
        let ms = cat == "water" ? 9000 : cat == "stroll" ? 7000 : 12000+sim.random()*6000
        h.behaviour.errand = .init(room: "__yard",cat: cat,until: time+ms)
        sim.setGoal(h,pickSpot(h,"__yard",cat)); h.life.scene = cat == "water" ? "water" : nil
        h.state = "idle"; h.life.arriveState = "idle"; h.life.rNext = time+ms
        return true
    }
    func plantSpots(_ key: String) -> [(String,[Double])] {
        let r = sim.room(key)
        let plants: [[Double]] = r.theme == "bedroom" ? [[9,3.2,0]] : r.theme == "greenhouse" ? [[1.8,2,0],[4.6,6.6,0],[5.3,1.6,0]] : []
        var out = plants.map { (key,$0) }
        if sim.roomAt(r.tower,r.floor+1) == nil { out.append((key,[1.4,5.2,0])) }
        if let roof = shared("roof"), let p = scPick([[2.2,6.8,0],[1.4,1.8,0],[9,2.2,0]]) { out.append((roof,p)) }
        if layout.yard.on, let p = scPick(sim.spots("__yard")["water"] ?? []) { out.append(("__yard",p)) }
        return out
    }
    func residentRoutine(_ h: HouseSprite) {
        let l = h.life
        if l.next != .infinity { l.next = .infinity; l.rNext = time+1200 }
        if h.fade < 1 || hasHold(h) || h.behaviour.errand != nil || !h.path.isEmpty || time < (l.rNext ?? 0) { return }
        let hr = life.hour, key = h.homeRoom, roll = sim.random(), kitchen = shared("kitchen"), roof = shared("roof")
        func go(_ goal: HouseGoal, _ scene: String?, _ state: String, _ ms: Double) {
            sim.setGoal(h,goal); l.scene = scene; h.state = "idle"; l.arriveState = state; l.rNext = time+ms
        }
        func errand(_ key: String, _ cat: String, _ ms: Double) { h.behaviour.errand = .init(room: key,cat: cat,until: time+ms) }
        if hr >= 23 || hr < 6 {
            if h.goal?.cat == "sleep", HouseRoutes.same(h.goal?.room,key) { h.state = "idle-sleep"; l.rNext = time+20000 }
            else { go(pickSpot(h,key,"sleep"),nil,"idle-sleep",20000) }
        } else if hr < 10 {
            if let kitchen, roll < 0.6 { errand(kitchen,"coffee",9000); go(pickSpot(h,kitchen,"coffee"),"coffee","idle",3000) }
            else if roll < 0.85, yardVisit(h,"morning") { return }
            else { go(pickSpot(h,key,roll < 0.8 ? "read" : "pace"),roll < 0.8 ? "read" : l.scene,"idle",12000) }
        } else if hr < 19 {
            let plants = plantSpots(key)
            if roll < 0.45, !plants.isEmpty, let (room,p) = scPick(plants) {
                if !HouseRoutes.same(room,key) { errand(room,"water",9000) }
                go(.init(room: room,p: p,cat: "water"),"water","idle",9000)
            } else if roll < 0.55, let bath = shared("bath") { errand(bath,"wash",5000); go(pickSpot(h,bath,"wash"),nil,"idle",3000) }
            else if roll < 0.72, yardVisit(h,"day") { return }
            else {
                let cat = scPick(["web","task","pace","read"]) ?? "pace"
                // JS evaluates pickSpot before the duration's random draw.
                let goal = pickSpot(h,key,cat)
                go(goal,cat == "read" ? "read" : nil,"idle",9000+sim.random()*6000)
            }
        } else {
            if roll < 0.7 { go(pickSpot(h,key,"read"),"read","idle",15000) }
            else if roll < 0.8, yardVisit(h,"evening") { return }
            else if let roof, roll < 0.85 { errand(roof,"look",8000); go(pickSpot(h,roof,"look"),nil,"idle",3000) }
            else { go(pickSpot(h,key,"pace"),nil,"idle",8000) }
        }
    }
}
