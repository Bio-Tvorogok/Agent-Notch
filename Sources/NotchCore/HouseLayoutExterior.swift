import Foundation

extension HouseLayoutBuilder {
    // YD, YARD, YW, YUP, YGATE, YARD_PORTS, yardOn(), gateUsed(). YARD's
    // origin is one SLAB below the bathroom; worldFrame stays at the bathroom.
    func yardPlan() -> H.Yard {
        var r = H.Room(key: "__yard", name: "Двор", theme: "yard", NX: 16.6 - 0.1, NY: 7.85,
                       tower: -1, floor: -1, tz: nil, wx: nil, wy: nil)
        r.ox = rooms[0].ox; r.oy = rooms[0].oy + 6 * 2
        r.wx = rooms[0].wx; r.wy = (rooms[0].wy ?? 0) + 6 * 2 // world position: the yard's edge is where its jumpers fall from
        let used: (String) -> Bool = { kind in self.links.contains { $0.a == "__yard" && $0.pa.kind == kind } }
        return H.Yard(on: style == .islands, room: r, YD: ["x1": 16.6, "y0": 1],
                      YW: [[8.9,6.3],[8.6,7.0],[2.6,7.0],[1.8,7.05],[1.0,7.65],[8.9,3.7],[16.0,3.6],[8.9,1.5],[9.9,0.85],
                           [10.4,6.35],[10.3,5.1],[11.9,6.3],[12.3,7.0],[9.05,2.45],[11.7,3.62],[1.75,7.6],[13.4,3.6],[14.7,5.0],[15.5,7.2],[14.8,2.2]],
                      YUP: [-1,0,1,2,15,0,16,5,7,0,9,9,11,5,5,3,5,16,17,16], YGATE: ["foot":3,"Yl":4,"Yr":6,"tower":8],
                      ports: ["Yr": H.YardPort(q: [16.6,3.6], d: [1,0], opp: "L"), "Yl": H.YardPort(q: [-1.2,7.5], d: [-1,0], opp: "Rt")],
                      ground: [-1.2,-1.2,-6.0-14,16.6,rooms[0].NY+2,-6], gates: ["Yl":used("Yl"),"Yr":used("Yr")])
    }

    // buildCache(r)'s escBack / escFront / escTop selection. Repeated local
    // shapes share an entry, so fixtures stay below 2 MB without rounding.
    func escapePlan() -> ([H.Escape], [String: [H.Primitive]]) {
        var out: [H.Escape] = [], shapes: [String: [H.Primitive]] = [:]
        for r in rooms {
            let above = rooms.contains { $0.tower == r.tower && $0.floor == r.floor + 1 }
            var layers: [String] = []
            if above && lift == nil { layers += ["back", "front"] }
            if lift != nil ? r.key == "__bath" : !above && r.floor > 0 { layers.append("top") }
            for layer in layers {
                let shape = "\(Int(r.NY)):\(layer)"
                out.append(H.Escape(room: r.key, layer: layer, shape: shape))
                if shapes[shape] == nil { shapes[shape] = escape(r, layer) }
            }
        }
        return (out, shapes)
    }

    // escape(r,layer): ESC={x0:.1,x1:3.3,w:1.1}, F2=FLOOR_STEP/2.
    // Geometry-only B/line/poly operations preserve the JS drawing order.
    private func escape(_ r: H.Room, _ layer: String) -> [H.Primitive] {
        let y = r.NY, steps = 11, run = (3.3 - 1.3) / 11, rise = 47.0 / 11, w = 1.1
        var out: [H.Primitive] = []
        func iso(_ x: Double, _ y: Double, _ z: Double) -> [Double] { [(x-y)*8*2,(x+y)*4*2-z*2] }
        func box(_ x: Double, _ y: Double, _ z: Double, _ w: Double, _ d: Double, _ h: Double) {
            out.append(H.Primitive(kind: "box", points: [[x,y,z,w,d,h]]))
        }
        func line(_ a: [Double], _ b: [Double]) { out.append(H.Primitive(kind: "line", points: [a,b])) }
        func polygon(_ p: [[Double]]) { out.append(H.Primitive(kind: "polygon", points: p)) }
        func landing(_ x: Double, _ z: Double) {
            box(x,y+0.1,z-2.4,w,1.2,2.4)
            var k = 0.3
            while k < w { line(iso(x+k,y+0.1,z),iso(x+k,y+1.3,z)); k += 0.3 }
        }
        func post(_ x: Double, _ y: Double, _ z0: Double, _ z1: Double) { box(x-0.06,y-0.06,z0,0.12,0.12,z1-z0) }
        func rail(_ a: [Double], _ b: [Double]) { line(a,b); line([a[0],a[1]+1],[b[0],b[1]+1]) }
        if layer == "back" {
            landing(0.1,0)
            for i in 0..<steps { box(1.3+Double(i)*run,y+0.1,Double(i+1)*rise-1.6,run+0.02,0.6,1.6) }
            polygon([iso(1.3,y+0.1,-2),iso(3.3,y+0.1,47-2),iso(3.3,y+0.1,47-5),iso(1.3,y+0.1,-5)])
            landing(3.3,47)
            for x in [0.1+0.05,3.3+w-0.05] { post(x,y+0.15,x<1 ? -2 : 47-8,x<1 ? 94 : 47+12) }
        } else if layer == "front" {
            for i in 0..<steps { box(3.3-Double(i+1)*run,y+0.7,47+Double(i+1)*rise-1.6,run+0.02,0.6,1.6) }
            polygon([iso(3.3,y+1.3,47-2),iso(1.3,y+1.3,94-2),iso(1.3,y+1.3,94-5),iso(3.3,y+1.3,47-5)])
            for x in [0.1+0.05,3.3+w-0.05] { post(x,y+1.25,x<1 ? -2 : 47-2,x<1 ? 12 : 47+12) }
            rail(iso(0.1+0.05,y+1.25,12),iso(1.3,y+1.25,12))
            rail(iso(3.3,y+1.25,47+12),iso(3.3+w-0.05,y+1.25,47+12))
            rail(iso(3.3+w-0.05,y+1.25,47+12),iso(3.3+w-0.05,y+0.15,47+12))
            rail(iso(3.3,y+1.25,47+12),iso(1.3,y+1.25,94+12))
            for i in stride(from: 1, to: steps, by: 3) { post(3.3-Double(i)*run,y+1.25,47+Double(i)*rise-1,47+Double(i)*rise+12) }
        } else {
            landing(0.1,0)
            post(0.1+0.05,y+1.25,-2,12); post(1.25,y+1.25,-2,12)
            rail(iso(0.1+0.05,y+1.25,12),iso(1.25,y+1.25,12))
        }
        return out
    }
}
