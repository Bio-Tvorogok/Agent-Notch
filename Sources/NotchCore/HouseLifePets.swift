import Foundation

public final class HouseDogGreeting {
    public var id: String, stage = "meet"
    public var t0: Double, t1: Double?, re = 0.0
    public init(id: String, t0: Double) { self.id = id; self.t0 = t0 }
}

public final class HouseFetchBall {
    public var by: String, n = 0, of: Int
    public var t0: Double, ms = 0.0, t1: Double?
    public var from: [Double], to: [Double], held = false, stage = "come"
    public init(by: String, of: Int, t0: Double) {
        self.by = by; self.of = of; self.t0 = t0
        from = [14.0, 6.75]; to = [14.0, 6.75]
    }
}

private let houseCatDesk: [String: Double] = ["bedroom": 14, "server": 14, "library": 13.5, "greenhouse": 14.5, "arcade": 14]
// Right-wall, non-vent windows, in the same order as each frozen page theme.
private let houseCatWindows: [String: [[Double]]] = [
    "bedroom": [[(2.2 + 4.4) / 2, 0.22, 24 - 1.5]],
    "server": [[(4.9 + 6.4) / 2, 0.22, 38 - 1.5]],
    "library": [[(3.5 + 6.0) / 2, 0.22, 22 - 1.5]],
    "kitchen": [[(2.6 + 4.6) / 2, 0.22, 32 - 1.5]],
]
private let housePitch = [14.0, 6.75, 0.0], housePitchDog = [14.7, 6.4]
private func petClamp(_ n: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, n)) }

extension HouseBehaviour {
    public func catHome() -> (String, [Double])? {
        guard let r = shared("roof") else { return nil }
        let home = HouseRoutes.theme("roof").spots["cat"]?.first
        let homeRoll = sim.random()
        guard homeRoll < (life.dark > 0.5 ? 0.8 : 0.25), let home else { return nil }
        return (r, home)
    }

    public func catNaps() -> [(String, [Double])] {
        var out: [(String, [Double])] = []
        for r in layout.rooms {
            for p in sim.spots(r.key)["sleep"] ?? [] { out.append((r.key, p)) }
            for p in houseCatWindows[r.theme] ?? [] { out.append((r.key, p)) }
        }
        return out
    }

    public func catGo(_ c: HouseSprite, _ room: String, _ p: [Double], _ want: String) {
        guard p.count >= 3, p.allSatisfy(\.isFinite) else { return }
        sim.setGoal(c, .init(room: room, p: p, cat: "cat", i: -1))
        c.life.want = want; c.life.pose = "sit"
        if p[2] > 3 && !c.path.isEmpty {
            let r = sim.room(room)
            c.path.insert(.init(r: room, p: [petClamp(p[0] + 0.2, 0.4, r.NX - 0.4), petClamp(p[1] + 1.0, 0.4, r.NY - 0.4), 0]), at: c.path.count - 1)
        }
    }

    public func catThink(_ c: HouseSprite, _ t: Double) {
        if let id = c.life.deskOf {
            if let a = find(id), a.state == "working", a.path.isEmpty, a.goal?.cat == "work" {
                // The desk still belongs to a working agent.
            } else {
                c.life.deskOf = nil; c.life.next = min(c.life.next, t)
            }
        }
        if c.path.isEmpty, let want = c.life.want { c.life.pose = want }
        if !c.path.isEmpty || t < c.life.next || c.onBridge != nil { return }
        if !anyWorking() {
            if c.life.pose != "nap" && c.life.want != "nap" {
                let naps = catNaps()
                if !naps.isEmpty, let (r, p) = catHome() ?? scPick(naps) {
                    catGo(c, r, p, "nap"); c.life.deskOf = nil
                }
            }
            c.life.next = t + 4000; return
        }
        let roll = sim.random()
        let desks = sprites.filter { a in
            guard a.kind == "agent", a.state == "working", let room = a.room,
                  a.path.isEmpty, a.goal?.cat == "work", a.z > 3 else { return false }
            let theme = sim.room(room).theme
            return houseCatDesk[theme] != nil && !(theme == "library" && a.goal?.i == 1)
                && !sprites.contains { $0.kind == "cat" && $0 !== c && HouseRoutes.same($0.life.deskOf,a.id) }
        }
        if !desks.isEmpty && roll < 0.3, let a = scPick(desks), let r = a.room, let height = houseCatDesk[sim.room(r).theme] {
            catGo(c, r, [a.x + 0.15, a.y - 1.15, height + 0.6], "sit")
            c.life.deskOf = a.id; c.life.next = t + 12000 + sim.random() * 9000
        } else if roll < 0.75 {
            let naps = catNaps()
            if naps.isEmpty { c.life.next = t + 4000; return }
            if let (r, p) = catHome() ?? scPick(naps) { catGo(c, r, p, "nap") }
            c.life.deskOf = nil; c.life.next = t + 18000 + sim.random() * 22000
        } else if let room = scPick(layout.rooms), var p = scPick((sim.spots(room.key)["pace"] ?? []) + [sim.hub(room.key)]) {
            p[0] = petClamp(p[0] + (sim.random() - 0.5), 0.4, room.NX - 0.4); p[2] = 0
            catGo(c, room.key, p, "sit"); c.life.deskOf = nil; c.life.next = t + 6000 + sim.random() * 7000
        }
    }

