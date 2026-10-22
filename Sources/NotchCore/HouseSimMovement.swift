import Foundation

extension HouseSim {
    func stepSprites(_ dt: Double) {
        for sp in sprites {
            let delta = sp.fade - sp.alpha
            sp.alpha += (delta > 0 ? 1 : delta < 0 ? -1 : 0) * min(abs(delta), dt / 450)
            if sp.leaving && sp.alpha <= 0.01 {
                removeSprite(sp); continue
            }
            if sp.fall != nil { continue }
            if sp.frozen || time < (sp.frozenUntil ?? -.infinity) { sp.moving = false; continue }
            if sp.exit && sp.path.isEmpty {
                let r = room(sp.room!)
                let x = r.ox + (sp.x - sp.y) * 8 * 2
                let y = r.oy + r.drop + (sp.x + sp.y) * 4 * 2 - sp.z * 2
                // YARD has no wx/wy in JS: exiting it produces NaN world
                // coordinates and never meets drawFallers' removal threshold.
                let wx = r.key == "__yard" ? Double.nan : (r.wx ?? 0)
                let wy = r.key == "__yard" ? Double.nan : (r.wy ?? 0)
                sp.fall = .init(x: x-r.ox+wx, y: y-r.oy+wy, t0: time, seed: sp.seed)
                sp.room = nil; sp.state = "fall"; sp.moving = false; continue
            }
            sp.waving = false
            guard let n = sp.path.first else { sp.moving = false; sp.seated = sp.z > 3; continue }
            sp.seated = false
            if n.lift != nil {
                if n.since == nil { n.since = time }
                sp.moving = false; continue
            }
            let speed = dt / 1000 * (sp.small ? 2.3 : 1.9) * ((sp.context ?? 0) >= 0.9 ? 0.55 : 1) * ((sp.speed ?? 0) == 0 ? 1 : sp.speed!)
            if let bridge = n.bridge {
                let l = link(bridge).geometry
                if !HouseRoutes.same(sp.onBridge?.pair, bridge) {
                    sp.onBridge = .init(kind: l.kind, pair: bridge, u: n.from ?? ((n.to ?? 0) > 0.5 ? 0 : 1)); sp.room = nil
                }
                var ob = sp.onBridge!
                let target = n.to!, dir = target >= ob.u ? 1.0 : -1.0, step = speed / max(0.5,l.len)
                ob.forward = dir > 0
                if abs(target-ob.u) <= step {
                    ob.u = target; sp.path.removeFirst()
                    let next = sp.path.first
                    if next == nil || !(HouseRoutes.same(next?.bridge,bridge) || HouseRoutes.same(next?.call,bridge) || (next?.wait ?? 0) != 0) {
                        sp.onBridge = nil
                    } else { sp.onBridge = ob }
                } else { ob.u += dir * step; sp.onBridge = ob; sp.moving = true }
                continue
            }
            if let wait = n.wait, wait != 0 {
                if (n.until ?? 0) == 0 { n.until = time + wait }
                sp.moving = false; sp.seated = true
                if time >= n.until! { sp.path.removeFirst() }
                continue
            }
            if let call = n.call {
                let l = link(call)
                if l.aim == n.aim && l.turn == nil { sp.path.removeFirst(); continue }
                if n.since == nil { n.since = time }
                sp.waving = true; sp.moving = false; continue
            }
            if n.jump == true {
                sp.room = n.r; let p = n.p!; sp.x = p[0]; sp.y = p[1]; sp.z = p[2]
                sp.path.removeFirst(); if n.poof == true { sp.alpha = 0 }; continue
            }
            let p = n.p!, dx = p[0]-sp.x, dy = p[1]-sp.y, dz = (p[2]-sp.z)/14
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
}
