import Foundation

final class HouseLayoutBuilder {
    typealias H = HouseLayout
    let style: H.Style
    let canvas: H.Canvas
    let insets: H.Insets
    var rooms: [H.Room] = []
    var stack: [[Int]] = []
    var lift: H.Lift?
    var links: [H.Link] = []
    var hulls: [[[Double]]] = []

    init(projects: [String], style: H.Style, canvas: H.Canvas, insets: H.Insets, themes: [H.ThemeChoice]) {
        self.style = style; self.canvas = canvas; self.insets = insets
        // ensureRoom: shared rooms precede projects, even though roof is stacked last.
        rooms = [H.Room(key: "__bath", name: "Ванная", theme: "bath", NX: 7, NY: 6),
                 H.Room(key: "__kitchen", name: "Кухня", theme: "kitchen", NX: 10, NY: 8),
                 H.Room(key: "__roof", name: "Крыша", theme: "roof", NX: 10, NY: 8)]
        var seen = Set<[UInt16]>()
        for project in projects {
            let name = project.isEmpty ? "—" : project
            if seen.insert(Array(name.utf16)).inserted {
                rooms.append(H.Room(key: "p:" + name, name: name, theme: H.projectTheme(name, choices: themes), NX: 10, NY: 8))
            }
        }
    }

    func make() -> H {
        // layout(): PER_TOWER = 3. In islands, each room after tower 0 gets
        // its own stack. The roof copies the dimensions of tower 0's top room.
        for i in rooms.indices where i != 2 {
            let t: Int
            if style == .islands && !stack.isEmpty && stack[0].count >= 3 {
                stack.append([]); t = stack.count - 1
            } else if let available = stack.firstIndex(where: { $0.count < 3 }) {
                t = available
            } else { stack.append([]); t = stack.count - 1 }
            rooms[i].tower = t; rooms[i].floor = stack[t].count; stack[t].append(i)
        }
        let top = rooms[stack[0].last!]
        rooms[2].tower = 0; rooms[2].floor = stack[0].count
        rooms[2].NX = top.NX; rooms[2].NY = top.NY; stack[0].append(2)
        if style == .islands {
            lift = liftPlan(stack[0])
            islandPlan(Array(stack.dropFirst()).map { $0[0] }, tower: stack[0])
        }
        // layout / place: W = 18*8*S, F = FLOOR_STEP*S.
        for (t, indices) in stack.enumerated() {
            let base: [Double]
            switch style {
            case .steps: base = [Double(t) * (288 + 140), -Double(t) * 0.62 * 188]
            case .towers: base = [Double(t) * (288 + 80), 0]
            case .islands:
                let r = rooms[indices[0]]
                base = [(r.tx - r.ty) * 8 * 2, (r.tx + r.ty) * 4 * 2 - r.tz! * 2]
            }
            var wy = 0.0
            for (f, i) in indices.enumerated() {
                if f > 0 { wy += rooms[indices[f - 1]].NY - rooms[i].NY }
                rooms[i].wx = houseRound(base[0] - wy * 8 * 2)
                rooms[i].wy = houseRound(base[1] - Double(f) * 188 + wy * 4 * 2)
            }
        }
        var x0 = Double.infinity, y0 = Double.infinity
        var x1 = -Double.infinity, y1 = -Double.infinity
        for r in rooms {
            let island = style == .islands && r.floor == 0 && r.tower > 0
            let gx = island ? 3.2 : 1.5, gy = island ? 3.4 : 1.5
            x0 = min(x0, r.wx! - (r.NY + gy) * 8 * 2)
            x1 = max(x1, r.wx! + (r.NX + gx) * 8 * 2 + (r.tower == 0 ? 120 : 0))
            y0 = min(y0, r.wy! - (60 + 12) * 2)
            y1 = max(y1, r.wy! + (r.NX + r.NY + (island ? 4 : 2.4)) * 4 * 2 + (6 + 16) * 2)
        }
        if style == .islands {
            let b = rooms[0]
            y1 = max(y1, b.wy! + (16.6 + b.NY + 2) * 4 * 2 + (6 + 18) * 2)
            x1 = max(x1, b.wx! + (16.6 - 1.0 + 1.5) * 8 * 2)
            for h in hulls { for p in h { x0 = min(x0, p[0]); x1 = max(x1, p[0]); y0 = min(y0, p[1]); y1 = max(y1, p[1]) } }
        }
        let dpr = canvas.dpr == 0 ? 1 : canvas.dpr
        let fit = min((canvas.width - insets.right) * dpr * 0.96 / (x1 - x0),
                      (canvas.height - insets.top - insets.bottom) * dpr * 0.94 / (y1 - y0))
        let base = fit >= 3 ? floor(fit * 4) / 4 : max(1, floor(fit * 2) / 2)
        let home = [(x0 + x1) / 2, (y0 + y1) / 2]
        // applyView() at VIEW.zoom = 1, VIEW.at = VIEW.home.
        let w = ceil(canvas.width * dpr / base), h = ceil(canvas.height * dpr / base)
        let up = houseRound((insets.top - insets.bottom) / 2 * dpr / base)
        let aside = houseRound(insets.right / 2 * dpr / base)
        for i in rooms.indices {
            rooms[i].ox = houseRound(w / 2 - aside + rooms[i].wx! - home[0])
            rooms[i].oy = houseRound(h / 2 + up + rooms[i].wy! - home[1])
        }
        let view = H.View(PXD: base, DPR: dpr, width: w, height: h, cssWidth: w * base / dpr, cssHeight: h * base / dpr,
                          base: base, home: home, at: home)
        let (escapes, shapes) = escapePlan()
        var made = H(rooms: rooms, lift: lift, links: links, hulls: hulls, yard: yardPlan(), escapes: escapes, escapeShapes: shapes,
                 drawOrder: drawOrder(), view: view, worldFrame: H.Frame(ox: rooms[0].ox, oy: rooms[0].oy, drop: 0))
        made.style = style
        return made
    }