    public func ballAt(_ bl: HouseFetchBall, _ t: Double) -> [Double] {
        guard bl.to.count >= 2, bl.to.allSatisfy(\.isFinite) else { return [0, 0, 0] }
        if bl.held { return bl.to }
        let ground = [bl.to[0], bl.to[1], 0]
        // A zero-length throw lands at once (the page uses k = 1).
        guard bl.ms.isFinite, bl.ms > 0, t.isFinite, bl.t0.isFinite,
              bl.from.count >= 2, bl.from.allSatisfy(\.isFinite) else { return ground }
        let k = min(1, (t - bl.t0) / bl.ms)
        let point = [bl.from[0] + (bl.to[0] - bl.from[0]) * k, bl.from[1] + (bl.to[1] - bl.from[1]) * k,
                     6 + sin(k * .pi) * 26 * (1 - k * 0.3) - k * 6]
        return point.allSatisfy(\.isFinite) ? point : ground
    }

    public func dogGo(_ d: HouseSprite, _ room: String, _ p: [Double], _ pose: String, _ speed: Double = 1) {
        guard p.count >= 2, p.allSatisfy(\.isFinite), speed.isFinite else { return }
        sim.setGoal(d, .init(room: room, p: [p[0], p[1], 0], cat: "dog", i: -1))
        d.life.want = pose; d.speed = speed; d.life.wag = false
    }

    public func dogGreet(_ a: HouseSprite) {
        if let d = find("__dog"), d.life.fireOf == nil {
            d.life.greet = .init(id: a.id, t0: time); d.life.next = 0
        }
    }

    public func dogFree(_ d: HouseSprite) -> Bool { d.path.isEmpty && d.onBridge == nil && d.room != nil }

    public func dogThink(_ d: HouseSprite, _ t: Double) {
        if d.path.isEmpty, let want = d.life.want { d.life.pose = want }
        if d.onBridge != nil || d.room == nil { return }
        let fire = sprites.first { $0.life.fire != nil && $0.room != nil && $0.onBridge == nil && $0.alpha > 0.5 }
        if let fire, let room = fire.room {
            if !HouseRoutes.same(d.life.fireOf,fire.id) || (dogFree(d) && !HouseRoutes.same(d.room,room) && t > d.life.re) {
                d.life.fireOf = fire.id; d.life.greet = nil; dropBall(d); d.life.re = t + 3000
                let r = sim.room(room)
                dogGo(d, room, [petClamp(fire.x + 1.3, 0.4, r.NX - 0.4), petClamp(fire.y + 0.9, 0.4, r.NY - 0.4)], "bark", 1.6)
            }
            d.life.look = [fire.x, fire.y]; return
        }
        if d.life.fireOf != nil {
            d.life.fireOf = nil; d.life.look = nil; d.life.next = t + 1500; d.life.pose = "sit"; d.life.want = "sit"
        }
        let bath = shared("bath")
        if let gr = d.life.greet {
            let a = find(gr.id), e = a?.behaviour.errand
            let washing = e.map { ["shower", "dry", "wash"].contains($0.cat) } ?? false
            if a == nil || bath == nil || (!washing && gr.stage != "meet") || t - gr.t0 > 120000 {
                d.life.greet = nil; d.life.wag = false; d.life.next = t + 2000
            } else if let a, gr.stage == "meet" {
                let near = a.room != nil && HouseRoutes.same(d.room,a.room) && houseBehaviourHypot([a.x - d.x, a.y - d.y]) < 1.6
                if near || t - gr.t0 > 25000 { gr.stage = "along"; d.life.pose = "sit"; d.life.wag = true; gr.t1 = t }
                else if dogFree(d) || (t > gr.re && a.room != nil && !HouseRoutes.same(d.room,a.room) && a.onBridge == nil) {
                    gr.re = t + 2500
                    if let room = a.room, a.onBridge == nil {
                        let r = sim.room(room)
                        dogGo(d, room, [petClamp(a.x + 0.6, 0.4, r.NX - 0.4), petClamp(a.y + 0.6, 0.4, r.NY - 0.4)], "sit", 1.6)
                    }
                }
                if !washing && a.state != "done" { d.life.greet = nil }
                return
            } else if gr.stage == "along" && t - (gr.t1 ?? .nan) > 1200, let bath {
                gr.stage = "wait"; dogGo(d, bath, [3.5, 2.25], "sit", 1.3)
            }
            if gr.stage == "wait" && dogFree(d), let a { d.life.wag = true; d.life.look = [a.x, a.y] }
            return
        }
        d.life.look = nil
        if life.ball != nil { fetchStep(d, t); return }
        if !d.path.isEmpty || t < d.life.next { return }
        let working = sprites.contains { $0.kind == "agent" && $0.state == "working" && !$0.leaving }
        if life.dark > 0.5 || !working {
            guard let p = sim.spots("__yard")["dog"]?.first, p.count >= 2 else { return }
            if d.room != "__yard" || houseBehaviourHypot([d.x - p[0], d.y - p[1], d.z]) > 0.01 { dogGo(d, "__yard", p, "nap") }
            else { d.life.want = "nap"; d.life.pose = "nap"; d.life.wag = false }
            d.life.next = t + 30000 + sim.random() * 30000; return
        }
        let thrower = d.room == "__yard" ? pickThrower(d) : nil
        if let thrower, sim.random() < 0.55 { startFetch(d, thrower, t); return }
        let roll = sim.random()
        if roll < 0.6 || bath == nil {
            if let p = scPick(sim.spots("__yard")["romp"] ?? []) { dogGo(d, "__yard", p, "sit") }
            d.life.next = t + 6000 + sim.random() * 8000
        } else if roll < 0.8 {
            if let p = sim.spots("__yard")["dog"]?.first { dogGo(d, "__yard", p, "nap") }
            d.life.next = t + 15000 + sim.random() * 15000
        } else if let room = shared("kitchen") ?? bath {
            let r = sim.room(room), hub = sim.hub(room)
            dogGo(d, room, [petClamp(hub[0] + 0.8, 0.4, r.NX - 0.4), petClamp(hub[1] + 0.6, 0.4, r.NY - 0.4)], "sit")
            d.life.next = t + 9000 + sim.random() * 6000
        }
    }

