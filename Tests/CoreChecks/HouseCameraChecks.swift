import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

/// The camera of the SpriteKit house (the page's VIEW / zoomAt / panBy / glideTo / followTo / stepHome) and what the pointer picks
/// (updateTip's card, safeText, the hit rectangle of a Clawd, roomUnder, roomNear, focusRoom). The page itself is compared in
/// scripts/house-atlas/interact-proof.sh; these are the numbers that do not need it.
struct HouseCameraChecks {
    private func layout() -> HouseLayout {
        HouseLayout.make(projects: ["Agent-Notch", "hexhaven", "world"], layout: .islands, canvas: .init(width: 1728, height: 1117, dpr: 2))
    }
    private func camera(_ l: HouseLayout) -> HouseCamera {
        HouseCamera(layout: l, innerWidth: 1728, innerHeight: 1117, insets: .init(top: 32, bottom: 70, right: 120))
    }
    private func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }

    func all() throws {
        try zoomClamps()
        try panAtOverview()
        try glide()
        try follow()
        try autoReset()
        try shift()
        try rebased()
        print("houseCameraChecks: zoom clamps, pan, glide, follow, 30 s reset, shift, rebase")
    }

    func zoomClamps() throws {
        let l = layout()
        var c = camera(l)
        c.zoomAt(100, x: 800, y: 500, now: 0)
        XCTAssertEqual(c.target.zoom, 6, "zoom stops at 6")
        c.zoomAt(1e-6, x: 800, y: 500, now: 1)
        XCTAssertTrue(c.target.zoom == 1 && c.target.at == l.view.home, "zooming out below 1.001 goes home")
        c.zoomAt(2, x: 800, y: 500, now: 2)
        XCTAssertTrue(near(c.target.zoom, 2), "factor multiplies the target, not the pose")
        c.zoomAt(1.5, x: 800, y: 500, now: 3)
        XCTAssertTrue(near(c.target.zoom, 3), "pinches add up before the view has caught up")
        XCTAssertTrue(c.pose.zoom == 1, "the pose has not moved before a step")
    }

    func panAtOverview() throws {
        var c = camera(layout())
        c.panBy(dx: 50, dy: 50, now: 0)
        XCTAssertTrue(!c.isMoving && c.pose.zoom == 1, "two fingers do nothing at the overview")
        c.zoomAt(2, x: 864, y: 558, now: 0)
        let before = c.target
        c.panBy(dx: 30, dy: -20, now: 1)
        let p = c.base * before.zoom
        XCTAssertTrue(near(c.target.at[0], before.at[0] - 30 * c.dpr / p) && near(c.target.at[1], before.at[1] + 20 * c.dpr / p), "content follows the fingers")
    }

    func glide() throws {
        let l = layout()
        var c = camera(l)
        let to = HouseCamera.Pose(zoom: 4, at: [l.view.home[0] + 100, l.view.home[1] - 60])
        c.glideTo(to, now: 1000)
        XCTAssertTrue(c.isMoving && c.target == to, "a glide is headed for its target")
        c.step(now: 1000, dt: 16)
        XCTAssertTrue(near(c.pose.zoom, 1) && c.pose.at == l.view.home, "a glide starts where it was")
        c.step(now: 1210, dt: 16)
        XCTAssertTrue(near(c.pose.zoom, 2), "half way in time is half way in log zoom (ease in/out is 0.5 at 0.5)")
        XCTAssertTrue(near(c.pose.at[0], l.view.home[0] + 50) && near(c.pose.at[1], l.view.home[1] - 30), "and half way in distance")
        c.step(now: 1100, dt: 16)
        let e = 4 * pow(100.0 / 420, 3)
        XCTAssertTrue(near(c.pose.at[0], l.view.home[0] + 100 * e), "cubic ease in")
        c.step(now: 1420, dt: 16)
        XCTAssertTrue(c.pose == to && !c.isMoving, "a glide ends exactly on its target after 420 ms")
    }

    func follow() throws {
        let l = layout()
        var c = camera(l)
        c.zoomAt(3, x: 864, y: 558, now: 0)
        let goal = c.target
        var t = 0.0, steps = 0
        while c.isMoving && steps < 2000 { t += 16; c.step(now: t, dt: 16); steps += 1 }
        XCTAssertTrue(!c.isMoving && c.pose == goal, "following converges and lands exactly on the target")
        XCTAssertTrue(steps > 10 && steps < 400, "and takes a visible time, not one frame")
        let k = 1 - exp(-1.0 / 60) // dt below one millisecond counts as one
        var d = camera(l)
        d.zoomAt(2, x: 864, y: 558, now: 0)
        d.step(now: 1, dt: 0)
        XCTAssertTrue(near(log(d.pose.zoom), log(d.target.zoom) * k, 1e-12), "dt is at least 1 ms")
    }

    func autoReset() throws {
        var c = camera(layout())
        c.zoomAt(2, x: 864, y: 558, now: 0)
        var t = 0.0
        while c.isMoving { t += 16; c.step(now: t, dt: 16) }
        XCTAssertTrue(c.homeOn, "the overview button shows while zoomed")
        c.step(now: 29_000, dt: 16)
        XCTAssertTrue(!c.isMoving && c.pose.zoom > 1, "still zoomed 29 s after the last touch")
        c.step(now: 30_100, dt: 16)
        XCTAssertTrue(c.isMoving && near(c.target.zoom, 1), "half a minute untouched sends it home")
        c.step(now: 30_100 + 420, dt: 16)
        XCTAssertTrue(c.pose.zoom == 1 && !c.isMoving, "and it arrives")
        c.step(now: 31_000, dt: 16)
        XCTAssertTrue(!c.homeOn, "the button goes away")
        var d = camera(layout())
        d.zoomAt(2, x: 864, y: 558, now: 0)
        t = 0
        while d.isMoving { t += 16; d.step(now: t, dt: 16) }
        d.panBy(dx: 5, dy: 5, now: 25_000)
        d.step(now: 40_000, dt: 16)
        XCTAssertTrue(near(d.target.zoom, 2), "15 s after the last touch it stays")
    }

    func shift() throws {
        let l = layout()
        let c = camera(l)
        let home = c.shiftFromHome(HouseCamera.Pose(zoom: 1, at: l.view.home))
        XCTAssertTrue(home.x == 0 && home.y == 0, "the overview moves nothing")
        let p = HouseCamera.Pose(zoom: 2, at: [l.view.home[0] + 10, l.view.home[1] + 20])
        let q = c.toLayout(x: 864, y: 558, pose: p)
        let back = c.toLayout(x: 864, y: 558, pose: HouseCamera.Pose(zoom: 1, at: l.view.home))
        XCTAssertTrue(q.x != back.x, "a zoomed view maps the cursor elsewhere")
        // zooming at a point keeps the layout point under the cursor where it was
        var d = camera(l)
        let under = d.toLayout(x: 600, y: 300)
        d.zoomAt(3, x: 600, y: 300, now: 0)
        let t = d.target, u = d.toLayout(x: 600, y: 300, pose: t)
        XCTAssertTrue(abs(under.x - u.x) < 2 && abs(under.y - u.y) < 2, "the point under the cursor stays under the cursor (\(under) / \(u))")
    }

    func rebased() throws {
        let l = layout()
        var c = camera(l)
        c.zoomAt(2, x: 864, y: 558, now: 0)
        var t = 0.0
        while c.isMoving { t += 16; c.step(now: t, dt: 16) }
        let l2 = HouseLayout.make(projects: ["Agent-Notch", "hexhaven", "world", "extra"], layout: .islands, canvas: .init(width: 1728, height: 1117, dpr: 2))
        let r = c.rebased(layout: l2)
        XCTAssertTrue(r.pose == c.pose && r.homeOn, "a project joining leaves a zoomed view where it is")
        var g = camera(l)
        g.zoomAt(2, x: 864, y: 558, now: 0) // a zoom that has only just started: pose.zoom is still 1
        let kept = g.rebased(layout: l2)
        XCTAssertTrue(g.pose.zoom == 1 && kept.isMoving && kept.target.zoom == g.target.zoom, "a click in the frame of a relayout is not lost")
        let o = camera(l).rebased(layout: l2)
        XCTAssertTrue(o.pose.zoom == 1 && o.pose.at == l2.view.home, "and an overview follows the new home")
    }
}
