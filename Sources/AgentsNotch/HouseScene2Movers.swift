import AppKit
import NotchCore
import SpriteKit

/// What `HouseSprite` does not carry but the page's drawClawd reads: whose Clawd it is and what it is doing at its desk.
/// The host (agent behaviour is stage 2b) supplies it per sprite; the scene only picks the pose sprite.
struct HouseLook {
    var vendor = "claude"
    var activity = ""
}

/// The moving sprites: each HouseSim sprite is one SKSpriteNode showing a pose cut from the page's drawClawd (feet anchor
/// ax, ay), placed at iso() of its spot, in front of the pieces of its room that lie behind it.
extension HouseScene2 {
    func linkW(_ sp: HouseSprite) -> Double { (sp.seed - 0.5) * 0.36 }

    func iso(_ f: HouseLayout.Frame, _ x: Double, _ y: Double, _ z: Double) -> (Double, Double) {
        (f.ox + (x - y) * 16, f.oy + f.drop + (x + y) * 8 - z * 2)
    }

    private func idx(_ n: Int, _ period: Double, _ t: Double) -> Int { Int(floor(t.truncatingRemainder(dividingBy: period) / period * Double(n))) % n }

    /// The pose sprite name for a sprite at time t (ms), per parts.json poses.names and poses.timing.
    static func propFor(_ act: String) -> String? {
        let a = act.lowercased()
        if a.hasPrefix("bash"), a.range(of: #"\b(test|tests|jest|pytest|vitest|mocha|rspec|xctest|phpunit|unittest)\b"#, options: .regularExpression) != nil { return "flask" }
        if a.range(of: #"^(edit|write|multiedit|notebookedit)\b"#, options: .regularExpression) != nil { return "hammer" }
        if a.range(of: #"^(websearch|webfetch|web)"#, options: .regularExpression) != nil { return "binoculars" }
        if a.range(of: #"^(read|grep|glob)\b"#, options: .regularExpression) != nil { return "book" }
        return nil
    }

    /// The page's onLaptop: seated at a desk of the room it is in (the library's candle stool has no screen: a laptop there).
    func onLaptop(_ sp: HouseSprite) -> Bool {
        guard let gl = sp.goal, let room = sp.room, gl.room == room else { return false }
        if gl.cat == "seat" || gl.cat == "cowork" { return true }
        return gl.cat == "work" && gl.i == 1 && layout.rooms.first { $0.key == room }?.theme == "library"
    }

    func poseName(_ sp: HouseSprite, look: HouseLook, face: Int, t: Double, frame: HouseBehaviourFrame? = nil, simT: Double = 0) -> String {
        let tick = { (ms: Double) in Int(floor(t / ms)) % 2 }
        let st = sp.state ?? ""
        switch sp.kind {
        case "cat", "dog":
            return petPoseName(sp, face: face, t: t, frame: frame)
        case "home":
            if st == "idle-sleep" { return "home/sleep.\(idx(4, 1400, t))" }
            return sp.moving ? "home/walk.\(tick(110))" : "home/stand.0"
        default:
            let p = look.vendor + (sp.small ? "-mini" : "")
            if st == "fall" { return sp.moving ? p + "/fallmv.\(tick(110))" : p + "/fall.0" }
            if st == "shower" { return p + "/shower.0" }
            if st == "dry" { return p + "/dry.0" }
            if sp.waving == true { return p + "/wave.\(tick(300))" }
            if let ta = frame?.tossAt, simT - ta < 450, !sp.moving { return p + "/toss.0" }
            if sp.moving && st == "waiting" { return p + "/waitwalk.\((sin(t / 260) > 0 ? 0 : 2) + tick(110))" } // walking with the waiting arms
            if sp.moving { return p + "/walk.\(tick(110))" }
            if st == "waiting" { return p + "/waiting.\(Self.waitStep(t))" }
            if st == "error" { return p + "/error.\(idx(4, 1885, t))" }
            if st == "done" || st == "idle-sleep" { return p + "/sleep.\(idx(4, 1400, t))" }
            // the page's drawProps: a working Clawd that stands still and has nowhere to walk holds the laptop it sits at, or what its tool suggests
            if st == "working" && sp.path.isEmpty {
                if onLaptop(sp) {
                    // three glow phases of sin(t/900 + seed*9), cut at 0, 700, 1400 ms with the seed .3
                    let g = sin(t / 900 + sp.seed * 9)
                    let k = (0..<3).min { abs(sin(Double($0) * 700 / 900 + 2.7) - g) < abs(sin(Double($1) * 700 / 900 + 2.7) - g) }!
                    return p + "/laptop.\(k)"
                }
                switch Self.propFor(look.activity) {
                case "flask": return p + "/flask.\(idx(4, 800, t + sp.seed * 800))"
                case "hammer": return p + "/hammer.\(Int(floor(t / 190 + sp.seed * 3)) % 2)"
                case "binoculars": return p + "/binoculars.\((t / 1700 + 3).truncatingRemainder(dividingBy: 1) < 0.15 ? 1 : 0)"
                case "book": return p + "/book.\((t / 2600 + sp.seed).truncatingRemainder(dividingBy: 1) < 0.12 ? 1 : 0)"
                default: break
                }
            }
            if sp.seated == true && st == "working" { return p + "/work.\(tick(160))" }
            return p + "/stand.0"
        }
    }

    func roomFrame(_ key: String) -> HouseLayout.Room? {
        key == "__yard" ? layout.yard.room : layout.rooms.first { $0.key == key }
    }

    /// Where a sprite stands: its feet on the canvas and the z it is drawn at.
    func place(_ sp: HouseSprite, sim: HouseSim) -> (x: Double, y: Double, z: CGFloat)? {
        let S = 2.0, w = linkW(sp)
        if let ob = sp.onBridge {
            if ob.kind == "lift" {
                guard let ci = layout.lift?.cabins.firstIndex(where: { $0.id == ob.pair }), let lf = liftParts else { return nil }
                let sh = layout.lift!.cabins[ci].sh, cz = sim.cabins[ci].z
                let p = iso(wf, sh.cx + w * 1.4, sh.cy - w * 0.8, cz)
                let vi = min(light.variant, lf.variants.count - 1)
                let f = lf.variants[vi].floors.first { cz >= $0.zlo && cz < $0.zhi }?.level ?? 0
                return (p.0, p.1, riderZ[ci]?[f] ?? topZ)
            }
            guard let L = layout.links.first(where: { $0.id == ob.pair }), let info = linkInfo[L.id] else { return nil }
            if L.kind == "stair" {
                let c = cos(L.ang ?? 0), s = sin(L.ang ?? 0), d = ob.u * L.len, steps = Double(L.steps ?? 13)
                let k = min(steps, max(0, ceil(ob.u * steps - 0.2))), ww = w * 0.8
                let p = iso(wf, L.A[0] + c * d - s * ww, L.A[1] + s * d + c * ww, (L.z0 ?? 0) + k * (L.rise ?? 0) / steps)
                return (p.0, p.1, info.stepsZ + 4)
            }
            let x = L.A[0] + (L.B[0] - L.A[0]) * ob.u, y = L.A[1] + (L.B[1] - L.A[1]) * ob.u, z = (L.z ?? 0) - parts.SLAB
            let p = L.axis == "x" ? iso(wf, x, y + w, z) : iso(wf, x + w, y, z)
            return (p.0, p.1, info.backZ + 4)
        }
        guard let key = sp.room, let r = roomFrame(key) else { return nil }
        let p = iso(HouseLayout.Frame(ox: r.ox, oy: r.oy, drop: 0), sp.x, sp.y, sp.z)
        _ = S
        let atFoot = key == "__yard" && sp.x < 2.6
        let onStairs = layout.lift != nil ? (key == "__bath" && sp.y > r.NY - 0.05 && sp.x < 1.6) : false
        if atFoot || onStairs { return (p.0, p.1, topZ - 2 + CGFloat(sp.x + sp.y) * 0.01) }
        let listKey = key == "__yard" ? "__bath" : key
        guard let info = roomInfo[listKey] else { return nil }
        let depth = sp.x + sp.y + 0.55 + (sp.z > 9 ? 0.3 : 0)
        let slot = info.slots.first { $0.depth > depth || ($0.depth == depth && $0.fixture) }
        let base = (slot?.z ?? info.endZ + 4) - 4
        return (p.0, p.1, base + CGFloat(depth) * 0.15)
    }

    /// Puts every sprite of the simulation where it stands, in its pose; the cabins and stairs follow the simulation too.
    func sync(sim: HouseSim) {
        cabinState = sim.cabins.map { ($0.z, $0.state) }
        applyCabins()
        for l in sim.links where l.geometry.kind == "stair" {
            guard let info = linkInfo[l.geometry.id] else { continue }
            let up = l.lift >= 0.5
            for n in info.down { n.isHidden = up }
            for n in info.up { n.isHidden = !up }
        }
        let vi = min(light.variant, parts.poses.variants.count - 1)
        let frames = behaviour.map { b in Dictionary(b.renderFrames().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) } ?? [:]
        let simT = behaviour?.time ?? clockMillis
        var seen = Set<String>()
        for sp in sim.sprites {
            seen.insert(sp.id)
            var fallen: HouseParachute?
            let spot: (x: Double, y: Double, z: CGFloat)?
            if sp.fall != nil, let f = fallPlace(sp) { spot = (f.x, f.y, f.z); fallen = f.p } else { spot = place(sp, sim: sim) }
            guard sp.alpha > 0.001, let at = spot else { moverNodes[sp.id]?.isHidden = true; canopyNodes[sp.id]?.isHidden = true; continue }
            if let f = fallen, let c = canopy(x: at.x, y: at.y, open: f.open, vendor: sp.behaviour.vendor) {
                let cn = canopyNodes[sp.id] ?? { let m = SKSpriteNode(); m.anchorPoint = CGPoint(x: 0, y: 1); movers.addChild(m); canopyNodes[sp.id] = m; return m }()
                cn.texture = c.0; cn.size = c.2; cn.position = CGPoint(x: c.1.x, y: -c.1.y); cn.zPosition = at.z - 0.5; cn.alpha = CGFloat(sp.alpha); cn.isHidden = false
            } else { canopyNodes[sp.id]?.isHidden = true }
            let last = lastPos[sp.id], sx = (sp.x - sp.y)
            var face = 1
            if let last { let d = sx - (last.0 - last.1); face = abs(d) > 1e-6 ? (d > 0 ? 1 : -1) : faceMemory[sp.id] ?? 1 }
            faceMemory[sp.id] = face
            lastPos[sp.id] = (sp.x, sp.y)
            let fr = frames[sp.id], lk = look(sp)
            if (sp.kind == "cat" || sp.kind == "dog"), let fr { face = fr.facing }
            let t = (sp.context ?? 0) >= 0.9 ? clockMillis * 0.5 : clockMillis
            let name = poseName(sp, look: lk, face: face, t: t, frame: fr, simT: simT)
            guard let pose = parts.poses.variants[vi][name] ?? parts.poses.variants[vi][lk.vendor + "/stand.0"] else { continue }
            let extra = overlayLayers(sp, look: lk, frame: fr, t: t, simT: simT, vi: vi)
            let all = pose.layers.map { ($0, false) } + extra.layers
            let sig = all.map { String($0.0.sprite) + ($0.1 ? "g" : "") }.joined(separator: ",")
            let n = moverNodes[sp.id] ?? {
                let m = SKSpriteNode(); m.anchorPoint = CGPoint(x: 0, y: 1); movers.addChild(m); moverNodes[sp.id] = m; return m
            }()
            let ax0 = pose.layers[0].ax, ay0 = pose.layers[0].ay
            if n.userData?["sig"] as? String != sig {
                // the pose's layers are reused in place: a walk changes its pose every 110 ms and makes no node for it
                var spare = n.children.compactMap { $0 as? SKSpriteNode }.filter { $0.name == "ly" || $0.name == "glow" }
                for (k, (ly, glow)) in all.enumerated() {
                    let r = pages.rect(ly.sprite)
                    let c: SKSpriteNode
                    if !spare.isEmpty { c = spare.removeFirst() } else {
                        c = SKSpriteNode(); c.anchorPoint = CGPoint(x: 0, y: 1); n.addChild(c); HouseRects.created += 1
                    }
                    c.texture = pages.texture(ly.sprite)
                    c.size = CGSize(width: r.w, height: r.h)
                    c.position = CGPoint(x: Double(ax0 - ly.ax), y: -Double(ay0 - ly.ay))
                    c.zPosition = (k < pose.layers.count ? 0 : 0.003) + CGFloat(k) * 0.0001
                    c.shader = nil; shaders.apply(to: c, id: ly.sprite)
                    c.name = glow ? "glow" : "ly"
                    c.blendMode = ly.blend == "add" ? .add : .alpha
                    c.isHidden = false; c.alpha = 1
                }
                for c in spare { c.removeFromParent() }
                n.userData = ["sig": sig]
            }
            if let g = extra.glow { for c in n.children where c.name == "glow" { c.alpha = CGFloat(g) } }
            n.isHidden = false
            n.alpha = CGFloat(sp.alpha)
            n.position = CGPoint(x: Double(HouseLight.round(at.x) - ax0), y: -Double(HouseLight.round(at.y) - ay0))
            n.zPosition = at.z
            let nap = (sp.kind == "cat" || sp.kind == "dog") && name.contains("/nap.")
            updateMarks(sp, node: n, ax0: ax0, ay0: ay0, look: lk, t: t, napFace: nap ? face : nil, feetX: at.x)
            if sp.kind != "cat", sp.kind != "dog", let g = parts.poses.looks?[lookKey(sp, lk)] { hitBoxes[sp.id] = hitBox(sp, geo: g, t: t) } else { hitBoxes[sp.id] = nil }
        }
        for (id, n) in moverNodes where !seen.contains(id) { n.removeFromParent(); moverNodes[id] = nil; lastPos[id] = nil; faceMemory[id] = nil; infoRects[id] = nil; markRects[id] = nil; hitBoxes[id] = nil }
        updateEffects(sim: sim, simT: simT, t: clockMillis)
        updateSkyLife(t: clockMillis)
        for (id, n) in canopyNodes where !seen.contains(id) { n.removeFromParent(); canopyNodes[id] = nil }
    }

    /// The page's houseAwake: the house draws while an agent works or anything moves, and may rest until the next minute otherwise.
    /// Marks, idle residents and a still camera do not keep it awake (the page does not animate them on their own either).
    var isMoving: Bool {
        guard let sim else { return houseCamera?.isMoving == true }
        if houseCamera?.isMoving == true { return true }
        if sim.cabins.contains(where: { $0.state != "idle" }) || sim.links.contains(where: { $0.turn != nil }) { return true }
        if let b = behaviour, !b.puffs.isEmpty || !b.papers.isEmpty || !b.life.fireworks.isEmpty || pendingRows != nil || sim.roomsSettling { return true }
        return sim.sprites.contains { !$0.path.isEmpty || $0.onBridge != nil || $0.fall != nil || $0.behaviour.handover != nil || $0.life.hold != nil || $0.life.fire != nil || ($0.kind == "agent" && $0.state == "working") }
    }

    /// Anything that visibly moves (walking, the lift, falls, particles, fades, rooms arriving, the host's direct manipulation): draws at the full rate.
    /// What stays awake without it (agents typing or waiting at their desks, a held or burning resident: frames of 110-130 ms) only steps frames, so it draws at half that.
    var isBursting: Bool {
        if houseCamera?.isMoving == true { return true } // a zoom, pan or glide is direct manipulation
        guard let sim else { return false }
        if sim.roomsSettling || pendingRows != nil || burstExtra() { return true }
        if sim.cabins.contains(where: { $0.state != "idle" }) || sim.links.contains(where: { $0.turn != nil }) { return true }
        if let b = behaviour, !b.puffs.isEmpty || !b.papers.isEmpty || !b.life.fireworks.isEmpty { return true }
        return sim.sprites.contains { !$0.path.isEmpty || $0.onBridge != nil || $0.fall != nil || $0.behaviour.handover != nil || $0.alpha != $0.fade || $0.moving }
    }

    /// The waiting hop and arm: round(|sin(t/260)|*3) x (sin > 0), 7 steps in each half of the 1634 ms cycle.
    static func waitStep(_ t: Double) -> Int {
        let ph = (t / 260).truncatingRemainder(dividingBy: 2 * .pi), h = ph >= .pi ? 1 : 0, r = ph - Double(h) * .pi
        let b = [0.0, 0.1674, 0.5236, 0.9851, 2.1565, 2.618, 2.9742]
        return h * 7 + (b.lastIndex { $0 <= r } ?? 0)
    }

    override func update(_ currentTime: TimeInterval) {
        let raw = lastTime.map { max(0, currentTime - $0) } ?? 0
        stepInteraction(frameMs: min(1500, raw * 1000))
        let dt = min(0.1, raw)
        lastTime = currentTime
        if !freezeClock { clockMillis += dt * 1000 }
        if behaviour != nil, !freezeSim { advanceBehaviour(ms: raw * 1000) }
        else if driveSim, let sim { var left = dt * 1000; while left > 0 { let step = min(50, left); left -= step; sim.step(dt: step) } }
        if followClock {
            let c = Calendar.current, d = Date(), h = c.component(.hour, from: d), m = c.component(.minute, from: d)
            if h * 60 + m != lastMinute {
                lastMinute = h * 60 + m
                // the page's setTime takes the seconds too
                setTime(hour: Double(h) + Double(m) / 60 + Double(c.component(.second, from: d)) / 3600, day: (c.ordinality(of: .day, in: .year, for: d) ?? 1) - 1)
            }
            let blink = Int(d.timeIntervalSince1970) % 2 == 0
            if blink != colon {
                colon = blink
                // the light follows the seconds like the page's: the shader's ambient every second, a new variant rebuilds
                let hs = Double(h) + Double(m) / 60 + Double(c.component(.second, from: d)) / 3600
                let st = HouseLight.state(parts, hour: hs)
                if st.variant != builtVariant { setTime(hour: hs, day: (c.ordinality(of: .day, in: .year, for: d) ?? 1) - 1) } else { shaders.set(st.amb) }
                repaint(sync: false, clockOnly: true) // the clock faces' colon blinks with the seconds, as the page's
            }
        }
        if let sim { sync(sim: sim) }
        updateClouds()
        if mistAmount > 0.02 { refreshMist() }
        onFrame?(clockMillis)
        pace(currentTime)
    }

    /// Full rate while something moves, half of it while agents only type (their frames change every ~110 ms), paused after 3 s of nothing and woken each minute
    /// for the sky (the clouds drift a pixel at a time and the wisps likewise, so the idle house rests too).
    private func pace(_ now: TimeInterval) {
        counted += 1
        if countFrom == 0 { countFrom = now }
        if now - countFrom >= 5 { deliveredFps = Double(counted) / (now - countFrom); counted = 0; countFrom = now }
        guard followClock else { return }
        let moving = isMoving
        let want = fixedFps ?? min(maxFps, isBursting ? 60 : 30)
        if want != rate { rate = want; view?.preferredFramesPerSecond = want }
        if moving || fixedFps != nil { stillSince = nil; return }
        if stillSince == nil { stillSince = now }
        if let s = stillSince, now - s >= 3 { sleepUntilNextMinute() }
    }

    private func sleepUntilNextMinute() {
        view?.isPaused = true
        napTimer?.invalidate()
        let ms = 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60) + 0.05
        napTimer = Timer.scheduledTimer(withTimeInterval: ms, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let view = self.view else { return }
                self.stillSince = (self.lastTime ?? 0) - 2.9 // one frame for the new minute, then asleep again
                view.isPaused = false
            }
        }
    }

    /// Wakes a sleeping house (the host calls it when the window shows again).
    func wake() { covered = false; napTimer?.invalidate(); stillSince = nil; view?.isPaused = false }
    /// New work for a house that rests: wakes it unless the window is covered.
    func stir() { if !covered { wake() } }
    /// Stops drawing until wake(), without the minute refresh (the host calls it when the window is covered).
    func hide() { covered = true; napTimer?.invalidate(); view?.isPaused = true }
}
