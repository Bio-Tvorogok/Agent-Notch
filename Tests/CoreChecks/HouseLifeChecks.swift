import Foundation
import CoreFoundation
#if canImport(NotchCore)
import NotchCore
#endif

struct HouseLifeChecks {
    func goldenFixtures() throws {
        let seeded = HouseBehaviour(seed: 173)
        seeded.step(dt: 50)
        XCTAssertEqual(seeded.sprites.filter { $0.kind == "cat" }.count,1,"seeded house enables life")
        let ball = HouseFetchBall(by: "test",of: 2,t0: 0)
        XCTAssertTrue(seeded.ballAt(ball,0).allSatisfy(\.isFinite),"zero-duration fetch must stay finite")
        ball.to = []; ball.from = [.nan]
        XCTAssertTrue(seeded.ballAt(ball,.infinity).allSatisfy(\.isFinite),"malformed ball must stay finite")
        let js = Process(); js.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        js.arguments = ["node","Tests/HouseChecks/life-fixtures.mjs","--check"]
        try js.run(); js.waitUntilExit()
        XCTAssertEqual(js.terminationStatus,0,"current JS must reproduce life fixtures")
        let files = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "Tests/Fixtures/house-life"),includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(files.count,8)
        var samples = 0
        for file in files {
            let f = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let input = f["input"] as! [String: Any], values = f["values"] as! [Any], trace = f["trace"] as! [[Int]]
            let rng = HouseRandom(seed: UInt32(input["seed"] as! Int)), w = HouseBehaviour(random: { rng.nextDouble() })
            w.enableLife()
            let events = input["events"] as! [[String: Any]]
            func deliver(_ event: [String: Any]) throws {
                if let hour = event["hour"] as? Double { w.life.hour = hour }
                if let dark = event["dark"] as? Double { w.life.dark = dark }
                if let rows = event["rows"] { w.setAgents(try JSONDecoder().decode([HouseAgentRow].self,from: JSONSerialization.data(withJSONObject: rows))) }
            }
            var previous = 0
            for entry in trace {
                let tick = entry[0]
                if input["frame"] != nil {
                    let pending = events.filter { ($0["at"] as! Int) > previous && ($0["at"] as! Int) <= tick }
                    for e in pending { if let hour = e["hour"] as? Double { w.life.hour = hour }; if let dark = e["dark"] as? Double { w.life.dark = dark } }
                    let rows = try pending.last?["rows"].map { try JSONDecoder().decode([HouseAgentRow].self,from: JSONSerialization.data(withJSONObject: $0)) }
                    if tick == 0 { for e in events where e["at"] as! Int == 0 { try deliver(e) } }
                    else { w.advance(frame: Double(tick-previous),agents: rows) }
                } else {
                    let first = previous == 0 && tick == 0 ? 0 : previous+50
                    for t in stride(from: first,through: tick,by: 50) {
                        for e in events where e["at"] as! Int == t {
                            // setAgents is delivered at the ending clock, before the step.
                            if let hour = e["hour"] as? Double { w.life.hour = hour }
                            if let dark = e["dark"] as? Double { w.life.dark = dark }
                        }
                        let rows = try events.first { $0["at"] as! Int == t }?["rows"].map { try JSONDecoder().decode([HouseAgentRow].self,from: JSONSerialization.data(withJSONObject: $0)) }
                        if t == 0 { if let rows { w.setAgents(rows) } }
                        else { w.step(dt: 50,agents: rows) }
                    }
                }
                var expected = values[entry[1]] as! [String: Any]
                expected["sprites"] = (expected["sprites"] as! [Int]).map { values[$0] }
                expected["render"] = (expected["render"] as! [Int]).map { values[$0] }
                try compare(expected,snapshot(w,rng),at: "\(file.lastPathComponent)[\(tick)ms]")
                samples += 1; previous = tick
            }
        }
        print("houseLifeGoldenFixtures: compared \(files.count) JS fixtures, \(samples) samples (tolerance 1e-6)")
    }
    private func snapshot(_ w: HouseBehaviour, _ rng: HouseRandom) -> [String: Any] {
        let null = NSNull()
        func v<T>(_ value: T?) -> Any { value as Any? ?? null }
        func finite(_ x: Double) -> Any { x.isFinite ? x as Any : null }
        let sprites: [[Any]] = w.sprites.map { sp in
            let l = sp.life, b = sp.behaviour
            let goal: Any = sp.goal.map { [$0.room,$0.cat,$0.i,$0.p] as [Any] } ?? null
            let errand: Any = b.errand.map { [$0.room,$0.cat,v($0.dur),finite($0.until),v($0.since),v($0.t0)] as [Any] } ?? null
            let fire: Any = l.fire.map { [$0.t0,v($0.helper),v($0.retry),v($0.foamed)] as [Any] } ?? null
            let hold: Any
            if let h = l.hold { hold = [h.kind,v(h.stage),h.t0,v(h.t1),v(h.target),v(h.state),v(h.dir),v(h.spraying),v(h.sprayFrom),v(h.z0),v(h.start),null,null] as [Any] }
            else if let h = b.handover { hold = ["handover",h.stage,h.t0,v(h.t1),null,"idle",null,null,null,null,null,h.parent,h.vanish] as [Any] }
            else { hold = null }
            let greet: Any = l.greet.map { [$0.id,$0.stage,$0.t0,v($0.t1),$0.re == 0 ? null : $0.re as Any] as [Any] } ?? null
            return [sp.id,sp.kind,v(sp.room),sp.homeRoom,sp.x,sp.y,sp.z,sp.alpha,sp.fade,v(sp.state),sp.path.count,goal,errand,
                    v(l.scene),v(l.arriveState),v(l.pose),v(l.want),sp.kind == "agent" ? null : finite(l.next),v(l.rNext),v(l.deskOf),v(l.fireOf),v(l.look),l.wag,l.ball,v(l.toss),v(l.workSince),v(l.mailAct),fire,hold,greet,sp.leaving,sp.exit,sp.moving,v(sp.seated),v(sp.waving),b.handed,b.popped,v(b.towel)]
        }
        let before = rng.state
        let render: [[Any]] = w.renderFrames().filter { $0.parachutePhase == nil }.map { f in
            var row: [Any] = [f.id,f.kind,f.pose,f.facing,f.position,f.alpha]
            row += [v(f.scene),v(f.prop),f.carryingBall,f.wagging]
            row += [v(f.fireSince),v(f.foamedAt),f.spraying,v(f.sprayTarget),v(f.tossAt),f.propFacing,f.pouring]
            return row
        }
        XCTAssertEqual(before,rng.state,"render reads must not consume RNG")
        let ball: Any = w.life.ball.map { [$0.by,$0.n,$0.of,$0.t0,$0.ms,$0.from,$0.to,$0.held,$0.stage,v($0.t1),w.ballAt($0,w.time)] as [Any] } ?? null
        return ["rng":rng.state,"sprites":sprites,"render":render,"ball":ball,"mailFlag":w.life.mailFlag,
                "fireworks":w.life.fireworks.map { [$0.room,$0.t0,$0.seed] as [Any] },
                "puffs":w.puffs.map { [$0.room,$0.x,$0.y,$0.z,$0.t0,$0.col,$0.seed] as [Any] },"papers":w.papers.map { [$0.from,$0.to,$0.t0] as [Any] }]
    }
    private struct Mismatch: Error, CustomStringConvertible { let description: String }
    private func compare(_ a: Any, _ b: Any, at path: String) throws {
        func fail() throws { throw Mismatch(description: path+": \(a) != \(b)") }
        if let a = a as? [String: Any], let b = b as? [String: Any] {
            guard Set(a.keys) == Set(b.keys) else { return try fail() }
            for k in a.keys.sorted() { if let av = a[k], let bv = b[k] { try compare(av,bv,at: path+"."+k) } }
        } else if let a = a as? [Any], let b = b as? [Any] {
            guard a.count == b.count else { return try fail() }
            for i in a.indices { try compare(a[i],b[i],at: "\(path)[\(i)]") }
        } else if let a = a as? NSNumber, let b = b as? NSNumber {
            let ab = CFGetTypeID(a) == CFBooleanGetTypeID(), bb = CFGetTypeID(b) == CFBooleanGetTypeID()
            guard ab == bb, ab ? a == b : a.doubleValue.isFinite && b.doubleValue.isFinite && abs(a.doubleValue-b.doubleValue) <= 1e-6 else { return try fail() }
        } else if a is NSNull, b is NSNull { return }
        else if let a = a as? String, let b = b as? String, a.utf16.elementsEqual(b.utf16) { return }
        else { try fail() }
    }
}
