import Foundation

/// The page's easter eggs. Coordinates and clocks use canvas pixels and milliseconds.
/// Enabling this layer is explicit so the isolated behaviour fixtures keep their RNG stream.
public final class HouseEggSpriteState {
    var seen = false
    public internal(set) var golden = false
}

public final class HouseEggs {
    public struct Holidays: Equatable {
        public var xmas, newYear, halloween, valentine, fools: Bool
        public init(month: Int, day: Int) {
            xmas = (month == 12 && day >= 20) || (month == 1 && day <= 7)
            newYear = month == 1 && day == 1; halloween = month == 10 && day >= 25
            valentine = month == 2 && day == 14; fools = month == 4 && day == 1
        }
    }
    public struct Saved: Codable {
        public var next: [String: Double] = [:], ghostDay = "", seenDay = "", count = 0
        public var ids: [String] = [], gold: [String] = []
        public init() {}
    }
    public struct Whale { public var t0: Double, dir: Double, y: Double, seed: Double }
    public struct Ghost { public var t0: Double, dir: Double }
    public final class UFO {
        public let t0: Double, target: HouseSprite, dir: Double
        public var hold = true, lift = 0.0, beam = 0.0, x = 0.0, y = 0.0, at: [Double]?
        init(t0: Double, target: HouseSprite, dir: Double) { self.t0 = t0; self.target = target; self.dir = dir }
    }
    public struct Hi5 { public let a, b: HouseSprite; public let t0: Double; public let reroute: Bool }
    public struct Heart { public var x, y, t0, life, seed: Double; public var col: String; public var small: Bool }
    public struct Letter { public var t0: Double, room: String, tip: String }
    public static let tips = [
        "Наведи курсор на Clawd — увидишь, над чем работает агент.", "Клик по Clawd открывает его сессию.",
        "Жёлтый «!» над головой: агент ждёт твоего ответа.", "Дым и огонь — агент застрял на ошибке, загляни к нему.",
        "Закончив, Clawd идёт в душ, на крышу или во двор.", "Клик по комнате приближает её, Esc — обратно к дому.",
        "Сабагент отдаёт результат родителю и исчезает в облачке.", "После git commit Clawd несёт письмо в этот ящик.",
        "Сонный, медленный Clawd — его контекст почти заполнен."]
    private unowned let b: HouseBehaviour
    public var date: () -> Date = Date.init
    public var calendar = Calendar.current
    public var save: (Saved) -> Void = { _ in }
    public var saved = Saved()
    public var enabled = true, extra = false
    public var dark = 0.0
    public private(set) var holidays = Holidays(month: 10, day: 15)
    public var sun: [Double]?, clouds: [[Double]] = []
    public private(set) var shadesUntil = 0.0, rain: [Int: Double] = [:], purrUntil = 0.0
    public private(set) var whale: Whale?, ghost: Ghost?, ufo: UFO?, party = false, partyUntil = 0.0
    public private(set) var highFives: [Hi5] = [], hearts: [Heart] = [], letter: Letter?
    private var hi5Next: [String: Double] = [:], catClicks: [Double] = []
    private var ufoTry = 0.0, fwNext = 0.0, heartNext = 0.0, purrNext = 0.0, tipN = 0
    public init(behaviour: HouseBehaviour) { b = behaviour }
    private func rnd() -> Double { b.sim.random() }
    private func pick<T>(_ a: [T]) -> T { a[min(a.count - 1, Int(rnd() * Double(a.count)))] }
    private func dayKey(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    private func schedule(_ name: String) { saved.next[name] = date().timeIntervalSince1970 * 1000 + (2 + rnd() * 3) * 86400000; save(saved) }
    private func due(_ name: String) -> Bool {
        if saved.next[name] == nil { schedule(name) }
        return date().timeIntervalSince1970 * 1000 >= saved.next[name]!
    }
    public func sky(at t: Double) {
        let c = calendar.dateComponents([.month, .day], from: date())
        holidays = Holidays(month: c.month ?? 1, day: c.day ?? 1)
        guard enabled else { return }
        if !extra && whale == nil && due("whale") { schedule("whale"); newWhale(t) }
        if let w = whale {
            let x = whaleX(w, at: t), W = b.layout.view.width
            if w.dir > 0 ? x > W + 120 : x < -120 { whale = nil }
        }
        rain = rain.filter { $0.key < clouds.count && t <= $0.value }
    }
    public func whaleX(_ w: Whale, at t: Double) -> Double {
        let span = b.layout.view.width + 240
        return w.dir > 0 ? -100 + (t-w.t0)*span/110000 : b.layout.view.width + 100 - (t-w.t0)*span/110000
    }
    private func newWhale(_ t: Double) {
        whale = Whale(t0: t, dir: rnd() < 0.5 ? 1 : -1, y: b.layout.view.height * (0.12 + rnd()*0.1), seed: rnd()*9)
    }
    public func position(_ sp: HouseSprite) -> [Double]? {
        if let ob = sp.onBridge, let l = b.layout.links.first(where: { $0.id == ob.pair }) {
            let w = (sp.seed-0.5)*0.36
            if l.kind == "stair" {
                let d = ob.u*l.len, a = l.ang ?? 0, k = min(Double(l.steps ?? 13), max(0, ceil(ob.u*Double(l.steps ?? 13)-0.2)))
                return world(l.A[0]+cos(a)*d-sin(a)*w*0.8, l.A[1]+sin(a)*d+cos(a)*w*0.8, (l.z0 ?? 0)+k*(l.rise ?? 0)/Double(l.steps ?? 13))
            }
            let x = l.A[0]+(l.B[0]-l.A[0])*ob.u, y = l.A[1]+(l.B[1]-l.A[1])*ob.u
            return world(x+(l.axis == "y" ? w : 0), y+(l.axis == "x" ? w : 0), (l.z ?? 0)-6)
        }
        guard let key = sp.room else { return nil }
        let r = b.sim.room(key)
        return [r.ox+(sp.x-sp.y)*16, r.oy+r.drop+(sp.x+sp.y)*8-sp.z*2]
    }
    private func world(_ x: Double, _ y: Double, _ z: Double) -> [Double] {
        let f = b.layout.worldFrame
        return [f.ox+(x-y)*16, f.oy+f.drop+(x+y)*8-z*2]
    }
    private func count() {
        let day = dayKey(date())
        if saved.seenDay != day { saved.seenDay = day; saved.count = 0; saved.ids = []; saved.gold = [] }
        var dirty = false
        for sp in b.sprites where sp.kind == "agent" && sp.behaviour.agent != nil && !sp.eggs.seen {
            sp.eggs.seen = true
            let agentID = sp.behaviour.agent!.id
            if saved.gold.contains(agentID) { sp.eggs.golden = true }
            if saved.ids.contains(agentID) { continue }
            saved.ids.append(agentID); if saved.ids.count > 3000 { saved.ids.removeFirst(1000) }
            saved.count += 1
            if saved.count % 100 == 0 { sp.eggs.golden = true; saved.gold.append(agentID) }
            dirty = true
        }
        if dirty { save(saved) }
    }
    private func eligible(_ s: HouseSprite) -> Bool {
        s.kind != "cat" && s.kind != "dog" && s.room != nil && s.onBridge == nil && s.alpha > 0.6 && s.fall == nil && !s.leaving && !s.exit && s.life.hold == nil && s.behaviour.handover == nil
    }
    private func startUFO(_ t: Double, forced: Bool) -> Bool {
        var a = b.sprites.filter { eligible($0) && $0.path.isEmpty && ($0.state == "done" || $0.state == "idle-sleep") }
        if a.isEmpty && forced { a = b.sprites.filter { eligible($0) && $0.path.isEmpty } }
        if a.isEmpty && forced { a = b.sprites.filter(eligible) }
        let open = a.filter { let theme = b.sim.room($0.room!).theme; return theme == "roof" || theme == "yard" }
        if !open.isEmpty { a = open }
        guard !a.isEmpty else { return false }
        ufo?.target.frozen = false
        ufo = UFO(t0: t, target: pick(a), dir: rnd() < 0.5 ? 1 : -1); return true
    }
    private func stepUFO(_ t: Double) {
        guard let u = ufo else { return }
        let e = t-u.t0, tg = u.target
        if b.sprites.contains(where: { $0 === tg }), let p = position(tg) { u.at = p }
        guard let p = u.at, e <= 10400 else { tg.frozen = false; ufo = nil; return }
        u.x = p[0]; u.y = max(28, p[1]-104)
        if e < 3200 { let k = 1-pow(1-e/3200,3); u.x -= u.dir*(1-k)*b.layout.view.width*0.75; u.y -= (1-k)*60 }
        else if e > 7400 { let k = pow((e-7400)/3000,2); u.x += u.dir*k*b.layout.view.width*0.85; u.y -= k*120 }
        u.hold = e < 7400; tg.frozen = u.hold
        let l = e < 3700 ? 0 : e < 4700 ? (e-3700)/1000 : e < 5900 ? 1 : e < 6900 ? 1-(e-5900)/1000 : 0
        u.lift = houseRound(l*32+(l > 0.9 ? sin(e/180)*2 : 0))
        u.beam = e < 3200 ? 0 : e < 3700 ? (e-3200)/500 : e < 6900 ? 1 : e < 7400 ? 1-(e-6900)/500 : 0
    }
    private func hi5(_ a: HouseSprite, _ c: HouseSprite, _ t: Double, reroute: Bool) {
        a.frozenUntil = t+1500; c.frozenUntil = t+1500; hi5Next[a.id] = t+40000; hi5Next[c.id] = t+40000
        highFives.append(Hi5(a: a, b: c, t0: t, reroute: reroute))
    }
    private func highFives(_ t: Double) {
        for h in highFives where t >= h.t0+1500 {
            if h.reroute { for s in [h.a,h.b] { if let g = s.goal { b.sim.setGoal(s,g) } } }
        }
        highFives.removeAll { t >= $0.t0+1500 }
        let a = b.sprites.filter { s in
            s.kind == "agent" && s.alpha >= 0.6 && s.life.hold == nil && s.fall == nil && !s.leaving && !s.exit && t >= (s.frozenUntil ?? 0) && t >= (hi5Next[s.id] ?? 0) && s.state != "done" && s.state != "shower" && s.state != "idle-sleep" && ufo?.target !== s
        }
        for (i,s) in a.enumerated() { for c in a.dropFirst(i+1) {
            guard s.behaviour.vendor != c.behaviour.vendor, (s.onBridge?.pair ?? s.room) == (c.onBridge?.pair ?? c.room), s.moving || c.moving,
                  t >= (s.frozenUntil ?? 0), t >= (c.frozenUntil ?? 0), let p = position(s), let q = position(c) else { continue }
            if abs(p[0]-q[0]) < 20 && abs(p[1]-q[1]) < 10 { hi5(s,c,t,reroute:false) }
        } }
    }
    public func step(at t: Double) {
        guard enabled else { return }
        count()
        party = !extra && (b.sprites.filter { $0.kind == "agent" && !$0.leaving && $0.behaviour.agent?.state == "working" }.count >= 8 || t < partyUntil)
        if ufo == nil && dark > 0.6 && t > ufoTry && !extra { ufoTry = t+5000; if due("ufo") && startUFO(t,forced:false) { schedule("ufo") } }
        stepUFO(t)
        let d = date(), c = calendar.dateComponents([.hour,.minute], from:d)
        if ghost == nil && c.hour == 3 && (c.minute ?? 60) < 5 && !extra && saved.ghostDay != dayKey(d) {
            saved.ghostDay = dayKey(d); save(saved); ghost = Ghost(t0:t,dir:rnd() < 0.5 ? 1 : -1)
        }
        highFives(t)
        if holidays.newYear && c.hour == 0 && (c.minute ?? 60) < 15 && t > fwNext && !b.layout.rooms.isEmpty && !extra {
            fwNext = t+1100+rnd()*900; let room = pick(b.layout.rooms).key
            b.life.fireworks.append(.init(room:room,t0:t,seed:floor(rnd()*5)))
        }
    }
    public func over(at t: Double) {
        guard enabled else { return }
        if holidays.valentine && !b.layout.rooms.isEmpty && t > heartNext && !extra {
            heartNext = t+420; let r = pick(b.layout.rooms), x = rnd()*r.NX, y = rnd()*r.NY, z = rnd()*60*0.8
            hearts.append(Heart(x:r.ox+(x-y)*16,y:r.oy+r.drop+(x+y)*8-z*2,t0:t,life:4200,seed:rnd()*6,col:pick(["#ff5a8a","#ff80b0","#e8405a"]),small:false))
        }
        if t < purrUntil, let cat = b.sprites.first(where: { $0.kind == "cat" }), t > purrNext, let p = position(cat) {
            purrNext = t+380; hearts.append(Heart(x:p[0]+(rnd()-0.5)*6,y:p[1]-9,t0:t,life:2200,seed:rnd()*6,col:"#ff6a9a",small:true))
        }
        hearts.removeAll { t-$0.t0 > $0.life }
        if let g = ghost, t-g.t0 > 26000 { ghost = nil }
        if let l = letter, t-l.t0 > 6500 || mailbox()?.room != l.room { letter = nil }
    }
    @discardableResult public func trigger(_ name: String, at t: Double) -> Bool {
        switch name {
        case "ufo": return startUFO(t,forced:true)
        case "whale": newWhale(t)
        case "ghost": ghost = Ghost(t0:t,dir:rnd() < 0.5 ? 1 : -1)
        case "party": partyUntil = t+60000
        case "golden":
            let a = b.sprites.filter { $0.kind == "agent" && !$0.leaving && !$0.eggs.golden && $0.alpha > 0.5 }
            guard !a.isEmpty else { return false }; pick(a).eggs.golden = true
        case "highfive":
            let a = b.sprites.filter { $0.kind == "agent" && eligible($0) && t >= ($0.frozenUntil ?? 0) }
            let cl = a.filter { $0.behaviour.vendor == "claude" }, cx = a.filter { $0.behaviour.vendor == "codex" }
            guard let s = cl.first(where: { $0.z < 1 }) ?? cl.first, let c = cx.first(where: { $0.room == s.room }) ?? cx.first else { return false }
            if c.room != s.room || hypot(c.x-s.x-0.9,c.y-s.y) > 0.4 || abs(c.z-s.z) > 1 {
                b.puff(c); c.room = s.room; let r = b.sim.room(s.room!); c.x = min(r.NX-0.4,max(0.4,s.x+0.9)); c.y = min(r.NY-0.4,max(0.4,s.y)); c.z = s.z > 3 ? 0 : s.z; c.path = []; b.puffs.append(.init(room:c.room!,x:c.x,y:c.y,z:c.z,t0:t,col:"#fff0a0",seed:rnd()*6))
            }
            hi5(s,c,t,reroute:true)
        default: return false
        }
        return true
    }
    public func mailbox() -> (room: String, rect: [Double])? {
        let yard = b.layout.yard.on, key = yard ? "__bath" : "__kitchen"
        guard b.sim.hasRoom(key) else { return nil }
        let r = b.sim.room(key)
        let v: [Double] = yard ? [3.6,7.2,6,0.75,0.55,5.3] : [9.1,3.05,12,0.75,0.55,5.3]
        var xs:[Double] = [], ys:[Double] = []
        for a in [0.0,v[3]] { for c in [0.0,v[4]] { for d in [0.0,v[5]] {
            let x = v[0]+a, y = v[1]+c, z = v[2]+d
            xs.append(r.ox+(x-y)*16); ys.append(r.oy+r.drop+(x+y)*8-z*2)
        } } }
        return (key,[xs.min()!,ys.min()!,xs.max()!,ys.max()!])
    }
    @discardableResult public func click(x: Double, y: Double, at t: Double, overHouse: Bool) -> Bool {
        guard enabled && !extra else { return false }
        if let p = sun, !overHouse, hypot(x-p[0],y-p[1]) < 14 { shadesUntil = t+60000; return true }
        if let cat = b.sprites.first(where: { $0.kind == "cat" && $0.alpha > 0.5 }), let p = position(cat), abs(x-p[0]) < 9, y > p[1]-12, y < p[1]+3 {
            catClicks = catClicks.filter { t-$0 < 1300 }; catClicks.append(t)
            if catClicks.count >= 3 { catClicks = []; purrUntil = t+4500; purrNext = t; cat.life.next = max(cat.life.next,t+6000) }
            return true
        }
        if let m = mailbox(), x >= m.rect[0]-3, x <= m.rect[2]+3, y >= m.rect[1]-3, y <= m.rect[3]+3 {
            let day = calendar.ordinality(of:.day,in:.year,for:date()) ?? 1
            letter = Letter(t0:t,room:m.room,tip:Self.tips[(day+tipN)%Self.tips.count]); tipN += 1; return true
        }
        if !overHouse { for i in clouds.indices.reversed() { let c = clouds[i]; if x >= c[0] && x <= c[0]+c[2] && y >= c[1]-10 && y <= c[1]+10 { rain[i] = t+5000; return true } } }
        return false
    }
    /// Static sunglasses and daylight holiday props may rest with the house.
    public func isMoving(at t: Double) -> Bool {
        enabled && (!extra && (whale != nil || ghost != nil || party || holidays.valentine || (holidays.halloween && dark > 0.5)) || ufo != nil || !highFives.isEmpty || !hearts.isEmpty || letter != nil || t < purrUntil || !rain.isEmpty)
    }
}

extension HouseBehaviour {
    public func enableEggs(persist: Bool = false) {
        guard eggs == nil else { return }
        let e = HouseEggs(behaviour:self)
        if persist {
            let key = "house.eggs.v1"
            if let d = UserDefaults.standard.data(forKey:key), let s = try? JSONDecoder().decode(HouseEggs.Saved.self,from:d) { e.saved = s }
            e.save = { if let d = try? JSONEncoder().encode($0) { UserDefaults.standard.set(d,forKey:key) } }
        }
        eggs = e
    }
}
