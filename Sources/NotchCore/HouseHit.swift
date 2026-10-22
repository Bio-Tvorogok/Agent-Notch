import Foundation

/// What the pointer picks in the house, as the page does it (room/index.html: updateTip, safeText, STATE_TEXT, roomOutline, inside,
/// roomUnder, roomNear, focusRoom, and the hit rectangle drawClawd leaves on every Clawd). Pure geometry: the host says where things are.
public enum HouseHit {
    // MARK: the tip

    /// The payload `room` posts to the app for the hover card (RoomTip.show reads exactly these fields).
    public struct Tip: Equatable, Sendable {
        public var title, status, color, detail: String
        public var x, y: Double
        public init(title: String, status: String, color: String, detail: String, x: Double, y: Double) {
            self.title = title; self.status = status; self.color = color; self.detail = detail; self.x = x; self.y = y
        }
        /// The dictionary RoomTip.show takes.
        public var payload: [String: Any] { ["title": title, "status": status, "color": color, "detail": detail, "x": x, "y": y] }
    }

    static let stateText: [String: (String, String)] = [
        "working": ("работает", "#3fb950"), "waiting": ("ждёт тебя", "#f5b400"), "error": ("застрял на ошибке", "#e5534b"), "done": ("закончил", "#aaa"),
    ]

