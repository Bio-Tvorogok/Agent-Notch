import Foundation

// hull2, hullOf, hullsMeet and spanHull use the same point and loop order as JS.
// Collision decisions must precede view rounding; all computations use Double.
enum HouseHull {
    typealias Hull = [[Double]]
    static func hull2(_ points: Hull) -> Hull {
        let pts = points.sorted { $0[0] == $1[0] ? $0[1] < $1[1] : $0[0] < $1[0] }
        func cross(_ o: [Double], _ a: [Double], _ c: [Double]) -> Double {
            (a[0] - o[0]) * (c[1] - o[1]) - (a[1] - o[1]) * (c[0] - o[0])
        }
        var lo: Hull = [], up: Hull = []
        for p in pts {
            while lo.count >= 2 && cross(lo[lo.count - 2], lo[lo.count - 1], p) <= 0 { lo.removeLast() }
            lo.append(p)
        }
        for p in pts.reversed() {
            while up.count >= 2 && cross(up[up.count - 2], up[up.count - 1], p) <= 0 { up.removeLast() }
            up.append(p)
        }
        return Array(lo.dropLast()) + Array(up.dropLast())
    }
    static func of(_ b: [Double]) -> Hull {
        var pts: Hull = []
        for x in [b[0], b[3]] { for y in [b[1], b[4]] { for z in [b[2], b[5]] {
            pts.append([(x - y) * 8 * 2, (x + y) * 4 * 2 - z * 2])
        } } }
        return hull2(pts)
    }
    static func meet(_ a: Hull, _ b: Hull, margin: Double = 2) -> Bool {
        for p in [a, b] { for i in p.indices {
            let v = p[i], w = p[(i + 1) % p.count], nx = w[1] - v[1], ny = v[0] - w[0]
            let length = hypot(nx, ny), l = length == 0 ? 1 : length
            var a0 = Double.infinity, a1 = -Double.infinity, b0 = Double.infinity, b1 = -Double.infinity
            for q in a { let d = (q[0] * nx + q[1] * ny) / l; a0 = min(a0, d); a1 = max(a1, d) }
            for q in b { let d = (q[0] * nx + q[1] * ny) / l; b0 = min(b0, d); b1 = max(b1, d) }
            if a1 + margin <= b0 || b1 + margin <= a0 { return false }
        } }
        return true
    }
    static func core(_ r: HouseLayout.Room, _ x: Double, _ y: Double, _ z: Double) -> Hull {
        of([x, y, z - 6, x + r.NX, y + r.NY, z + 60])
    }
    static func body(_ r: HouseLayout.Room, _ x: Double, _ y: Double, _ z: Double, full: Bool = false) -> Hull {
        of([x - 1.2, y - 1.2, z - 6 - 14 - (full ? 32 : 0), x + r.NX + 2, y + r.NY + 2, z + 60 + 4])
    }
    static func span(_ a: [Double], _ b: [Double], _ z: Double, _ h: Double) -> Hull {
        of([min(a[0], b[0]) - 0.7, min(a[1], b[1]) - 0.7, z - 12,
            max(a[0], b[0]) + 0.7, max(a[1], b[1]) + 0.7, z + h + 16])
    }
}

extension HouseLayoutBuilder {
    private final class Node {
        let r: H.Room
        let tx, ty: Double
        let lv: Int
        let core, full, body: HouseHull.Hull
        init(_ r: H.Room, _ tx: Double, _ ty: Double, _ lv: Int) {
            self.r = r; self.tx = tx; self.ty = ty; self.lv = lv
            core = HouseHull.core(r, tx, ty, Double(lv) * 64)
            full = HouseHull.body(r, tx, ty, Double(lv) * 64, full: true)
            body = HouseHull.body(r, tx, ty, Double(lv) * 64)
        }
    }
    private struct Side { var last: Node?; var col: Node? }

