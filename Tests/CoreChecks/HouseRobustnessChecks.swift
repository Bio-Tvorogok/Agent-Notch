import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

/// What the golden fixtures cannot say: the port must not trap where the page's
/// frame() would have thrown into its try/catch (a state nobody planned for), and
/// it must read a frame clock the way the page does.
struct HouseRobustnessChecks {
    private static let projects = ["Agent-Notch", "hexhaven", "world", "t2", "decide"]
    private func world(_ projects: [String] = Self.projects) -> HouseSim {
        HouseSim(layout: HouseLayout.make(projects: projects, layout: .islands, canvas: .init(width: 1440, height: 900)))
    }
    private func bridgeLink(_ w: HouseSim) -> HouseLayout.Link? { w.links.first { $0.geometry.kind != "stair" }?.geometry }

    func all() throws {
        try limbo()
        try staleLinks()
        try irregularFrames()
        try faller()
        try rowsInLimbo()
        try yardExit()
        try fuzz()
        print("houseRobustnessChecks: limbo, stale links, frame clock, faller, rows in limbo, yard exit, fuzz")
    }

    // The frame after a crossing (and after a lift exit) has no room and no bridge: its
    // jump node has not run yet. A goal set then used to trap in route().
    func limbo() throws {
        let w = world()
        guard let l = bridgeLink(w) else { return XCTFail("no bridge") }
        let sp = w.spawn(id: "x", room: l.a, kind: "home")
        sp.x = l.pa.q[0]; sp.y = l.pa.q[1]; sp.z = -6
        sp.path = [HouseRouteNode(bridge: l.id, to: 1), HouseRouteNode(r: l.b, p: [l.pb.q[0], l.pb.q[1], -6], jump: true)]
        var t = 0
        while !(sp.room == nil && sp.onBridge == nil) && t < 100_000 { w.step(dt: 50); t += 50 }
        XCTAssertTrue(sp.room == nil && sp.onBridge == nil && sp.path.first?.jump == true, "crossing ends with the jump node pending")
        w.setGoal(sp, .init(room: "__kitchen", p: [1, 1.7, 0]))
        XCTAssertTrue(sp.path.first?.jump == true && HouseRoutes.same(sp.path.first?.r, l.b), "the pending jump lands the sprite first")
        for _ in 0..<4000 where !sp.path.isEmpty { w.step(dt: 50) }
        XCTAssertEqual(sp.room, "__kitchen", "and the walk goes on to the goal")
        // No room, no bridge, nothing pending: home, with a poof.
        let lost = w.spawn(id: "lost", room: "__roof", kind: "home")
        lost.room = nil; lost.path = []
        w.setGoal(lost, .init(room: "__bath", p: [3.3, 1.75, 0]))
        XCTAssertTrue(lost.path.first?.jump == true && lost.path.first?.poof == true && HouseRoutes.same(lost.path.first?.r, "__roof"))
    }

    // setAgents delivers a row change in the one frame an island agent has just left its bridge (no room, no
    // bridge): its new goal is planned from the pending jump instead of trapping.
    func rowsInLimbo() throws {
        let r = HouseRandom(seed: 173), w = HouseBehaviour(random: { r.nextDouble() })
        var rows = [HouseAgentRow(id: "main", project: "alpha", state: "working", activity: "Edit"),
                    HouseAgentRow(id: "isl", project: "beta", state: "working", activity: "Edit")]
        w.setAgents(rows)
        for _ in 0..<200 { w.step(dt: 16.7) }
        rows[1].state = "waiting"
        w.step(dt: 16.7, agents: rows)
        var hit = false
        for _ in 0..<5000 {
            guard let sp = w.sprites.first(where: { $0.id == "isl" }) else { break }
            if sp.room == nil && sp.onBridge == nil && sp.fall == nil {
                hit = true
                rows[1].state = "working"; rows[1].activity = "Read · x"
                w.step(dt: 16.7, agents: rows)
                XCTAssertTrue(sp.room != nil || sp.onBridge != nil || !sp.path.isEmpty, "the sprite keeps going after the row change")
                break
            }
            w.step(dt: 16.7)
        }
        XCTAssertTrue(hit, "the one-frame limbo after a crossing was reached")
    }

