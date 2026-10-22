import Foundation

/// Reserved stage 3 calls, at the page's corresponding frame boundaries.
/// The default callbacks consume no time or randomness. Rendering-only egg
/// hooks (items/look/eyes/after/click) remain the future renderer's responsibility.
public struct HouseLifeStage3Hooks {
    public var lightingAndWeather: (Double) -> Void = { _ in }
    public var eggSky: (Double) -> Void = { _ in }
    public var eggStep: (Double) -> Void = { _ in }
    public var drawSkyLife: (Double) -> Void = { _ in }
    public var drawSeason: (Double) -> Void = { _ in }
    public var eggOver: (Double) -> Void = { _ in }
    public init() {}
}

public final class HouseLifeHold {
    public var kind: String, stage: String?, target: String?, state: String?
    public var t0: Double, t1: Double?, start: Double?, z0: Double?, re: Double?
    public var dir: Int?, spraying: Bool?, sprayFrom: Double?
    public var errand: HouseErrand?
    public init(kind: String, t0: Double, errand: HouseErrand? = nil, state: String? = nil) {
        self.kind = kind; self.t0 = t0; self.errand = errand; self.state = state
    }
}
public final class HouseLifeFire {
    public var t0: Double, helper: String?, retry: Double?, foamed: Double?
    init(t0: Double) { self.t0 = t0 }
}
public final class HouseLifeSpriteState {
    public var pose: String?, want: String?, next = 0.0, rNext: Double?
    public var scene: String?, arriveState: String?, deskOf: String?, fireOf: String?
    public var re = 0.0, greet: HouseDogGreeting?, look: [Double]?, wag = false, ball = false, toss: Double?
    public var face = 1, hold: HouseLifeHold?, fire: HouseLifeFire?, errSince: Double?
    public var workSince: Double?, mailAct: String?
}
public final class HouseLifeState {
    public struct Firework { public var room: String, t0: Double, seed: Double }
    public var enabled = false, hour = 12.0, dark = 0.0
    public var ball: HouseFetchBall?, swinger: String?
    public var mailFlag = -1e9, fireworks: [Firework] = []
    var quietSince: [[UInt16]: Double] = [:]
}