    // PORTS / YARD_PORTS. Opposite kinds are selected explicitly by islandPlan.
    private func port(_ kind: String, _ r: H.Room) -> (q: [Double], d: [Double]) {
        switch kind {
        case "Yr": return ([16.6, 3.6], [1, 0])
        case "Yl": return ([-1.2, 7.5], [-1, 0])
        case "Rt": return ([r.NX + 2, 0.6], [1, 0])
        case "L": return ([-1.2, r.NY + 1], [-1, 0])
        case "F": return ([0.5, r.NY + 2], [0, 1])
        default: return ([r.NX + 1.4, -1.2], [0, -1]) // Bk
        }
    }

    func islandPlan(_ list: [Int], tower: [Int]) {
        // towerHulls(s): rooms, lift, ground and apple tree, in this order.
        var tCore: [HouseHull.Hull] = [], tFull: [HouseHull.Hull] = []
        var wy = 0.0
        for (f, i) in tower.enumerated() {
            let r = rooms[i]
            if f > 0 { wy += rooms[tower[f - 1]].NY - r.NY }
            let top = r.theme == "roof" ? 70.0 : 94 - 6
            let h = HouseHull.of([0, wy, Double(f) * 94 - 6, r.NX, wy + r.NY, Double(f) * 94 + top])
            tCore.append(h); tFull.append(h)
        }
        if let l = lift {
            let h = HouseHull.of([l.x0 - 0.2, l.y0 - 0.2, -6.0 - 14, l.x1 + 0.2, l.y1 + 0.9, l.top + 16])
            tCore.append(h); tFull.append(h)
        }
        tFull.append(HouseHull.of([-1.2, -1.2, -6.0 - 14 - 32, 16.6, rooms[tower[0]].NY + 2, 12]))
        tFull.append(HouseHull.of([12.2, 1.8, -6, 13.7, 3.0, 36]))
        var placed: [Node] = [], spans: [HouseHull.Hull] = []
        let yard = Node(H.Room(key: "__yard", name: "Двор", theme: "yard", NX: 16.5, NY: 7.85), 0, 0, 0)
        func clear(_ core: HouseHull.Hull, _ full: HouseHull.Hull, _ span: HouseHull.Hull? = nil,
                   _ near: Node? = nil, _ body: HouseHull.Hull? = nil) -> Bool {
            if tCore.contains(where: { HouseHull.meet($0, full) }) || tFull.contains(where: { HouseHull.meet($0, core) }) { return false }
            for n in placed {
                if n === near {
                    if HouseHull.meet(n.core, body!) || HouseHull.meet(n.body, core) { return false }
                } else if HouseHull.meet(n.full, full) { return false }
            }
            if spans.contains(where: { HouseHull.meet($0, full) }) { return false }
            if let span {
                if placed.contains(where: { $0 !== near && HouseHull.meet($0.core, span) }) || tCore.contains(where: { HouseHull.meet($0, span) }) { return false }
            }
            return true
        }
        func put(_ i: Int, _ x: Double, _ y: Double, _ lv: Int) -> Node {
            rooms[i].tx = x; rooms[i].ty = y; rooms[i].tz = Double(lv) * 64
            let n = Node(rooms[i], x, y, lv); placed.append(n); return n
        }
        var sides = [Side(), Side()] // R, L, alternating; no random selection
        for (index, i) in list.enumerated() {
            let side = index % 2, r = rooms[i]
            var st = sides[side]
            var climbed = false
            // JS while(st.col && st.col.lv < MAX_LV), with at most one put per project.
            if let lo = st.col, lo.lv < 4 {
                let lv = lo.lv + 1, alongX = (lo.lv % 2 == 0) == (side == 1)
                var found: Node?
                var gap = 6.0 + (alongX ? 0 : 2)
                while gap <= 16 && found == nil {
                    let pa: H.Port, pb: H.Port, tx: Double, ty: Double
                    if alongX {
                        pa = H.Port(kind: "L", q: [-1.2, lo.r.NY + 1])
                        let a = [lo.tx + pa.q[0], lo.ty + pa.q[1]]
                        tx = a[0] - gap - (r.NX + 2); ty = a[1] - (r.NY + 1)
                        pb = H.Port(kind: "Rt", q: [r.NX + 2, r.NY + 1])
                    } else {
                        pa = H.Port(kind: "Bk", q: [lo.r.NX + 1, -1.2])
                        let a = [lo.tx + pa.q[0], lo.ty + pa.q[1]]
                        tx = a[0] - (r.NX + 1); ty = a[1] - gap - (r.NY + 2)
                        pb = H.Port(kind: "F", q: [r.NX + 1, r.NY + 2])
                    }
                    let a = [lo.tx + pa.q[0], lo.ty + pa.q[1]], b = [tx + pb.q[0], ty + pb.q[1]]
                    let span = HouseHull.span(a, b, Double(lo.lv) * 64 - 6, 64)
                    if clear(HouseHull.core(r, tx, ty, Double(lv) * 64), HouseHull.body(r, tx, ty, Double(lv) * 64, full: true),
                             span, lo, HouseHull.body(r, tx, ty, Double(lv) * 64)) {
                        let n = put(i, tx, ty, lv); found = n
                        // addStair(lo,hi,pa,pb,A,Bp)
                        spans.append(span)
                        links.append(H.Link(kind: "stair", id: lo.r.key + ":" + pa.kind + ">" + n.r.key,
                                            a: lo.r.key, b: n.r.key, pa: pa, pb: pb, A: a, B: b,
                                            len: hypot(b[0] - a[0], b[1] - a[1]), ang: atan2(b[1] - a[1], b[0] - a[0]),
                                            rise: 64, steps: 13, z0: Double(lo.lv) * 64 - 6, lo: lo.r.key, hi: n.r.key,
                                            targets: [H.Target(room: n.r.key), H.Target(up: true)]))
                    }
                    gap += 2
                }
                if let found { st.col = found; climbed = true } else { st.col = nil }
            }
            if climbed { sides[side] = st; continue }
            // New ground row: BR_GAP = 3; push it out by 2 until clear, or
            // keep the JS fallback at gap 33 even if no candidate was clear.
            let p = st.last ?? yard
            let kind: String, ck: String
            if p === yard { kind = side == 0 ? "Yr" : "Yl"; ck = side == 0 ? "L" : "Rt" }
            else { kind = side == 0 ? "Rt" : "F"; ck = side == 0 ? "L" : "Bk" }
            let pp = port(kind, p.r), cp = port(ck, r)
            let a = [p.tx + pp.q[0], p.ty + pp.q[1]]
            var gap = 3.0, found: Node?
            while gap < 33 {
                let b = [a[0] + pp.d[0] * gap, a[1] + pp.d[1] * gap]
                let tx = b[0] - cp.q[0], ty = b[1] - cp.q[1]
                if clear(HouseHull.core(r, tx, ty, 0), HouseHull.body(r, tx, ty, 0, full: true)) {
                    found = put(i, tx, ty, 0); break
                }
                gap += 2
            }
            let n: Node
            if let found { n = found }
            else { n = put(i, a[0] + pp.d[0] * gap - cp.q[0], a[1] + pp.d[1] * gap - cp.q[1], 0) }
            let b = [n.tx + cp.q[0], n.ty + cp.q[1]], axis = pp.d[0] != 0 ? "x" : "y", k = axis == "x" ? 0 : 1
            links.append(H.Link(kind: "bridge", id: p.r.key + ":" + kind + ">" + r.key, a: p.r.key, b: r.key,
                                pa: H.Port(kind: kind, q: pp.q), pb: H.Port(kind: ck, q: cp.q), A: a, B: b, axis: axis, z: 0, len: abs(b[k] - a[k])))
            spans.append(HouseHull.span(a, b, -6, 0))
            st.last = n; st.col = n; sides[side] = st
        }
        hulls = tFull + placed.map(\.full) + spans
    }
}
