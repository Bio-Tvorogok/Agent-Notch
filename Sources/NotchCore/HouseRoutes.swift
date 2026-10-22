import Foundation

extension HouseSim {
    private struct RouteStep {
        let next: String, kind: String
        var link: String? = nil
        var trip: HouseLiftTrip? = nil
    }
    // roomPath: stable breadth-first search. Lifts, stack stairs, links and yard
    // edges are visited in exactly the page's order, including disconnected stacks.
    private func roomPath(_ a: String, _ b: String) -> [RouteStep]? {
        let rooms = layout.rooms + [layout.yard.room]
        func index(_ key: String) -> Int { rooms.firstIndex { HouseRoutes.same($0.key, key) }! }
        let start = index(a), end = index(b)
        var visited: Set<Int> = [start], queue = [start], head = 0
        var previous: [Int: (Int, RouteStep)] = [:]
        while head < queue.count {
            let current = queue[head]; head += 1
            if current == end { break }
            let r = rooms[current], yard = r.key == "__yard"
            var next: [RouteStep] = []
            if let lift = layout.lift, yard || r.tower == 0 {
                let f = yard ? 0 : r.floor
                if yard || f > 0 {
                    for (k, floor) in lift.fl.enumerated() where k != f {
                        next.append(RouteStep(next: k == 0 ? "__yard" : floor.room, kind: "lift", trip: .init(from: f, to: k)))
                    }
                }
            } else {
                for d in [-1, 1] {
                    if let n = roomAt(r.tower, r.floor + d) { next.append(RouteStep(next: n.key, kind: "stairs")) }
                }
            }
            for l in links {
                let g = l.geometry
                if HouseRoutes.same(g.a, r.key) || HouseRoutes.same(g.b, r.key) {
                    next.append(RouteStep(next: HouseRoutes.same(g.a, r.key) ? g.b : g.a, kind: "link", link: g.id))
                }
            }
            if yard { next.append(RouteStep(next: "__bath", kind: "yard")) }
            else if r.key == "__bath" && layout.yard.on { next.append(RouteStep(next: "__yard", kind: "yard")) }
            for step in next {
                let n = index(step.next)
                if visited.insert(n).inserted { previous[n] = (current, step); queue.append(n) }
            }
        }
        guard visited.contains(end) else { return nil }
        var result: [RouteStep] = [], current = end
        while let (prev, step) = previous[current] { result.insert(step, at: 0); current = prev }
        return result
    }

    /// routeTo: replaces only the path; setGoal also records category/spot data.
    public func route(_ sprite: HouseSprite, to key: String, point p: [Double]) {
        var nodes: [HouseRouteNode] = [], cur = sprite.room, from = [sprite.x, sprite.y, sprite.z]
        if sprite.onBridge != nil {
            let rest = sprite.path.filter { ($0.wait ?? 0) == 0 }
            if let k = rest.firstIndex(where: { $0.r != nil }) {
                nodes.append(contentsOf: rest[...k]); cur = rest[k].r; from = rest[k].p!
            } else {
                sprite.onBridge = nil; cur = sprite.homeRoom; from = hub(cur!)
                nodes.append(.init(r: cur, p: from, jump: true, poof: true))
            }
        } else if let n = sprite.path.first, let q = n.p, q[2] != 0,
                  HouseRoutes.same(n.r, cur), n.jump != true {
            nodes.append(n); from = q
        } else if sprite.z > 0.5 {
            let r = room(cur!)
            nodes.append(.init(r: cur, p: [min(sprite.x + 0.2, r.NX - 0.4), min(sprite.y + 0.7, r.NY - 0.4), 0]))
        }
        let steps = HouseRoutes.same(cur, key) ? [] : roomPath(cur!, key)
        if let steps {
            for step in steps {
                let current = room(cur!), next = room(step.next)
                switch step.kind {
                case "stairs":
                    let up = next.floor > current.floor, ny = current.NY, nyn = next.NY
                    if far(from, hub(current.key)) && far(from, [1, ny - 0.5]) { nodes.append(.init(r: cur, p: hub(current.key))) }
                    func flight(_ y: Double) -> [[Double]] {
                        [[1, y-0.5, 0], [0.7, y+0.7, 0], [1.4, y+0.4, 0], [3.3, y+0.4, 47],
                         [3.3+0.6, y+0.7, 47], [3.3, y+1, 47], [1.4, y+1, 94]]
                    }
                    if up {
                        nodes += flight(ny).map { .init(r: cur, p: $0) }
                        nodes += [.init(r: next.key, p: [1.4, nyn+1, 0], jump: true),
                                  .init(r: next.key, p: [0.7, nyn+0.7, 0]), .init(r: next.key, p: [1, nyn-0.5, 0])]
                    } else {
                        nodes += [.init(r: cur, p: [1, ny-0.5, 0]), .init(r: cur, p: [0.7, ny+0.7, 0]),
                                  .init(r: cur, p: [1.4, ny+1, 0]), .init(r: next.key, p: [1.4, nyn+1, 94], jump: true)]
                        nodes += flight(nyn).reversed().dropFirst().map { .init(r: next.key, p: $0) }
                    }
                case "yard": yardLink(&nodes, current, next, from)
                case "lift": liftLink(&nodes, current, next, step.trip!, from, sprite)
                default: crossLink(&nodes, current, next, link(step.link!).geometry, from)
                }
                from = nodes.last!.p!; cur = next.key
            }
        } else {
            from = hub(key); cur = key
            nodes.append(.init(r: key, p: from, jump: true, poof: true))
        }
        let target = room(key)
        if key == "__yard" { yardWalk(&nodes, from, p) }
        else {
            if isIsland(target) && !inBox(target, from) { from = walkIn(&nodes, target, from) }
            if far(from, p) { nodes.append(.init(r: key, p: hub(key))) }
        }
        nodes.append(.init(r: key, p: p)); sprite.path = nodes
    }