    /// safeText: one line of the command, secrets masked, at most 70 characters.
    public static func safeText(_ raw: String?) -> String {
        var t = (raw ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        func sub(_ pattern: String, _ with: String) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: with)
        }
        sub(#"\b([A-Z0-9_]*(PASS(WORD)?|TOKEN|SECRET|KEY|AUTH|CREDENTIALS?)[A-Z0-9_]*)=("[^"]*"|'[^']*'|\S+)"#, "$1=•••")
        sub(#"(--?(password|token|secret|api-key|key)[= ])("[^"]*"|'[^']*'|\S+)"#, "$1•••")
        let u = Array(t.utf16)
        return u.count > 70 ? String(decoding: u[0..<69], as: UTF16.self) + "…" : t
    }

    /// The hover card of an agent. `state` is the sprite's own state ("shower" shows the shower line).
    public static func tip(agent a: HouseAgentRow, spriteState: String?, cursor: (x: Double, y: Double)) -> Tip {
        let (stt, col) = stateText[a.state] ?? (a.state, "#aaa")
        let model = (a.model ?? "").isEmpty ? "" : " · " + a.model!
        let detail = spriteState == "shower" ? "в душе 🚿" : safeText(a.state == "waiting" && !(a.ask ?? "").isEmpty ? a.ask : a.activity)
        return Tip(title: safeText(a.title), status: "\(stt) · \(a.project ?? "")\(model)", color: col, detail: detail, x: cursor.x, y: cursor.y)
    }

    // MARK: Clawds

    /// The look of a Clawd as drawClawd's LOOKS table has it: cells wide, rows, and the legs' height in cells.
    public static func cells(vendor: String, small: Bool) -> (w: Int, rows: Int, legs: Int) {
        if vendor == "codex" { return small ? (8, 6, 1) : (12, 10, 2) }
        return small ? (8, 4, 1) : (12, 6, 2)
    }

    /// sp.hit: [x, y, w, h] in canvas pixels, from the feet (X, Y). `t` is the page's draw time (halved for a drowsy Clawd by the caller).
    public static func agentRect(vendor: String, small: Bool, state: String, moving: Bool, x X: Double, y Y: Double, t: Double) -> [Double] {
        let C = 2.0, k = cells(vendor: vendor, small: small)
        let hop = state == "waiting" && !moving ? houseRound(abs(sin(t / 260)) * 3) : (moving ? Double(Int(floor(t / 110)) % 2) * C : 0)
        let left = houseRound(X - Double(k.w) * C / 2), top = houseRound(Y - Double(k.rows + k.legs) * C - hop)
        return [left - 2 * 2, top - 2 * 2, Double(k.w + 4) * C, Double(k.rows + k.legs + 4) * C]
    }

    public static func contains(_ r: [Double], _ x: Double, _ y: Double) -> Bool { x >= r[0] && x <= r[0] + r[2] && y >= r[1] && y <= r[1] + r[3] }

    // MARK: rooms

    static let S = 2.0, WH = 60.0, SLAB = 6.0

    static func isOpen(_ r: HouseLayout.Room) -> Bool { r.theme == "roof" || r.key == "__yard" }
    static func isIsland(_ r: HouseLayout.Room, in l: HouseLayout) -> Bool { r.key != "__yard" && r.floor == 0 && r.tower > 0 }

    /// roomOutline(r, world, island): a room's outline in canvas pixels (the layout's), or in world pixels with `world`.
    public static func roomOutline(_ r: HouseLayout.Room, in l: HouseLayout, world: Bool, island: Bool) -> [[Double]] {
        let ox = world ? (r.wx ?? 0) : r.ox, oy = world ? (r.wy ?? 0) : r.oy + r.drop
        func P(_ x: Double, _ y: Double, _ z: Double) -> [Double] { [ox + (x - y) * 8 * S, oy + (x + y) * 4 * S - z * S] }
        let top = isOpen(r) ? 26 : WH
        let ground = island && r.floor == 0
        let m = ground ? 1.2 : 0, bot = ground ? -SLAB - 14 : -SLAB
        let mr = island && isIsland(r, in: l) ? 2 : m
        let gy = ground ? r.NY + 2 : r.NY + m
        return [P(-m, -m, top), P(r.NX + mr, -m, top), P(r.NX + mr, -m, bot), P(r.NX + mr, gy, bot), P(-m, gy, bot), P(-m, gy, top)]
    }

    public static func inside(_ pts: [[Double]], _ x: Double, _ y: Double) -> Bool {
        var hit = false, j = pts.count - 1
        for i in 0..<pts.count {
            let xi = pts[i][0], yi = pts[i][1], xj = pts[j][0], yj = pts[j][1]
            if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi { hit.toggle() }
            j = i
        }
        return hit
    }

    /// roomUnder(x, y): the front-most room whose outline holds the point.
    public static func roomUnder(_ l: HouseLayout, _ x: Double, _ y: Double) -> HouseLayout.Room? {
        let byKey = Dictionary(l.rooms.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for item in l.drawOrder.reversed() {
            if let r = byKey[item.key], inside(roomOutline(r, in: l, world: false, island: true), x, y) { return r }
        }
        return nil
    }

    /// roomNear(x, y): a sign, then a room or its island, then the room whose outline is nearest (within about half a room's width).
    /// `signs` are the signs' hit rectangles by room key, in canvas pixels.
    public static func roomNear(_ l: HouseLayout, _ x: Double, _ y: Double, signs: [String: [Double]]) -> HouseLayout.Room? {
        for r in l.rooms.reversed() { if let h = signs[r.key], contains(h, x, y) { return r } }
        if let r0 = roomUnder(l, x, y) { return r0 }
        func seg(_ a: [Double], _ b: [Double]) -> Double {
            let dx = b[0] - a[0], dy = b[1] - a[1]
            let k = max(0, min(1, ((x - a[0]) * dx + (y - a[1]) * dy) / (dx * dx + dy * dy == 0 ? 1 : dx * dx + dy * dy)))
            return hypot(x - a[0] - k * dx, y - a[1] - k * dy)
        }
        var best: HouseLayout.Room?, bd = Double.infinity
        for r in l.rooms {
            let pts = roomOutline(r, in: l, world: false, island: true)
            var d = Double.infinity
            for i in 0..<pts.count { d = min(d, seg(pts[i], pts[(i + 1) % pts.count])) }
            if d <= (r.NX + r.NY) * 4 * S && d < bd { bd = d; best = r }
        }
        return best
    }

    /// focusRoom(r): the room fills about 70% of the screen's height, in whole quarter steps of device pixels.
    public static func focusPose(_ r: HouseLayout.Room, in l: HouseLayout, camera c: HouseCamera) -> HouseCamera.Pose {
        let pts = roomOutline(r, in: l, world: true, island: false), xs = pts.map { $0[0] }, ys = pts.map { $0[1] }
        let x0 = xs.min()!, x1 = xs.max()!, y0 = ys.min()!, y1 = ys.max()!
        var z = min(0.7 * c.innerHeight * c.dpr / (y1 - y0), 0.9 * c.innerWidth * c.dpr / (x1 - x0)) / c.base
        z = min(HouseCamera.maxZoom, max(1.25, houseRound(z * c.base * 4) / 4 / c.base))
        return HouseCamera.Pose(zoom: z, at: [(x0 + x1) / 2, (y0 + y1) / 2])
    }
}