extension HouseBehaviour {
    /// Injected-RNG stage 2b clients can keep their isolated simulation. Enable
    /// the page's life layer before the first row delivery for full-house parity.
    /// hour/dark are supplied by the host clock/lighting layer (stage 3).
    public func enableLife(hour: Double = 12, dark: Double = 0) {
        life.enabled = true; life.hour = hour.isFinite ? hour : 12; life.dark = dark.isFinite ? dark : 0
        hooks.sceneTrack = { [weak self] sp,a,prev in self?.sceneTrack(sp,a,prev) ?? false }
        hooks.sceneLeave = { [weak self] sp in self?.sceneLeave(sp) ?? false }
        hooks.dogGreet = { [weak self] sp in self?.dogGreet(sp); return true }
        hooks.residents = { [weak self] _ in self?.updateResidents(); return true }
        hooks.cat = { [weak self] t in
            guard let self else { return false }
            for sp in self.sprites where sp.kind == "cat" { self.catThink(sp,t) }; return true
        }
        hooks.dog = { [weak self] t in
            guard let self else { return false }
            for sp in self.sprites where sp.kind == "dog" { self.dogThink(sp,t) }; return true
        }
        hooks.dayScenes = { [weak self] _ in
            guard let self else { return false }
            for sp in self.sprites where sp.kind == "home" && sp.id.hasPrefix("home:") { self.residentRoutine(sp) }; return true
        }
        // The normal frame invokes scenes once: JS interleaves each sprite's
        // routine, pet decision, hold and arrival, rather than batching by kind.
        hooks.scenes = { [weak self] _ in self?.lifeScenes(); return true }
    }
    func shared(_ name: String) -> String? { layout.rooms.first { $0.key == "__"+name }?.key }
    func anyWorking() -> Bool { sprites.contains { $0.kind == "agent" && ($0.behaviour.agent?.state == "working" || $0.state == "working") } }
    func scPick<T>(_ values: [T]) -> T? {
        // All page callers supply nonempty lists; stale host inputs remain safe.
        guard !values.isEmpty else { return nil }
        return values[min(values.count-1,max(0,Int(floor(sim.random()*Double(values.count)))))]
    }
    func scArrived(_ sp: HouseSprite) -> Bool { sp.path.isEmpty && sp.onBridge == nil && sp.goal != nil && HouseRoutes.same(sp.room,sp.goal?.room) }
    func hasHold(_ sp: HouseSprite) -> Bool { sp.life.hold != nil || sp.behaviour.handover != nil }
    func releaseHold(_ sp: HouseSprite, quiet: Bool = false) {
        if sp.behaviour.handover != nil {
            if quiet { sp.behaviour.handover = nil } else { releaseHandover(sp) }; return
        }
        guard let h = sp.life.hold else { return }
        sp.life.hold = nil
        if let z = h.z0, sp.path.isEmpty { sp.z = z }
        if quiet { return }
        if sp.kind == "agent", let a = sp.behaviour.agent {
            sp.state = a.state
            if let e = h.errand, a.state == "done" { sp.behaviour.errand = e; e.until = max(e.until,time+8000) }
            let (r,c) = sp.behaviour.errand.map { ($0.room,$0.cat) } ?? placeFor(sp)
            sim.setGoal(sp,pickSpot(sp,r,c))
        } else if sp.kind == "home" {
            sp.state = "idle"; sp.life.rNext = 0
            if let e = h.errand { sp.behaviour.errand = e }
        }
    }
    func sceneTrack(_ sp: HouseSprite, _ a: HouseAgentRow, _ prev: String?) -> Bool {
        let l = sp.life, b = sp.behaviour
        if a.state == "working", (l.workSince ?? 0) == 0 { l.workSince = time }
        // Pop precedes hold validation. trackSubagent also handles handover, so
        // call it here only after non-handover holds have had their page turn.
        if prev == nil || prev == "", !(a.parentId ?? "").isEmpty, !b.popped {
            b.popped = true
            if let p = find(a.parentId ?? ""), let key = p.room, p.onBridge == nil, p.alpha > 0.5 {
                let r = sim.room(key); sp.room = key; sp.x = clamp(p.x+0.9,0.4,r.NX-0.4); sp.y = clamp(p.y+0.6,0.4,r.NY-0.4)
                sp.z = 0; sp.path = []; sp.alpha = 0; puff(sp)
            }
        }
        if let h = l.hold {
            let ok = h.kind == "fetch" ? a.state == "done" : h.kind == "mail" ? a.state == "working" : h.kind == "ext" ? a.state != "error" && a.state != "waiting" : a.state == "done"
            if !ok { releaseHold(sp) }
        } else if let h = b.handover, h.vanish || a.state != "done" { releaseHandover(sp) }
        if !hasHold(sp), let prev, !prev.isEmpty, prev != "done", a.state == "done" {
            if let parent = a.parentId, !parent.isEmpty, let p = find(parent), p.room != nil, !b.handed { startHandover(sp,p,vanish: false) }
            else if (a.parentId ?? "").isEmpty, let since = l.workSince, since != 0, time-since > 8000 { startCelebrate(sp) }
        }
        if a.state == "done" { l.workSince = nil }
        let git = a.state == "working" && (a.activity ?? "").range(of: #"\bgit\s+(commit|push)\b"#, options: [.regularExpression,.caseInsensitive]) != nil
        if !git { l.mailAct = nil }
        else if !hasHold(sp), !HouseRoutes.same(a.activity,l.mailAct), (layout.yard.on || shared("kitchen") != nil), sp.room != nil, sp.onBridge == nil, sp.alpha > 0.5 {
            l.mailAct = a.activity; startMail(sp)
        }
        if let state = l.hold?.state { sp.state = state }
        if b.handover != nil { sp.state = "idle" }
        return hasHold(sp)
    }
    func sceneLeave(_ sp: HouseSprite) -> Bool {
        if sp.life.hold != nil { releaseHold(sp,quiet: true) }
        return leaveSubagent(sp)
    }
    func startMail(_ sp: HouseSprite) {
        let h = HouseLifeHold(kind: "mail",t0: time); h.stage = "go"; sp.life.hold = h
        let yard = layout.yard.on
        sim.setGoal(sp,.init(room: yard ? "__yard" : shared("kitchen") ?? "__bath",p: yard ? sim.spots("__yard")["mail"]?.first ?? [9.4,4.3,0] : [9.4,4.3,0],cat: "mail"))
    }
    func startCelebrate(_ sp: HouseSprite) {
        let h = HouseLifeHold(kind: "celebrate",t0: time,errand: sp.behaviour.errand,state: "fall"); h.start = time
        sp.life.hold = h; sp.behaviour.errand = nil; sp.state = "fall"
        life.fireworks.append(.init(room: sp.room == "__yard" ? "__bath" : sp.room ?? sp.homeRoom,t0: time,seed: floor(sim.random()*5)))
    }
    func extGoal(_ sp: HouseSprite, _ target: HouseSprite) {
        guard let key = target.room else { return }; let r = sim.room(key)
        var x = target.x+1.1, dir = -1
        if x > r.NX-0.4 { x = target.x-1.1; dir = 1 }
        sim.setGoal(sp,.init(room: key,p: [clamp(x,0.4,r.NX-0.4),clamp(target.y+0.3,0.4,r.NY-0.4),0],cat: "ext")); sp.life.hold?.dir = dir
    }
    func findFireHelper(_ sp: HouseSprite) {
        guard sp.room != nil, sp.onBridge == nil, let fire = sp.life.fire else { return }
        if let id = fire.helper, let h = find(id)?.life.hold, h.kind == "ext", HouseRoutes.same(h.target,sp.id) { return }
        if time < (fire.retry ?? 0) { return }; fire.retry = time+2000
        var best: HouseSprite?, score = Double.infinity
        for o in sprites {
            if o === sp || (o.kind != "home" && o.kind != "agent") || !HouseRoutes.same(o.room,sp.room) || hasHold(o) || o.leaving || o.exit || o.life.fire != nil || o.onBridge != nil || o.alpha < 0.5 { continue }
            if o.state == "shower" || o.behaviour.agent?.state == "error" || o.behaviour.agent?.state == "waiting" { continue }
            let s = houseBehaviourHypot([o.x-sp.x,o.y-sp.y]) + (o.kind == "home" ? 0 : o.state == "working" ? 20 : 8)
            if s < score { best = o; score = s }
        }
        guard let best else { return }
        let h = HouseLifeHold(kind: "ext",t0: time,errand: best.behaviour.errand,state: "idle"); h.target = sp.id; h.dir = -1
        best.life.hold = h; best.behaviour.errand = nil; best.state = "idle"; best.life.scene = nil
        extGoal(best,sp); fire.helper = best.id
    }
    func stepLifeHold(_ sp: HouseSprite) {
        guard let h = sp.life.hold else { if sp.behaviour.handover != nil { stepHandover(sp) }; return }
        if let state = h.state { sp.state = state }
        switch h.kind {
        case "mail":
            if h.stage == "go", scArrived(sp), sp.goal?.cat == "mail" { h.stage = "drop"; h.t1 = time; life.mailFlag = time }
            else if (h.stage == "drop" && time-(h.t1 ?? time) > 900) || time-h.t0 > 60000 { releaseHold(sp) }
        case "ext":
            guard let tg = h.target.flatMap(find), let fire = tg.life.fire,
                  !(!HouseRoutes.same(tg.room,sp.room) && sp.path.isEmpty && sp.onBridge == nil), time-h.t0 <= 90000 else { releaseHold(sp); return }
            h.spraying = false
            if scArrived(sp) {
                if houseBehaviourHypot([tg.x-sp.x,tg.y-sp.y]) <= 2 { h.spraying = true; if h.sprayFrom == nil { h.sprayFrom = time }; fire.foamed = time }
                else if time > (h.re ?? 0) { h.re = time+1500; extGoal(sp,tg) }
            }
        case "fetch": if life.ball == nil || !HouseRoutes.same(life.ball?.by,sp.id) || time-h.t0 > 90000 { releaseHold(sp) }
        case "celebrate":
            if !sp.path.isEmpty { h.t0 = time; if time-(h.start ?? time) > 8000 { releaseHold(sp) }; return }
            if h.z0 == nil { h.z0 = sp.z }
            let e = time-h.t0
            if e > 1800 { releaseHold(sp); return }
            sp.z = (h.z0 ?? 0)+abs(sin(e/600 * .pi))*7
        default: break
        }
    }
    func lifeScenes() {
        if !sprites.contains(where: { $0.kind == "cat" }), let key = shared("kitchen") ?? layout.rooms.first?.key {
            let c = sim.spawn(id: "__cat",room: key,kind: "cat",small: true)
            c.behaviour.vendor = "home"; c.state = "idle"; c.life.pose = "sit"; c.life.next = time+3000
        }
        updateYard()
        life.swinger = nil
        if let p = sim.spots("__yard")["swing"]?.first {
            life.swinger = sprites.first { $0.room == "__yard" && $0.path.isEmpty && $0.goal?.room == "__yard" && abs(($0.goal?.p[0] ?? 0)-p[0]) < 0.01 && abs(($0.goal?.p[1] ?? 0)-p[1]) < 0.01 }?.id
        }
        if layout.yard.on, find("__dog") == nil {
            let d = sim.spawn(id: "__dog",room: "__yard",kind: "dog",small: true)
            d.behaviour.vendor = "home"; d.state = "idle"; d.life.pose = "nap"; d.life.next = time+4000
            if let p = sim.spots("__yard")["dog"]?.first { d.x = p[0]; d.y = p[1] }
        } else if !layout.yard.on, let d = find("__dog") { sim.removeSprite(d); life.ball = nil }
        for sp in sprites {
            if sp.kind == "agent" {
                if sp.behaviour.agent?.state == "error", !sp.leaving {
                    if sp.life.errSince == nil { sp.life.errSince = time }
                    if sp.life.fire == nil, time-(sp.life.errSince ?? time) > 3000 { sp.life.fire = .init(t0: time) }
                } else {
                    sp.life.errSince = nil
                    if sp.life.fire != nil {
                        sp.life.fire = nil
                        if let key = sp.room, sp.onBridge == nil { puffs.append(.init(room: key,x: sp.x,y: sp.y,z: sp.z,t0: time,col: "#9a9aa6",seed: sim.random()*6)) }
                    }
                }
            }
            if sp.kind == "home", sp.id.hasPrefix("home:") { residentRoutine(sp) }
            if sp.kind == "cat" { catThink(sp,time) }
            if sp.kind == "dog" { dogThink(sp,time) }
            if hasHold(sp) { stepLifeHold(sp) }
            if let state = sp.life.arriveState, sp.path.isEmpty { sp.state = state; sp.life.arriveState = nil }
        }
        for sp in sprites where sp.life.fire != nil { findFireHelper(sp) }
        stage3.drawSkyLife(time)

    }
}