    private func far(_ a: [Double], _ b: [Double]) -> Bool { hypot(a[0]-b[0], a[1]-b[1]) > 2.2 }
    private func inBox(_ r: HouseLayout.Room, _ p: [Double]) -> Bool { p[0] > -0.05 && p[0] < r.NX+0.05 && p[1] > -0.05 && p[1] < r.NY+0.05 }
    private func front(_ r: HouseLayout.Room, _ p: [Double]) -> Bool { p[1] > r.NY + 0.05 }
    private func entry(_ r: HouseLayout.Room, front: Bool) -> (i: [Double], s: [Double]) {
        let fx = r.theme == "library" ? 6.4 : r.NX * 0.6
        let ry: Double
        switch r.theme { case "server": ry = 4.25; case "library": ry = 5; case "kitchen": ry = 4.5; default: ry = r.NY * 0.45 }
        return front ? ([fx, r.NY-0.45, 0], [fx, r.NY+0.3, -3]) : ([r.NX-0.45, ry, 0], [r.NX+0.3, ry, -3])
    }
    private func grassWalk(_ nodes: inout [HouseRouteNode], _ r: HouseLayout.Room, _ a: [Double], _ b: [Double]) {
        let la = front(r,a), lb = front(r,b)
        func onto(_ p: [Double], _ f: Bool) -> [Double] { f ? [p[0], r.NY+1, -6] : [r.NX+1, p[1], -6] }
        nodes.append(.init(r: r.key, p: onto(a,la)))
        if la != lb { nodes.append(.init(r: r.key, p: [r.NX+1.5, r.NY+1.5, -6])) }
        nodes.append(.init(r: r.key, p: onto(b,lb)))
    }
    private func walkOut(_ nodes: inout [HouseRouteNode], _ r: HouseLayout.Room, _ q: [Double], _ from: [Double]) {
        var at = from
        if inBox(r,from) {
            let e = entry(r, front: front(r,q))
            if far(from,hub(r.key)) && far(from,e.i) { nodes.append(.init(r: r.key, p: hub(r.key))) }
            nodes += [.init(r: r.key, p: e.i), .init(r: r.key, p: e.s)]; at = e.s
        }
        grassWalk(&nodes,r,at,q); nodes.append(.init(r: r.key, p: [q[0],q[1],-6]))
    }
    @discardableResult
    private func walkIn(_ nodes: inout [HouseRouteNode], _ r: HouseLayout.Room, _ from: [Double]) -> [Double] {
        let e = entry(r,front: front(r,from)); grassWalk(&nodes,r,from,e.s)
        nodes += [.init(r: r.key, p: e.s), .init(r: r.key, p: e.i)]; return e.i
    }
    private func yardNear(_ p: [Double]) -> Int {
        let yw = layout.yard.YW
        if let i = yw.firstIndex(where: { hypot($0[0]-p[0], $0[1]-p[1]) < 0.35 }) { return i }
        let x=p[0], y=p[1]
        if x < 3.2 { return y > 7.25 ? 4 : 3 }
        if x > 9.5 && y < 1.3 { return 8 }
        if x > 13.9 { return y > 6.4 ? 18 : y > 4.2 ? 17 : y < 3 ? 19 : x > 15.6 ? 6 : 16 }
        if x > 12.5 && y > 6.6 { return 12 }
        if x > 11.6 && y > 5.8 { return 11 }
        if x > 9.8 && x < 11.6 && y > 6.6 { return 9 }
        if x > 9.5 && x < 11.2 && y > 4.3 && y < 5.8 { return 10 }
        if x > 9.3 && x < 11.5 && y > 2.1 && y < 2.8 { return 13 }
        if x > 11.4 && y > 1.5 && y < 3.5 { return 14 }
        return y < 4.6 && x > 8.2 ? 5 : 0
    }
    private func yardWalk(_ nodes: inout [HouseRouteNode], _ from: [Double], _ to: [Double]) {
        func chain(_ start: Int) -> [Int] {
            var result: [Int] = [], i = start
            while i >= 0 { result.append(i); i = layout.yard.YUP[i] }; return result
        }
        let a = chain(yardNear(from)), b = chain(yardNear(to)), top = a.first { b.contains($0) }!
        let path = Array(a.prefix(through: a.firstIndex(of: top)!)) + b.prefix(upTo: b.firstIndex(of: top)!).reversed()
        for i in path { nodes.append(.init(r: "__yard", p: layout.yard.YW[i] + [0])) }
    }
    private func yardLink(_ nodes: inout [HouseRouteNode], _ cur: HouseLayout.Room, _ next: HouseLayout.Room, _ from: [Double]) {
        let b = cur.key == "__yard" ? next : cur, ny = b.NY
        let way: [[Double]] = [[1,ny-0.5,0], [0.7,ny+0.7,0], [1.375,ny+1,-3]]
        let foot = layout.yard.YW[layout.yard.YGATE["foot"]!]
        if cur.key != "__yard" {
            if far(from,hub(b.key)) && far(from,way[0]) { nodes.append(.init(r: b.key, p: hub(b.key))) }
            nodes += way.map { .init(r: b.key, p: $0) }
            nodes += [.init(r: "__yard", p: [1.375,ny+1,3], jump: true), .init(r: "__yard", p: foot + [0])]
        } else {
            yardWalk(&nodes,from,foot)
            nodes += [.init(r: "__yard", p: [1.375,ny+1,3]), .init(r: b.key, p: way[2], jump: true),
                      .init(r: b.key, p: way[1]), .init(r: b.key, p: way[0])]
        }
    }
    private func crossLink(_ nodes: inout [HouseRouteNode], _ cur: HouseLayout.Room, _ next: HouseLayout.Room, _ l: HouseLayout.Link, _ from: [Double]) {
        let fw = HouseRoutes.same(l.a,cur.key), pc = fw ? l.pa : l.pb, pn = fw ? l.pb : l.pa
        if cur.key == "__yard" {
            yardWalk(&nodes,from,layout.yard.YW[layout.yard.YGATE[pc.kind]!])
            nodes.append(.init(r: "__yard", p: [pc.q[0],pc.q[1],0]))
        } else { walkOut(&nodes,cur,pc.q,from) }
        if l.kind == "stair" { nodes.append(.init(call: l.id, aim: 0, side: fw ? "lo" : "hi")) }
        nodes += [.init(bridge: l.id, to: fw ? 1 : 0), .init(r: next.key, p: [pn.q[0],pn.q[1],next.key == "__yard" ? 0 : -6], jump: true)]
    }
    private func liftWay(_ r: HouseLayout.Room, _ sprite: HouseSprite) -> [[Double]] {
        let l = layout.lift!, wx = l.x0 + 0.35 + sprite.seed * (l.x1-l.x0-0.7), wy = l.y1 + 0.4
        if r.key == "__yard" { return [[wx,wy,0]] }
        let e = entry(r,front: false), yo = l.fl[r.floor].yoff
        return [e.i, [r.NX+0.3,e.i[1],0], [r.NX+0.3,wy-yo,0], [wx,wy-yo,0]]
    }
    private func liftLink(_ nodes: inout [HouseRouteNode], _ cur: HouseLayout.Room, _ next: HouseLayout.Room, _ trip: HouseLiftTrip, _ from: [Double], _ sprite: HouseSprite) {
        let out = liftWay(cur,sprite), inn = liftWay(next,sprite), tower = layout.yard.YW[layout.yard.YGATE["tower"]!]
        if cur.key == "__yard" { yardWalk(&nodes,from,tower) }
        else if far(from,hub(cur.key)) && far(from,out[0]) { nodes.append(.init(r: cur.key, p: hub(cur.key))) }
        nodes += out.map { .init(r: cur.key, p: $0) }
        nodes += [.init(lift: trip), .init(r: next.key, p: inn.last!, jump: true)]
        if next.key == "__yard" { nodes.append(.init(r: "__yard", p: tower + [0])) }
        else { nodes += inn.dropLast().reversed().map { .init(r: next.key, p: $0) } }
    }
}
