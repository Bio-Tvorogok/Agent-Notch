import Foundation
import CoreFoundation
#if canImport(NotchCore)
import NotchCore
#endif

struct HouseBehaviourChecks {
    // Pin row ingestion, RNG short-circuiting, layout changes during transit,
    // errand arrival clocks, subagent handback, and fall removal to the real page.
    func goldenFixtures() throws {
        // Debug aid: NOTCH_BEH_DIR=<dir> compares fixtures generated elsewhere (BEH_DIR/BEH_ONLY/BEH_EXTRA for the generator).
        let scratch = ProcessInfo.processInfo.environment["NOTCH_BEH_DIR"]
        let js = Process()
        js.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        js.arguments = ["node", "Tests/HouseChecks/behaviour-fixtures.mjs", "--check"]
        if scratch == nil { try js.run(); js.waitUntilExit()
        XCTAssertEqual(js.terminationStatus, 0, "current JS must reproduce committed behaviour fixtures") }
        let files = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: scratch ?? "Tests/Fixtures/house-behaviour"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if scratch == nil { XCTAssertEqual(files.map(\.lastPathComponent), ["01-projects.json","03-projects.json","06-projects.json","14-projects.json","churn-10.json","churn-5.json","churn-growth.json","crowding-bath.json","growth-ring.json","lost-errand.json","odd-projects.json","relayout-bridges.json","relayout-lift-a.json","relayout-lift-b.json","relayout-lift-c.json","subagents-return.json","yard-exit.json"]) }
        var samples = 0
        for file in files {
            let f = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let input = f["input"] as! [String: Any], values = f["values"] as! [Any], trace = f["trace"] as! [[Int]]
            let rng = HouseRandom(seed: UInt32(input["seed"] as! Int))
            let world = HouseBehaviour(random: { rng.nextDouble() })
            let events = input["events"] as! [[String: Any]], every = input["sample"] as? Int ?? 250
            for tick in stride(from: 0, through: input["duration"] as! Int, by: 50) {
                let event = events.first { $0["at"] as! Int == tick }
                let rows = try event.flatMap { $0["rows"] }.map { try JSONDecoder().decode([HouseAgentRow].self, from: JSONSerialization.data(withJSONObject: $0)) }
                // Home sprites that were in the tower before any project room existed (they spawn before the tick's rows).
                for j in event?["inject"] as? [[String: Any]] ?? [] {
                    let sp = world.sim.spawn(id: j["id"] as! String, room: j["room"] as! String, kind: j["kind"] as! String)
                    if let e = j["errand"] as? [String: Any] {
                        sp.behaviour.errand = .init(room: e["room"] as! String, cat: e["cat"] as! String, dur: (e["dur"] as? NSNumber)?.doubleValue, since: world.time)
                    }
                    if let g = j["goal"] as? [String: Any] {
                        world.sim.setGoal(sp, .init(room: g["room"] as! String, p: g["p"] as! [Double], cat: g["cat"] as! String))
                    }
                }
                if tick == 0 { if let rows { world.setAgents(rows) } }
                else { world.step(dt: 50, agents: rows) }
                if tick % every == 0 {
                    var expected = values[trace[tick/every][1]] as! [String: Any]
                    expected["sprites"] = (expected["sprites"] as! [Int]).map { values[$0] }
                    expected["render"] = (expected["render"] as! [Int]).map { i -> [Any] in
                        var row = values[i] as! [Any]; row[7] = (row[7] as! Double)*Double(tick); return row
                    }
                    try compare(expected, snapshot(world,rng), at: "\(file.lastPathComponent)[\(tick)ms]")
                    samples += 1
                }
            }
        }
        print("houseBehaviourGoldenFixtures: compared \(files.count) JS fixtures, \(samples) samples (tolerance 1e-6)")
    }
    private func snapshot(_ w: HouseBehaviour, _ rng: HouseRandom) -> [String: Any] {
        let null = NSNull()
        func value<T>(_ x: T?) -> Any { x as Any? ?? null }
        let sprites: [[Any]] = w.sprites.map { sp in
            let b = sp.behaviour
            let goal: Any = sp.goal.map { [$0.room,$0.cat,$0.i,$0.p] as [Any] } ?? null
            let errand: Any = b.errand.map { [$0.room,$0.cat,value($0.dur),$0.until.isFinite ? $0.until as Any : null,value($0.since),value($0.t0),$0.lost] as [Any] } ?? null
            let fall: Any = sp.fall.map { f -> [Any] in
                let p = w.parachute(sp)!
                return [f.x.isFinite ? f.x as Any : null,f.y.isFinite ? f.y as Any : null,f.t0,f.seed,p.phase,p.open,p.position.map { $0.isFinite ? $0 as Any : null }]
            } ?? null
            let hold: Any = b.handover.map { [$0.parent,$0.vanish,$0.stage,$0.t0,value($0.t1)] as [Any] } ?? null
            return [sp.id,value(sp.room),sp.homeRoom,sp.x,sp.y,sp.z,goal,errand,value(sp.state),sp.leaving,sp.exit,fall,
                    sp.alpha,sp.fade,sp.small,b.vendor,sp.moving,value(sp.seated),value(sp.waving),sp.path.count,
                    b.restOnRoof,b.restInYard,value(b.towel),hold,b.handed,b.popped]
        }
        let beforeRender = rng.state
        let render: [[Any]] = w.renderFrames().map { f in
            [f.id,f.pose,f.facing,f.position.map { $0.isFinite ? $0 as Any : null },f.alpha,f.small,f.vendor,
             f.animationTime,value(f.parachutePhase),f.parachuteOpen,f.seated,f.waving,value(f.towelUntil)]
        }
        XCTAssertEqual(beforeRender,rng.state,"render snapshot must not consume random numbers")
        let cabins: [[Any]] = w.sim.cabins.map { [$0.geometry.id,$0.z,$0.level < 0 ? null : $0.level as Any,$0.state,$0.t,$0.stop.map { $0 < 0 ? null : $0 as Any } ?? null] }
        return ["sprites":sprites,"render":render,"cabins":cabins,"growth":w.growth.map { [$0.project,$0.n,$0.ids,$0.level] as [Any] },"rng":rng.state,
                "puffs":w.puffs.map { [$0.room,$0.x,$0.y,$0.z,$0.t0,$0.col,$0.seed] as [Any] },
                "papers":w.papers.map { [$0.from,$0.to,$0.t0] as [Any] }]
    }
    private struct Mismatch: Error, CustomStringConvertible { let description: String }
    private func compare(_ expected: Any, _ actual: Any, at path: String) throws {
        func fail(_ detail: String) throws {
            if ProcessInfo.processInfo.environment["NOTCH_BEH_ALL"] != nil { print("MISMATCH", path + ": " + detail); return }
            throw Mismatch(description: path + ": " + detail)
        }
        if let a = expected as? [String: Any], let b = actual as? [String: Any] {
            guard Set(a.keys) == Set(b.keys) else { return try fail("keys \(a.keys.sorted()) != \(b.keys.sorted())") }
            for k in a.keys.sorted() { try compare(a[k]!, b[k]!, at: path + "." + k) }
        } else if let a = expected as? [Any], let b = actual as? [Any] {
            guard a.count == b.count else { return try fail("count \(a.count) != \(b.count)") }
            for i in a.indices { try compare(a[i], b[i], at: "\(path)[\(i)]") }
        } else if let a = expected as? NSNumber, let b = actual as? NSNumber {
            let ab = CFGetTypeID(a) == CFBooleanGetTypeID(), bb = CFGetTypeID(b) == CFBooleanGetTypeID()
            guard ab == bb else { return try fail("boolean/number type") }
            guard ab ? a == b : a.doubleValue.isFinite && b.doubleValue.isFinite && abs(a.doubleValue - b.doubleValue) <= 1e-6 else { return try fail("\(a) != \(b)") }
        } else if expected is NSNull, actual is NSNull { return }
        else if let a = expected as? String, let b = actual as? String, a.utf16.elementsEqual(b.utf16) { return }
        else { try fail("\(expected) != \(actual)") }
    }
}
