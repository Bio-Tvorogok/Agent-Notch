import Foundation
import CoreFoundation
#if canImport(NotchCore)
import NotchCore
#endif

struct HouseRouteChecks {
    // Catches changed BFS ordering, lost jump nodes, incorrect speeds/timing,
    // lift dispatch/capacity and stair RNG consumption against the real JS.
    func goldenFixtures() throws {
        let js = Process()
        js.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        js.arguments = ["node", "Tests/HouseChecks/route-fixtures.mjs", "--check"]
        try js.run(); js.waitUntilExit()
        XCTAssertEqual(js.terminationStatus, 0, "current JS must reproduce the committed route fixtures")
        let dir = URL(fileURLWithPath: "Tests/Fixtures/house-routes")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(files.map(\.lastPathComponent), ["02-islands.json", "05-islands-frames.json", "05-islands.json", "05-towers.json", "14-islands.json"])
        var routes = 0, samples = 0
        for file in files {
            let f = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let input = f["input"] as! [String: Any], output = f["output"] as! [String: Any]
            let layout = HouseLayout.make(projects: input["projects"] as! [String],
                                          layout: HouseLayout.Style(rawValue: input["layout"] as! String)!,
                                          canvas: .init(width: 1440, height: 900))
            if !(output["routes"] as! [Any]).isEmpty { try compare(output["catalog"]!, json(HouseRoutes.themes), at: file.lastPathComponent + ".catalog") }
            let world = HouseSim(layout: layout)
            let origins = output["origins"] as! [[String: Any]]
            let nodes = output["nodes"] as! [Any]
            for (i, value) in (output["routes"] as! [[Any]]).enumerated() {
                let a = origins[value[0] as! Int], b = origins[value[1] as! Int]
                let sprite = HouseSprite(id: "route", room: a["room"] as! String, point: a["p"] as! [Double], seed: 0.371)
                world.route(sprite, to: b["room"] as! String, point: b["p"] as! [Double])
                let expected = (value[2] as! [Int]).map { nodes[$0] }
                try compare(expected, json(sprite.path), at: "\(file.lastPathComponent).routes[\(i)]")
                routes += 1
            }
            let sim = input["sim"] as! [String: Any], rng = HouseRandom(seed: UInt32(sim["seed"] as! Int))
            let moving = HouseSim(layout: layout, random: { rng.nextDouble() })
            for si in sim["stairInit"] as? [[String: Any]] ?? [] {
                guard let l = moving.links.first(where: { $0.geometry.id == si["id"] as? String }) else { XCTFail("no stair \(si["id"] ?? "")"); continue }
                if let v = si["aim"] as? Int { l.aim = v }
                if let v = si["lift"] as? Double { l.lift = v }
                if let v = si["next"] as? Double { l.next = v }
            }
            for item in sim["setup"] as! [[String: Any]] { _ = try spawn(item, in: moving) }
            let events = sim["events"] as! [[String: Any]]
            let trace = output["trace"] as! [[Any]], eventPaths = output["eventPaths"] as! [[Any]]
            var eventIndex = 0, fired = Set<Int>()
            // The page's order: an event fires on the first tick or frame whose clock has
            // reached its time and, with `when`, whose sprite is in that state.
            func ready(_ when: String?, _ sp: HouseSprite) -> Bool {
                switch when {
                case "limbo": return sp.room == nil && sp.onBridge == nil
                case "lift": return sp.onBridge?.kind == "lift"
                case "bridge": return sp.onBridge != nil && sp.onBridge?.kind != "lift"
                default: return true
                }
            }
            func fire(_ clock: Double) throws {
                for (k, e) in events.enumerated() where !fired.contains(k) && (e["at"] as! NSNumber).doubleValue <= clock {
                    let id = e["id"] as! String, spawnItem = e["spawn"] as? [String: Any]
                    var found = moving.sprites.first { $0.id == id }
                    if spawnItem == nil && found == nil { continue }
                    if let found, !ready(e["when"] as? String, found) { continue }
                    fired.insert(k)
                    if var item = spawnItem { item["id"] = id; found = try spawn(item, in: moving) }
                    guard let sp = found else { continue }
                    if e["orphan"] as? Bool == true {
                        sp.onBridge = .init(kind: "bridge", pair: moving.links.first?.geometry.id ?? "orphan", u: 0.5)
                        sp.room = nil; sp.path = []
                    }
                    if let g = e["goal"] as? [String: Any] { setGoal(sp, g, in: moving) }
                    try compare(eventPaths[eventIndex], [clock, id, try json(sp.path)], at: "\(file.lastPathComponent).eventPaths[\(eventIndex)]")
                    eventIndex += 1
                }
            }
            try compare(trace[0][1], snapshot(moving, rng), at: file.lastPathComponent + ".trace[0]")
            if let frames = sim["frames"] as? [String: Any] {
                // frame() of the page: advance(frame:) with the raw deltas, a negative first one and a 4 s stall.
                let deltas = (frames["deltas"] as! [NSNumber]).map(\.doubleValue), every = frames["sample"] as! Int
                var clock = 0.0, next = 1
                for (i, raw) in deltas.enumerated() {
                    clock += max(0, raw)
                    try fire(clock)
                    moving.advance(frame: raw)
                    if i % every == every - 1 {
                        try compare(trace[next][1], snapshot(moving, rng), at: "\(file.lastPathComponent).trace[frame \(i)]")
                        next += 1; samples += 1
                    }
                }
                XCTAssertEqual(next, trace.count)
                XCTAssertTrue(deltas.first! < 0 && deltas.contains { $0 >= 4000 }, "the frame trace needs its negative first delta and its stall")
            } else {
                for tick in stride(from: 50, through: 60000, by: 50) {
                    try fire(Double(tick))
                    moving.step(dt: 50)
                    if tick % 250 == 0 {
                        try compare(trace[tick / 250][1], snapshot(moving, rng), at: "\(file.lastPathComponent).trace[\(tick)ms]")
                        samples += 1
                    }
                }
            }
            XCTAssertEqual(eventIndex, eventPaths.count)
        }
        try HouseRobustnessChecks().all()
        print("houseRouteGoldenFixtures: compared \(files.count) JS fixtures, \(routes) paths, \(samples) movement samples (tolerance 1e-6)")
    }

