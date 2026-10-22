import Foundation

extension HouseSim {
    /// The page runs this inside frame()'s try/catch: a sprite in a state nobody
    /// planned for ends that frame, it does not take the house down. Here each
    /// sprite is its own scope; anything the JS would throw on skips that sprite
    /// (a stale link id drops the node that names it).
    func stepSprites(_ dt: Double) {
        for sp in sprites { stepSprite(sp, dt) }
    }

    private func stepSprite(_ sp: HouseSprite, _ dt: Double) {
        let delta = sp.fade - sp.alpha
        sp.alpha += (delta > 0 ? 1 : delta < 0 ? -1 : 0) * min(abs(delta), dt / 450)
        if sp.leaving && sp.alpha <= 0.01 {
            removeSprite(sp); return
        }
        if sp.fall != nil { return }
        if sp.frozen || time < (sp.frozenUntil ?? -.infinity) { sp.moving = false; return }
        if sp.exit && sp.path.isEmpty {
            // JS reads iso() against the sprite's room; none (mid-crossing) throws.
            guard let key = sp.room else { return }
            let r = room(key)
            let x = r.ox + (sp.x - sp.y) * 8 * 2
            let y = r.oy + r.drop + (sp.x + sp.y) * 4 * 2 - sp.z * 2
            // The yard has no world position of its own: it sits one slab below the bathroom.
            let bath = layout.rooms.first
            let wx = r.wx ?? ((bath?.wx ?? 0) + r.ox - (bath?.ox ?? 0))
            let wy = r.wy ?? ((bath?.wy ?? 0) + r.oy - (bath?.oy ?? 0))
            sp.fall = .init(x: x-r.ox+wx, y: y-r.oy+wy, t0: time, seed: sp.seed)
            sp.room = nil; sp.state = "fall"; sp.moving = false; return
        }
        sp.waving = false
        guard let n = sp.path.first else { sp.moving = false; sp.seated = sp.z > 3; return }
        sp.seated = false
        if n.lift != nil {
            if n.since == nil { n.since = time }
            sp.moving = false; return
        }
        let speed = dt / 1000 * (sp.small ? 2.3 : 1.9) * ((sp.context ?? 0) >= 0.9 ? 0.55 : 1) * ((sp.speed ?? 0) == 0 ? 1 : sp.speed ?? 1)
        if let bridge = n.bridge {
            guard let state = link(bridge), let target = n.to else { sp.path.removeFirst(); sp.moving = false; return }
            let l = state.geometry
            var ob: HouseSprite.Transit
            if let current = sp.onBridge, HouseRoutes.same(current.pair, bridge) { ob = current }
            else {
                ob = .init(kind: l.kind, pair: bridge, u: n.from ?? ((n.to ?? 0) > 0.5 ? 0 : 1)); sp.room = nil
            }
            let dir = target >= ob.u ? 1.0 : -1.0, step = speed / max(0.5,l.len)
            ob.forward = dir > 0
            if abs(target-ob.u) <= step {
                ob.u = target; sp.path.removeFirst()
                let next = sp.path.first
                if next == nil || !(HouseRoutes.same(next?.bridge,bridge) || HouseRoutes.same(next?.call,bridge) || (next?.wait ?? 0) != 0) {
                    sp.onBridge = nil
                } else { sp.onBridge = ob }
            } else { ob.u += dir * step; sp.onBridge = ob; sp.moving = true }
            return
        }
        if let wait = n.wait, wait != 0 {
            let until = (n.until ?? 0) == 0 ? time + wait : n.until ?? 0
            n.until = until
            sp.moving = false; sp.seated = true
            if time >= until { sp.path.removeFirst() }
            return
        }
        if let call = n.call {
            guard let l = link(call) else { sp.path.removeFirst(); return }
            if l.aim == n.aim && l.turn == nil { sp.path.removeFirst(); return }
            if n.since == nil { n.since = time }
            sp.waving = true; sp.moving = false; return
        }
        guard let p = n.p, p.count >= 3 else { sp.path.removeFirst(); return }
        if n.jump == true {
            sp.room = n.r; sp.x = p[0]; sp.y = p[1]; sp.z = p[2]
            sp.path.removeFirst(); if n.poof == true { sp.alpha = 0 }; return
        }
        let dx = p[0]-sp.x, dy = p[1]-sp.y, dz = (p[2]-sp.z)/14
        // Match Math.hypot's scaled, compensated sum. A few ulps here
        // decide which tick consumes a node at an exact-speed boundary.
        let dist = houseBehaviourHypot([dx,dy,dz])
        if dist <= speed || dist == 0 {
            sp.x = p[0]; sp.y = p[1]; sp.z = p[2]; sp.path.removeFirst(); sp.moving = !sp.path.isEmpty
        } else {
            let k = speed / dist; sp.x += dx*k; sp.y += dy*k; sp.z += (p[2]-sp.z)*k; sp.moving = true
        }
    }
}
