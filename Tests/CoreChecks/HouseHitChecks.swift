import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

/// What the pointer picks in the house, as the page's updateTip, safeText, roomOutline, roomUnder, roomNear and focusRoom decide it.
struct HouseHitChecks {
    private func layout() -> HouseLayout {
        HouseLayout.make(projects: ["Agent-Notch", "hexhaven", "world"], layout: .islands, canvas: .init(width: 1728, height: 1117, dpr: 2))
    }

    func all() throws {
        try safeText()
        try tip()
        try agentRect()
        try rooms()
        try focus()
        print("houseHitChecks: safeText, tip, agent rectangle, rooms, focus")
    }

    func safeText() throws {
        XCTAssertEqual(HouseHit.safeText(nil), "", "nothing is empty")
        XCTAssertEqual(HouseHit.safeText("  a \n\t b  "), "a b", "whitespace is one space")
        XCTAssertEqual(HouseHit.safeText("OPENAI_API_KEY=sk-abc123 npm test"), "OPENAI_API_KEY=••• npm test", "a secret in the environment is masked")
        XCTAssertEqual(HouseHit.safeText("curl --token abc123 https://x"), "curl --token ••• https://x", "a secret flag is masked")
        XCTAssertEqual(HouseHit.safeText("run --password=\"my pass\" now"), "run --password=••• now", "a quoted secret too")
        let long = String(repeating: "x", count: 100)
        let cut = HouseHit.safeText(long)
        XCTAssertTrue(cut.utf16.count == 70 && cut.hasSuffix("…"), "70 UTF-16 units, the last one an ellipsis")
        XCTAssertEqual(HouseHit.safeText(String(repeating: "y", count: 70)), String(repeating: "y", count: 70), "exactly 70 stays")
    }

    func tip() throws {
        var a = HouseAgentRow(id: "a0", project: "hexhaven", vendor: "claude", state: "working", title: "Fix the door", activity: "npm test", model: "opus")
        let t = HouseHit.tip(agent: a, spriteState: nil, cursor: (10, 20))
        XCTAssertEqual(t.title, "Fix the door")
        XCTAssertEqual(t.status, "работает · hexhaven · opus")
        XCTAssertEqual(t.color, "#3fb950")
        XCTAssertEqual(t.detail, "npm test")
        XCTAssertTrue(t.x == 10 && t.y == 20, "the card sits at the cursor")
        XCTAssertEqual(Set(t.payload.keys), ["title", "status", "color", "detail", "x", "y"], "the fields RoomTip.show reads")
        a.state = "waiting"; a.ask = "Run rm -rf?"
        XCTAssertEqual(HouseHit.tip(agent: a, spriteState: nil, cursor: (0, 0)).detail, "Run rm -rf?", "a waiting agent shows its question")
        XCTAssertEqual(HouseHit.tip(agent: a, spriteState: nil, cursor: (0, 0)).color, "#f5b400")
        XCTAssertEqual(HouseHit.tip(agent: a, spriteState: "shower", cursor: (0, 0)).detail, "в душе 🚿", "in the shower")
        a.model = nil; a.state = "done"
        let d = HouseHit.tip(agent: a, spriteState: nil, cursor: (0, 0))
        XCTAssertTrue(d.status == "закончил · hexhaven" && d.color == "#aaa", "no model, no trailing dot")
        a.state = "error"
        XCTAssertEqual(HouseHit.tip(agent: a, spriteState: nil, cursor: (0, 0)).status, "застрял на ошибке · hexhaven")
    }

    func agentRect() throws {
        let r = HouseHit.agentRect(vendor: "claude", small: false, state: "working", moving: false, x: 100, y: 200, t: 0)
        // 12 cells of 2 px wide, 6 + 2 legs rows: left = 100 - 12, top = 200 - 16; the rectangle is 4 px wider on each side
        XCTAssertEqual(r, [84.0, 180.0, 32.0, 24.0], "a Clawd's hit box")
        XCTAssertTrue(HouseHit.contains(r, 100, 195) && !HouseHit.contains(r, 100, 100), "inside and outside")
        let s = HouseHit.agentRect(vendor: "claude", small: true, state: "working", moving: false, x: 100, y: 200, t: 0)
        XCTAssertTrue(s[2] < r[2] && s[3] < r[3], "a sub-agent is smaller")
        let c = HouseHit.agentRect(vendor: "codex", small: false, state: "working", moving: false, x: 100, y: 200, t: 0)
        XCTAssertTrue(c[3] > r[3], "a Codex is taller")
        let hop = HouseHit.agentRect(vendor: "claude", small: false, state: "waiting", moving: false, x: 100, y: 200, t: 260 * .pi / 2)
        XCTAssertEqual(hop[1], r[1] - 3, "a waiting Clawd hops by up to 3 px")
    }

    func rooms() throws {
        let l = layout()
        for r in l.rooms {
            let o = HouseHit.roomOutline(r, in: l, world: false, island: true)
            XCTAssertEqual(o.count, 6, "\(r.key) outline has six corners")
            let cx = o.map { $0[0] }.reduce(0, +) / 6, cy = o.map { $0[1] }.reduce(0, +) / 6
            XCTAssertTrue(HouseHit.inside(o, cx, cy), "\(r.key) holds its own centre")
            XCTAssertTrue(!HouseHit.inside(o, cx + 100_000, cy), "and not a far point")
        }
        // the front-most room under a point of its own outline is that room, or one drawn in front of it
        for r in l.rooms {
            let o = HouseHit.roomOutline(r, in: l, world: false, island: true)
            let cx = o.map { $0[0] }.reduce(0, +) / 6, cy = o.map { $0[1] }.reduce(0, +) / 6
            XCTAssertTrue(HouseHit.roomUnder(l, cx, cy) != nil, "\(r.key): something is under its centre")
        }
        XCTAssertTrue(HouseHit.roomUnder(l, -50_000, -50_000) == nil, "nothing under empty sky")
        guard let r = l.rooms.first(where: { $0.key != "__yard" }) else { return XCTFail("no room") }
        let o = HouseHit.roomOutline(r, in: l, world: false, island: true)
        let sign = [String: [Double]]()
        XCTAssertTrue(HouseHit.roomNear(l, -50_000, -50_000, signs: sign) == nil, "far from every room: no room, the view goes home")
        let sp = [r.key: [5000.0, 5000.0, 30.0, 10.0]]
        XCTAssertEqual(HouseHit.roomNear(l, 5010, 5005, signs: sp)?.key, r.key, "a click on a sign picks its room")
        let edge = o[0]
        XCTAssertTrue(HouseHit.roomNear(l, edge[0] - 6, edge[1] - 6, signs: sign) != nil, "just off a room's edge still finds it")
    }

    func focus() throws {
        let l = layout()
        let c = HouseCamera(layout: l, innerWidth: 1728, innerHeight: 1117, insets: .init(top: 32, bottom: 70, right: 120))
        for r in l.rooms {
            let p = HouseHit.focusPose(r, in: l, camera: c)
            XCTAssertTrue(p.zoom >= 1.25 && p.zoom <= 6, "\(r.key): zoom inside [1.25, 6]")
            let quarter = p.zoom * c.base * 4
            XCTAssertTrue(abs(quarter - quarter.rounded()) < 1e-9, "\(r.key): a whole quarter of a device pixel per art pixel")
            let w = HouseHit.roomOutline(r, in: l, world: true, island: false)
            XCTAssertTrue(abs(p.at[0] - (w.map { $0[0] }.min()! + w.map { $0[0] }.max()!) / 2) < 1e-9, "\(r.key): centred on the room")
        }
    }
}