    public func pickThrower(_ d: HouseSprite) -> HouseSprite? {
        let candidates = sprites.filter { o in
            (o.kind == "home" || (o.kind == "agent" && o.behaviour.agent?.state == "done"))
                && o.room == "__yard" && o.path.isEmpty && o.onBridge == nil && o.alpha > 0.6
                && !HouseRoutes.same(life.swinger,o.id) && !hasHold(o) && !o.leaving && !o.exit
                && (o.behaviour.errand?.dur ?? 0) == 0
        }
        return candidates.isEmpty ? nil : scPick(candidates)
    }

    public func startFetch(_ d: HouseSprite, _ th: HouseSprite, _ t: Double) {
        life.ball = .init(by: th.id, of: 2 + Int(floor(sim.random() * 3)), t0: t)
        th.life.hold = .init(kind: "fetch", t0: t, errand: th.behaviour.errand, state: "idle")
        th.behaviour.errand = nil; th.state = "idle"
        sim.setGoal(th, .init(room: "__yard", p: housePitch, cat: "pitch", i: -1))
        dogGo(d, "__yard", housePitchDog, "sit", 1.5)
    }

    public func dropBall(_ d: HouseSprite) {
        let th = life.ball.flatMap { find($0.by) }
        life.ball = nil; d.life.ball = false
        if let th, th.life.hold?.kind == "fetch" { releaseHold(th) }
    }

    public func fetchStep(_ d: HouseSprite, _ t: Double) {
        guard let bl = life.ball else { return }
        let th = find(bl.by)
        let invalidThrower = th.map { $0.life.hold?.kind != "fetch" || (bl.stage != "come" && !$0.path.isEmpty)
            || t - ($0.life.hold?.t0 ?? .nan) > 90000 } ?? true
        if invalidThrower
            || (d.room != "__yard" && d.onBridge == nil && d.path.isEmpty)
        {
            dropBall(d)
            if let th, th.life.hold?.kind == "fetch" { releaseHold(th) }
            d.life.next = t + 3000; return
        }
        guard let th else { return }
        if bl.stage == "come" {
            if dogFree(d) && th.path.isEmpty { bl.stage = "throw"; bl.t1 = t + 700; d.life.pose = "sit"; d.life.wag = true; d.life.look = [th.x, th.y] }
            return
        }
        if bl.stage == "throw" && t > (bl.t1 ?? .nan) {
            let to = [14.3 + sim.random() * 1.9, 1.6 + sim.random() * 3.0]
            bl.from = [th.x, th.y]; bl.to = to; bl.t0 = t
            bl.ms = 700 + houseBehaviourHypot([to[0] - th.x, to[1] - th.y]) * 140; bl.held = false; bl.stage = "fly"
            th.life.toss = t; dogGo(d, "__yard", to, "sit", 1.8); return
        }
        if bl.stage == "fly" && dogFree(d) && t > bl.t0 + bl.ms {
            bl.stage = "back"; bl.held = true; d.life.ball = true; dogGo(d, "__yard", housePitchDog, "sit", 1.5); return
        }
        if bl.stage == "back" && dogFree(d) {
            d.life.ball = false; bl.n += 1; d.life.wag = true; d.life.look = [th.x, th.y]
            if bl.n >= bl.of { life.ball = nil; releaseHold(th); d.life.next = t + 5000 }
            else { bl.stage = "throw"; bl.t1 = t + 900 }
        }
    }
}
