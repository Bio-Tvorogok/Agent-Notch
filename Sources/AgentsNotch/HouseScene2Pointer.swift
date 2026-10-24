import AppKit
import NotchCore
import SpriteKit

/// The pointer in the SpriteKit house, as room/index.html answers it: `room.pointer / leave / click / zoom / pan / resetView`.
/// Coordinates are the window's points, top-left origin (the page's CSS pixels). Hit tests run on the overview's canvas coordinates
/// (the layout's), so the pointer is moved back through the view first.
extension HouseScene2 {
    // MARK: the room API

    func pointerMoved(x: Double, y: Double) {
        pointer = (x, y)
        updateHover()
    }

    func pointerLeft() {
        pointer = nil
        updateHover()
    }

    /// room.click: the overview button, then a Clawd (opens it), then a room (flies to it) or the sky (flies back out).
    func pointerClicked(x: Double, y: Double) {
        guard houseCamera != nil else { return }
        if houseCamera!.homeOn, homeButtonRect.contains(CGPoint(x: x, y: y)) { resetView(); return }
        pointer = (x, y)
        updateHover()
        let c = houseCamera!, q = c.toLayout(x: x, y: y)
        if let b = behaviour, let e = b.eggs, e.click(x: q.x, y: q.y, at: b.time, overHouse: hoveredId != nil || HouseHit.roomUnder(layout, q.x, q.y) != nil) { stir(); return }
        if let id = hoveredId { onOpen?(id); return }
        let zoomed = c.target.zoom > 1.01
        let room = zoomed ? HouseHit.roomUnder(layout, q.x, q.y) : HouseHit.roomNear(layout, q.x, q.y, signs: allSignHits())
        if let room { houseCamera!.glideTo(HouseHit.focusPose(room, in: layout, camera: c), now: nowMs()); moved() }
        else if zoomed { resetView() }
    }

    func zoom(_ factor: Double, x: Double, y: Double) {
        guard houseCamera != nil else { return }
        houseCamera!.zoomAt(factor, x: x, y: y, now: nowMs())
        moved()
    }

    func pan(dx: Double, dy: Double) {
        guard houseCamera != nil else { return }
        houseCamera!.panBy(dx: dx, dy: dy, now: nowMs())
        moved()
    }

    func resetView() {
        guard houseCamera != nil else { return }
        houseCamera!.resetView(now: nowMs())
        moved()
    }

    private func moved() {
        autoResetTimer?.invalidate(); autoResetTimer = nil
        stir()
        if pointer != nil { updateHover() }
    }

    // MARK: hover

    /// Where an agent's feet are on the overview's canvas.
    private func hoverFeet(_ sp: HouseSprite, sim: HouseSim) -> (x: Double, y: Double)? {
        if sp.fall != nil, let f = fallPlace(sp) { return (f.x, f.y) }
        guard let at = place(sp, sim: sim) else { return nil }
        return (at.x, at.y)
    }

    /// The Clawd under the pointer: the last one in the simulation's order whose hit rectangle holds it (the page's updateTip).
    func agentAt(canvas q: (x: Double, y: Double)) -> HouseSprite? {
        guard let sim else { return nil }
        var found: HouseSprite?
        for sp in sim.sprites {
            guard sp.behaviour.agent != nil, sp.alpha >= 0.5, let f = hoverFeet(sp, sim: sim) else { continue }
            let t = (sp.context ?? 0) >= 0.9 ? clockMillis * 0.5 : clockMillis
            let r = HouseHit.agentRect(vendor: sp.behaviour.vendor, small: sp.small, state: sp.state ?? "", moving: sp.moving, x: f.x, y: f.y, t: t)
            if HouseHit.contains(r, q.x, q.y) { found = sp }
        }
        return found
    }

    /// Recomputes what is under the pointer and tells the host when the hover card changes.
    func updateHover() {
        var tip: HouseHit.Tip?
        hoveredId = nil
        if let p = pointer, let c = houseCamera {
            let q = c.toLayout(x: p.x, y: p.y)
            if let sp = agentAt(canvas: q), let a = sp.behaviour.agent {
                hoveredId = a.id
                tip = HouseHit.tip(agent: a, spriteState: sp.state, cursor: p)
            }
        }
        if tip != lastTip { lastTip = tip; onTip?(tip) }
    }

    // MARK: signs

    private func signName(_ r: HouseLayout.Room) -> String {
        r.theme == "bath" || r.theme == "kitchen" || r.theme == "roof" ? (Self.sharedNames[r.key] ?? r.name) : r.name
    }

    /// The signs' hit rectangles of every room (the page's r.signHit), in canvas pixels.
    func allSignHits() -> [String: [Double]] {
        if signHits.count != layout.rooms.count {
            for r in layout.rooms { signHits[r.key] = painter.signHit(room: r, name: signName(r), vi: light.variant) }
        }
        return signHits
    }
}