    private func spawn(_ item: [String: Any], in world: HouseSim) throws -> HouseSprite {
        let o = item["options"] as! [String: Any]
        let sp = world.spawn(id: item["id"] as! String, room: item["room"] as! String, kind: o["kind"] as? String ?? "agent", small: o["small"] as? Bool ?? false)
        if let x = o["x"] as? Double { sp.x = x }; if let y = o["y"] as? Double { sp.y = y }; if let z = o["z"] as? Double { sp.z = z }
        if let alpha = o["alpha"] as? Double { sp.alpha = alpha }; if let fade = o["fade"] as? Double { sp.fade = fade }
        sp.context = o["context"] as? Double; sp.speed = o["speed"] as? Double
        sp.frozenUntil = o["frozenUntil"] as? Double; sp.exit = o["exit"] as? Bool ?? false
        sp.leaving = o["leaving"] as? Bool ?? false
        if let path = item["path"] { sp.path = try JSONDecoder().decode([HouseRouteNode].self, from: JSONSerialization.data(withJSONObject: path)) }
        if let goal = item["goal"] as? [String: Any] { setGoal(sp, goal, in: world) }
        return sp
    }

    private func setGoal(_ sp: HouseSprite, _ g: [String: Any], in world: HouseSim) {
        world.setGoal(sp, .init(room: g["room"] as! String, p: g["p"] as! [Double], cat: g["cat"] as? String ?? "fixture", i: g["i"] as? Int ?? -1))
    }

    private func snapshot(_ world: HouseSim, _ rng: HouseRandom) -> [String: Any] {
        let null = NSNull()
        let sprites: [[Any]] = world.sprites.map { sp in
            let bridge: Any = sp.onBridge.map { [$0.kind, $0.pair, $0.u, $0.forward as Any? ?? null] as [Any] } ?? null
            let lift: Any = sp.path.first.flatMap { n -> [Any]? in
                guard let lift = n.lift else { return nil }
                return [lift.from, lift.to, n.since as Any? ?? null, n.cab as Any? ?? null]
            } ?? null
            let fall: Any = sp.fall.map { [$0.x, $0.y, $0.t0, $0.seed] } ?? null
            return [sp.id, sp.room as Any? ?? null, sp.x, sp.y, sp.z, sp.alpha, sp.fade, sp.moving,
                    sp.seated as Any? ?? null, sp.waving as Any? ?? null, sp.state as Any? ?? null,
                    sp.path.count, bridge, lift, fall]
        }
        let cabins: [[Any]] = world.cabins.map { [$0.geometry.id, $0.z, $0.level, $0.state, $0.t, $0.stop as Any? ?? null] }
        let stairs: [[Any]] = world.links.filter { $0.geometry.kind == "stair" }.map { l in
            let turn: Any = l.turn.map { [$0.a0, $0.a1, $0.to, $0.t0, $0.ms] as [Any] } ?? null
            return [l.geometry.id, l.geometry.ang!, l.lift, l.aim, turn, l.next, l.since as Any? ?? null]
        }
        return ["clock": world.time, "sprites": sprites, "cabins": cabins, "stairs": stairs, "rng": rng.state]
    }

    private func json<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }
    private struct Mismatch: Error, CustomStringConvertible { let description: String }
    private func compare(_ expected: Any, _ actual: Any, at path: String) throws {
        func fail(_ detail: String) throws { throw Mismatch(description: path + ": " + detail) }
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