    // Agents that leave from the yard hop and parachute from its edge: finite positions all the way down, and
    // every faller is gone in the end.
    func yardExit() throws {
        let r = HouseRandom(seed: 99), w = HouseBehaviour(random: { r.nextDouble() })
        var rows = (0..<12).map { HouseAgentRow(id: "y\($0)", project: "yardp", state: "working", activity: "Bash") }
        w.setAgents(rows)
        for t in stride(from: 50, through: 80_000, by: 50) {
            if t == 3000 { for i in rows.indices { rows[i].state = "done" } }
            if t == 26_000 { rows = [] }
            w.step(dt: 50, agents: t == 3000 || t == 26_000 ? rows : nil)
            for f in w.renderFrames() {
                XCTAssertTrue(f.position.allSatisfy(\.isFinite) && f.localPosition.allSatisfy(\.isFinite), "finite render values")
            }
        }
        XCTAssertTrue(w.sprites.allSatisfy { $0.fall == nil }, "no faller is left hanging: \(w.sprites.filter { $0.fall != nil }.map(\.id))")
    }

    // A link id the layout no longer has (the page keeps the dead object alive, a value
    // world cannot): the node naming it is skipped, a walker mid-way is replanned.
    func staleLinks() throws {
        let w = world()
        let sp = w.spawn(id: "x", room: "p:hexhaven", kind: "home")
        sp.path = [HouseRouteNode(call: "ghost", aim: 0, side: "lo"), HouseRouteNode(bridge: "ghost", to: 1),
                   HouseRouteNode(r: "__kitchen", p: [2, 2, 0], jump: true)]
        for _ in 0..<10 { w.step(dt: 50) }
        XCTAssertEqual(sp.room, "__kitchen")
        let b = HouseBehaviour(random: HouseRandom(seed: 5).nextDouble)
        for i in Self.projects.indices { b.setAgents((0...i).map { HouseAgentRow(id: "a\($0)", project: Self.projects[$0]) }) }
        let rider = b.sim.spawn(id: "gone", room: "p:world", kind: "home")
        rider.room = nil; rider.onBridge = .init(kind: "bridge", pair: "vanished", u: 0.5)
        rider.path = [HouseRouteNode(bridge: "vanished", to: 1), HouseRouteNode(r: "p:t2", p: [3, 3, -6], jump: true)]
        rider.goal = .init(room: "p:decide", p: [3, 3, 0])
        let waiter = b.sim.spawn(id: "waiter", room: "p:world", kind: "home")
        waiter.path = [HouseRouteNode(call: "vanished", aim: 0, side: "lo")]
        waiter.goal = .init(room: "p:decide", p: [3, 3, 0])
        _ = b.ensureRoom("fresh")
        XCTAssertTrue(rider.onBridge == nil && rider.room == "p:t2" && !rider.path.isEmpty, "a vanished bridge lands the walker where it was headed and replans")
        XCTAssertTrue(waiter.path.allSatisfy { $0.call != "vanished" } && !waiter.path.isEmpty, "a call on a vanished stair is replanned")
        for _ in 0..<200 { b.step(dt: 50) }
    }

    // advance(frame:) is the page's frame(): the clock follows the stamps (never backwards),
    // motion is clamped to [0, 1500] ms in 50 ms substeps; step(dt:) never traps.
    func irregularFrames() throws {
        func walker(_ w: HouseSim) -> HouseSprite {
            let sp = w.spawn(id: "x", room: "__bath", kind: "home")
            w.setGoal(sp, .init(room: "p:world", p: [5, 3, 0])); return sp
        }
        let a = world(), b = world(), s1 = walker(a), s2 = walker(b)
        a.advance(frame: -50)
        XCTAssertEqual(a.time, 0); XCTAssertEqual(s1.x, s2.x)
        a.advance(frame: 4000)
        XCTAssertEqual(a.time, 4000, "the clock still follows a stall")
        for _ in 0..<30 { b.step(dt: 50) }
        XCTAssertTrue(s1.x == s2.x && s1.y == s2.y && s1.z == s2.z && s1.path.count == s2.path.count, "but motion is capped at 1.5 s")
        for bad in [Double.nan, .infinity, -.infinity, -1e300] { a.advance(frame: bad); a.step(dt: bad) }
        XCTAssertEqual(a.time, 4000)
        XCTAssertTrue(s1.x.isFinite && s1.y.isFinite)
        let c = HouseBehaviour(random: HouseRandom(seed: 3).nextDouble)
        c.advance(frame: -7); c.advance(frame: .nan); c.step(dt: -1)
        XCTAssertEqual(c.time, 0)
    }