    // liftPlan(s), liftSlice(f), liftZ(k). Cabins start on the yard's grass.
    func liftPlan(_ s: [Int]) -> H.Lift {
        let nx = s.dropFirst().map { rooms[$0].NX }.max()!
        var wy = 0.0
        var fl: [H.LiftFloor] = []
        for (f, i) in s.enumerated() {
            if f > 0 { wy += rooms[s[f - 1]].NY - rooms[i].NY }
            let z = Double(f) * 94
            fl.append(H.LiftFloor(room: rooms[i].key, f: f, yoff: wy, z: z, levelZ: f == 0 ? -6 : z,
                                  slice: [f == 0 ? -20 : z - 6, f + 1 < s.count ? Double(f + 1) * 94 - 6 : nil]))
        }
        let shafts = (0..<2).map { i -> H.Shaft in
            let x0 = nx + 0.25 + Double(i) * (1.4 + 0.2)
            return H.Shaft(x0: x0, y0: -1, x1: x0 + 1.4, y1: 0.4, cx: x0 + 1.4 / 2, cy: (-1.0 + 0.4) / 2)
        }
        let cabins = shafts.enumerated().map { H.Cabin(kind: "lift", id: "lift\($0.offset)", sh: $0.element, z: -6, level: 0, len: 1) }
        return H.Lift(fl: fl, shafts: shafts, cabins: cabins, x0: shafts[0].x0, x1: shafts[1].x1, y0: -1, y1: 0.4, top: fl.last!.z + 34)
    }

    func drawOrder() -> [H.DrawItem] {
        if style == .islands {
            let towerD = rooms[0].NX / 2 + rooms[0].NY / 2
            var list = rooms.map { r in H.DrawItem(key: r.key, depth: r.tower == 0 ? towerD + Double(r.floor) * 1e-3
                                                     : r.tx + r.NX / 2 + r.ty + r.NY / 2) }
            for l in links {
                let depth: Double
                if l.kind == "stair" { depth = l.A[0] + l.A[1] + (cos(l.ang!) + sin(l.ang!)) * l.len / 2 }
                else { depth = (l.A[0] + l.B[0] + l.A[1] + l.B[1]) / 2 }
                list.append(H.DrawItem(key: l.id, depth: depth))
            }
            // JS sort is stable, including rooms/links with equal depth.
            return list.enumerated().sorted { a, b in
                a.element.depth! == b.element.depth! ? a.offset < b.offset : a.element.depth! < b.element.depth!
            }.map(\.element)
        }
        let groundY = stack.map { rooms[$0[0]].oy }
        return rooms.sorted { a, b in
            if groundY[a.tower] != groundY[b.tower] { return groundY[a.tower] < groundY[b.tower] }
            if a.tower != b.tower { return a.tower < b.tower }
            return a.floor < b.floor
        }.map { H.DrawItem(key: $0.key) }
    }
}