    // An agent back while its parachute is still open: the faller keeps its id suffix and
    // finishes its fall; the new agent is a fresh sprite.
    func faller() throws {
        let b = HouseBehaviour(random: HouseRandom(seed: 9).nextDouble)
        let row = HouseAgentRow(id: "a", project: "alpha")
        b.setAgents([row])
        for _ in 0..<100 { b.step(dt: 50) }
        b.setAgents([])
        var guardTicks = 0
        while !b.sprites.contains(where: { $0.fall != nil }) && guardTicks < 1200 { b.step(dt: 50); guardTicks += 1 }
        guard let fall = b.sprites.first(where: { $0.fall != nil })?.fall else { return XCTFail("the agent never jumped") }
        for _ in 0..<20 { b.step(dt: 50) }
        b.setAgents([row])
        let name = "a#fall" + HouseBehaviour.jsNumber(fall.t0)
        XCTAssertTrue(b.sprites.contains { $0.id == name && $0.fall != nil }, "the faller is renamed, not replaced")
        XCTAssertTrue(b.sprites.contains { $0.id == "a" && $0.fall == nil }, "the agent starts over")
        for _ in 0..<1200 { b.step(dt: 50) }
        XCTAssertTrue(!b.sprites.contains { $0.id == name }, "and the faller is gone after its fall")
        XCTAssertTrue(b.sprites.contains { $0.id == "a" })
    }

    // Goals from anywhere, in any state, at any frame rate, projects joining under walkers.
    func fuzz() throws {
        var seed: UInt32 = 77
        func next() -> Double { seed = seed &* 1_664_525 &+ 1_013_904_223; return Double(seed) / 4_294_967_296 }
        let names = ["Agent-Notch", "hexhaven", "world", "t2", "decide", "trailby", "arena", "confetti", "hall", "lessons", "life-os", "screens", "tank-hero", "av-wt"]
        let menu: [Double] = [-30, 0, 16.7, 16.7, 33.4, 50, 120, 700, 1500, 4000, .nan, .infinity]
        let b = HouseBehaviour(random: HouseRandom(seed: 11).nextDouble)
        var rows: [HouseAgentRow] = []
        let states = ["working", "waiting", "done", "error", "idle"]
        for frame in 0..<6000 {
            if frame % 45 == 0 {
                if next() < 0.15 && !rows.isEmpty { rows.remove(at: Int(next() * Double(rows.count))) }
                else if rows.count < 22 { rows.append(HouseAgentRow(id: "f\(frame)", project: names[Int(next() * Double(names.count))])) }
                rows = rows.map { var r = $0; if next() < 0.3 { r.state = states[Int(next() * 5)] }; return r }
                b.setAgents(rows)
            }
            // Random goals from random states, limbo and lift rides included.
            if frame % 3 == 0, !b.sprites.isEmpty {
                let sp = b.sprites[Int(next() * Double(b.sprites.count))]
                let r = b.layout.rooms[Int(next() * Double(b.layout.rooms.count))]
                let target = next() < 0.15 ? "__yard" : r.key
                let spots = b.sim.spots(target).sorted { $0.key < $1.key }.flatMap { $0.value }
                let p = spots.isEmpty ? b.sim.hub(target) : spots[Int(next() * Double(spots.count))]
                b.sim.setGoal(sp, .init(room: target, p: p))
            }
            b.advance(frame: menu[Int(next() * Double(menu.count))])
        }
        XCTAssertTrue(b.sprites.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }
}
