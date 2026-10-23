import AppKit
import NotchCore
import SpriteKit

// Hosts HouseScene2 (the SpriteKit house composed from room/atlas/parts.json) to prove it and to measure it.
//   harness proof <atlas dir> <ref dir> <out dir>      render every page frame in <ref dir> (scripts/house-atlas/harness/ref.js)
//                                                       with the scene on the same canvas and compare: % of house pixels off by > 24
//   harness snapdemo <atlas dir> <projects> <hour> <seconds> <out.png>   the house with HouseSim agents after <seconds>
//   harness idle|demo <atlas dir> <projects> <seconds>  a windowed run at desktop level, printing delivered fps
let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : ""
let NAMES = ["Agent-Notch", "hexhaven", "world", "t2", "decide", "trailby", "arena", "confetti", "hall", "lessons", "life-os", "screens", "tank-hero", "av-wt"]
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

func spin(_ s: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow: s)) }

func pixels(_ img: CGImage) -> (data: [UInt8], w: Int, h: Int) {
    let w = img.width, h = img.height
    var d = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &d, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (d, w, h)
}

func crop(_ p: (data: [UInt8], w: Int, h: Int), _ w: Int, _ h: Int) -> (data: [UInt8], w: Int, h: Int) {
    var d = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<min(h, p.h) { for x in 0..<min(w, p.w) { for c in 0..<4 { d[(y * w + x) * 4 + c] = p.data[(y * p.w + x) * 4 + c] } } }
    return (d, w, h)
}

func load(_ url: URL) -> CGImage {
    guard let s = CGImageSourceCreateWithURL(url as CFURL, nil), let i = CGImageSourceCreateImageAtIndex(s, 0, nil) else { fatalError("cannot read \(url.path)") }
    return i
}

func save(_ d: [UInt8], _ w: Int, _ h: Int, to url: URL) {
    var d = d
    let ctx = CGContext(data: &d, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

func makeLayout(projects: Int, innerW: Double, innerH: Double, insets: HouseLayout.Insets) -> HouseLayout {
    HouseLayout.make(projects: Array(NAMES.prefix(projects)), canvas: .init(width: innerW, height: innerH, dpr: 2), insets: insets)
}

/// Renders a scene headless: the canvas at 1 device pixel per art pixel (the view is the canvas at backing scale 2, the world at .5).
func render(_ scene: HouseScene2, view: SKView) -> CGImage {
    view.presentScene(scene)
    spin(1.0)
    var img = view.texture(from: scene)!.cgImage()
    spin(0.3)
    img = view.texture(from: scene)!.cgImage()
    return img
}

/// Pixels per point of view.texture(from:) in this process (it is not always the display's backing scale).
let texScale: Double = {
    let v = SKView(frame: NSRect(x: 0, y: 0, width: 100, height: 100)), s = SKScene(size: CGSize(width: 100, height: 100))
    v.presentScene(s); spin(0.2)
    return Double(v.texture(from: s)!.cgImage().width) / 100
}()

func makeScene(atlas: URL, layout: HouseLayout) -> (HouseScene2, SKView) {
    let W = layout.view.width, H = layout.view.height
    let even = { (v: Double) in (v / texScale / 2).rounded(.up) * 2 } // whole points whose pixels are whole too
    let size = CGSize(width: even(W), height: even(H)) // points: the snapshot is W x H pixels, one art pixel each
    guard let scene = HouseScene2.load(from: atlas, layout: layout, unit: CGFloat(1 / texScale), size: size) else { print("no parts.json / parts pages in \(atlas.path)"); exit(1) }
    scene.followsLayoutScale = false
    let view = SKView(frame: NSRect(origin: .zero, size: size))
    view.ignoresSiblingOrder = true
    return (scene, view)
}

let GATE_AGENT24 = 12.0, GATE_AGENT6 = 12.0 // the agents' own pixels: bodies, marks, props, pets
let GATE_PCT6 = 0.3, GATE_MAE = 1.0, GATE_FRAME24 = 0.15, GATE_FRAME6 = 0.2 // clean run: <= 0.13, 0.57, 0.063, 0.067; the probes AMB=0.93 and CITYSHIFT=6 are far above
switch mode {
case "proof":
    let atlas = URL(fileURLWithPath: args[2], isDirectory: true), refDir = URL(fileURLWithPath: args[3], isDirectory: true), out = URL(fileURLWithPath: args[4], isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let metas = try FileManager.default.contentsOfDirectory(atPath: refDir.path).filter { $0.hasPrefix("ref-") && $0.hasSuffix(".json") }.sorted()
    var failed = false
    print("fixture             var  house px  off>24  %house24  %house6  MAE/ch | frame%24  frame%6")
    for m in metas {
        let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: refDir.appendingPathComponent(m))) as! [String: Any]
        let growthTag = (meta["rooms"] as! [[String: Any]]).map { $0["growth"] as? Int ?? 0 }.max() ?? 0
        let n = meta["n"] as! Int, hour = meta["hour"] as! Double, W = meta["W"] as! Int, H = meta["H"] as! Int
        let pxd = meta["PXD"] as! Double, dpr = meta["DPR"] as! Double, ins = meta["insets"] as! [String: Double]
        let layout = makeLayout(projects: n, innerW: (Double(W) * pxd / dpr).rounded(), innerH: floor(Double(H) * pxd / dpr),
                                insets: .init(top: ins["top"]!, bottom: ins["bottom"]!, right: ins["right"]!))
        // the same layout as the page's
        guard Int(layout.view.width) == W, Int(layout.view.height) == H else { print("canvas mismatch \(layout.view.width)x\(layout.view.height) vs \(W)x\(H)"); exit(1) }
        for r in meta["rooms"] as! [[String: Any]] {
            let key = r["key"] as! String
            guard let mine = layout.rooms.first(where: { $0.key == key }) else { print("room \(key) missing in the Swift layout"); exit(1) }
            if mine.ox != r["ox"] as! Double || mine.oy != r["oy"] as! Double { print("room \(key) origin \(mine.ox),\(mine.oy) vs page \(r["ox"]!),\(r["oy"]!)"); exit(1) }
        }
        let (scene, view) = makeScene(atlas: atlas, layout: layout)
        for r in meta["rooms"] as! [[String: Any]] { if let g = r["growth"] as? Int, g > 0 { scene.growth[r["key"] as! String] = g } }
        scene.env = HouseSkyEnv(innerHeight: floor(Double(H) * pxd / dpr), insetBottom: ins["bottom"]!)
        scene.freezeClock = true; scene.clockMillis = meta["T"] as! Double; scene.colon = false
        scene.setTime(hour: hour, day: meta["day"] as! Int)
        // deliberate defects, to prove the gate fails: PROOF_BREAK (house 2px right), PROOF_AMB=k (light scaled by k), PROOF_CITYSHIFT=n (city n art px right)
        let probe = ProcessInfo.processInfo.environment
        if probe["PROOF_BREAK"] != nil { scene.root.position.x += 2 }
        if let k = probe["PROOF_AMB"].flatMap({ Double($0) }) { scene.shaders.set(scene.light.amb * k) }
        if let sh = probe["PROOF_CITYSHIFT"].flatMap({ Double($0) }) { for c in scene.skyGroup.children where c.zPosition > -49_600 && c.zPosition < -49_400 { c.position.x += sh } }
        let ours = render(scene, view: view)
        let tag = m.dropFirst(4).dropLast(5)
        let ref = pixels(load(refDir.appendingPathComponent("ref-\(tag).png"))), sky = pixels(load(refDir.appendingPathComponent("ref-\(tag)-sky.png"))), mineRaw = pixels(ours)
        guard mineRaw.w >= ref.w, mineRaw.h >= ref.h, mineRaw.w - ref.w <= 8, mineRaw.h - ref.h <= 8 else { print("size mismatch \(mineRaw.w)x\(mineRaw.h) vs \(ref.w)x\(ref.h)"); exit(1) }
        let mine = crop(mineRaw, ref.w, ref.h)
        var house = 0, off = 0, offAll = 0, off6 = 0, sumAbs = 0, offFrame6 = 0
        var hot: [Int: Int] = [:]
        var diff = [UInt8](repeating: 255, count: ref.w * ref.h * 4)
        var side = [UInt8](repeating: 255, count: ref.w * 2 * ref.h * 4)
        for p in 0..<(ref.w * ref.h) {
            let i = p * 4
            var mx = 0
            for c in 0..<3 { mx = max(mx, abs(Int(ref.data[i + c]) - Int(mine.data[i + c]))) }
            let isHouse = abs(Int(ref.data[i]) - Int(sky.data[i])) + abs(Int(ref.data[i + 1]) - Int(sky.data[i + 1])) + abs(Int(ref.data[i + 2]) - Int(sky.data[i + 2])) > 0
            if isHouse { house += 1 }
            if mx > 6 { offFrame6 += 1 }
            if isHouse { sumAbs += (0..<3).reduce(0) { $0 + abs(Int(ref.data[i + $1]) - Int(mine.data[i + $1])) }; if mx > 6 { off6 += 1 } }
            if mx > 24 { offAll += 1; if isHouse { off += 1; hot[(p / ref.w / 48) * 1000 + (p % ref.w) / 48, default: 0] += 1 } }
            for c in 0..<3 { diff[i + c] = mx > 24 ? (c == 0 ? 255 : 0) : ref.data[i + c] >> 2 }
            let y = p / ref.w, x = p % ref.w
            for c in 0..<4 { side[(y * ref.w * 2 + x) * 4 + c] = ref.data[i + c]; side[(y * ref.w * 2 + ref.w + x) * 4 + c] = mine.data[i + c] }
        }
        save(diff, ref.w, ref.h, to: out.appendingPathComponent("\(tag)-diff.png"))
        save(side, ref.w * 2, ref.h, to: out.appendingPathComponent("\(tag)-side.png"))
        save(mine.data, mine.w, mine.h, to: out.appendingPathComponent("\(tag)-scene.png"))
        let pct = 100 * Double(off) / Double(max(1, house))
        let pct6 = 100 * Double(off6) / Double(max(1, house)), mae = Double(sumAbs) / Double(max(1, house) * 3)
        let frame24 = 100 * Double(offAll) / Double(ref.w * ref.h), frame6 = 100 * Double(offFrame6) / Double(ref.w * ref.h)
        print(String(format: "%-18@ %3d %9d %7d %8.4f %8.4f %7.4f | %8.4f %8.4f", "n=\(n) h=\(String(format: "%.2f", hour)) g=\(growthTag)" as NSString, scene.light.variant, house, off, pct, pct6, mae, frame24, frame6))
        if ProcessInfo.processInfo.environment["HOT"] != nil { for (k, v) in hot.sorted(by: { $0.value > $1.value }).prefix(8) { print("    cell x\((k % 1000) * 48) y\((k / 1000) * 48): \(v)") } }
        // gates: big errors (>24) on the house, small errors (>6, mean abs) on the house, and the whole frame (sky, city)
        let limits = (pct: 0.1, pct6: GATE_PCT6, mae: GATE_MAE, frame24: GATE_FRAME24, frame6: GATE_FRAME6)
        if pct > limits.pct || pct6 > limits.pct6 || mae > limits.mae || frame24 > limits.frame24 || frame6 > limits.frame6 { failed = true; print("    ^ over a gate") }
    }
    print(failed ? "PROOF: FAILED (a fixture is over a gate)" : "PROOF: all fixtures within the gates")
    exit(failed ? 3 : 0)

case "live":
    // live <atlas> <ref dir> <fixture dir> <out dir>: replays each behaviour fixture of the page frames in <ref dir> (live-ref.js) through
    // HouseBehaviour + HouseScene2 and compares at every sample, with the proof's gates and gates on the agents' own pixels
    let atlas = URL(fileURLWithPath: args[2], isDirectory: true), refDir = URL(fileURLWithPath: args[3], isDirectory: true)
    let fixDir = URL(fileURLWithPath: args[4], isDirectory: true), out = URL(fileURLWithPath: args[5], isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let metas = try FileManager.default.contentsOfDirectory(atPath: refDir.path).filter { $0.hasPrefix("live-") && $0.hasSuffix(".json") }
    var byCase: [String: [(t: Int, file: String, meta: [String: Any])]] = [:]
    for m in metas {
        let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: refDir.appendingPathComponent(m))) as! [String: Any]
        byCase[meta["case"] as! String, default: []].append((meta["t"] as! Int, String(m.dropFirst(5).dropLast(5)), meta))
    }
    var failed = false
    print("sample                 var  house px  %house24  %house6  MAE/ch | frame%24 frame%6 | agent px  %agent24  %agent6 | sprites")
    for name in byCase.keys.sorted() {
        let samples = byCase[name]!.sorted { $0.t < $1.t }
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: fixDir.appendingPathComponent(name + ".json"))) as! [String: Any]
        let input = fixture["input"] as! [String: Any]
        let events = (input["events"] as! [[String: Any]]).filter { $0["rows"] != nil }
        func rows(_ e: [String: Any]) -> [HouseAgentRow] { try! JSONDecoder().decode([HouseAgentRow].self, from: JSONSerialization.data(withJSONObject: e["rows"]!)) }
        let first = samples[0].meta, ins = first["insets"] as! [String: Double], dpr = first["DPR"] as! Double
        // the page runs its life layer too (live-ref.js), so the behaviour does: same randoms, the case's hour and the page's DARK
        let rng = HouseRandom(seed: UInt32(input["seed"] as! Int))
        let behaviour = HouseBehaviour(layout: .islands, canvas: .init(width: 1728, height: 1117, dpr: dpr),
                                       insets: .init(top: ins["top"]!, bottom: ins["bottom"]!, right: ins["right"]!), random: { rng.nextDouble() })
        behaviour.enableLife(hour: first["hour"] as! Double, dark: first["dark"] as! Double)
        var scene: HouseScene2?, view: SKView?
        var bt = 0
        for s in samples {
            // the same timeline as the page: rows at their time, 50 ms steps in between
            while bt <= s.t {
                let ev = events.filter { ($0["at"] as! Int) == bt }.last.map(rows)
                if bt == 0 { if let ev { behaviour.setAgents(ev) } } else { behaviour.advance(frame: 50, agents: ev) }
                bt += 50
            }
            let meta = s.meta, W = meta["W"] as! Int, H = meta["H"] as! Int, hour = meta["hour"] as! Double
            let pxd = meta["PXD"] as! Double
            let lay = behaviour.layout
            guard Int(lay.view.width) == W, Int(lay.view.height) == H else { print("\(s.file): canvas \(lay.view.width)x\(lay.view.height) vs the page's \(W)x\(H)"); exit(1) }
            for r in meta["rooms"] as! [[String: Any]] {
                guard let mine = lay.rooms.first(where: { $0.key == r["key"] as! String }) else { print("\(s.file): room \(r["key"]!) missing"); exit(1) }
                if mine.ox != r["ox"] as! Double || mine.oy != r["oy"] as! Double { print("\(s.file): room \(mine.key) origin differs"); exit(1) }
            }
            let even = { (v: Double) in (v / texScale / 2).rounded(.up) * 2 }
            let size = CGSize(width: even(Double(W)), height: even(Double(H)))
            if scene == nil {
                guard let sc = HouseScene2.load(from: atlas, layout: lay, unit: CGFloat(1 / texScale), size: size) else { print("no atlas"); exit(1) }
                sc.followsLayoutScale = false; sc.freezeClock = true; sc.freezeSim = true; sc.colon = false
                sc.env = HouseSkyEnv(innerHeight: floor(Double(H) * pxd / dpr), insetBottom: ins["bottom"]!)
                sc.attach(behaviour)
                let v = SKView(frame: NSRect(origin: .zero, size: size)); v.ignoresSiblingOrder = true
                scene = sc; view = v
                sc.setTime(hour: hour, day: meta["day"] as! Int)
                v.presentScene(sc)
            }
            let sc = scene!, v = view!
            sc.followBehaviour(behaviour) // a project that joined relays the house out (the app does it in update)
            if sc.size != size { sc.size = size; v.frame = NSRect(origin: .zero, size: size) }
            sc.clockMillis = Double(s.t); sc.roomClockOverride = 100_000
            sc.setTime(hour: hour, day: meta["day"] as! Int)
            sc.repaint(sync: true)
            if let sim = sc.sim { sc.sync(sim: sim) }
            spin(0.8)
            if let sim = sc.sim { sc.sync(sim: sim) }
            var img = v.texture(from: sc)!.cgImage()
            spin(0.3)
            img = v.texture(from: sc)!.cgImage()
            let ref = pixels(load(refDir.appendingPathComponent("live-\(s.file).png"))), sky = pixels(load(refDir.appendingPathComponent("live-\(s.file)-sky.png")))
            let bare = pixels(load(refDir.appendingPathComponent("live-\(s.file)-bare.png"))), mineRaw = pixels(img)
            guard mineRaw.w >= ref.w, mineRaw.h >= ref.h, mineRaw.w - ref.w <= 8, mineRaw.h - ref.h <= 8 else { print("size mismatch \(mineRaw.w)x\(mineRaw.h) vs \(ref.w)x\(ref.h)"); exit(1) }
            let mine = crop(mineRaw, ref.w, ref.h)
            var house = 0, off24 = 0, off6 = 0, sumAbs = 0, frame24 = 0, frame6 = 0, agent = 0, aOff24 = 0, aOff6 = 0
            var diff = [UInt8](repeating: 255, count: ref.w * ref.h * 4)
            var side = [UInt8](repeating: 255, count: ref.w * 2 * ref.h * 4)
            for p in 0..<(ref.w * ref.h) {
                let i = p * 4
                var mx = 0, dBare = 0, dSky = 0
                for c in 0..<3 {
                    mx = max(mx, abs(Int(ref.data[i + c]) - Int(mine.data[i + c])))
                    dBare += abs(Int(ref.data[i + c]) - Int(bare.data[i + c])); dSky += abs(Int(ref.data[i + c]) - Int(sky.data[i + c]))
                }
                let isHouse = dSky > 0, isAgent = dBare > 0
                if mx > 24 { frame24 += 1 }
                if mx > 6 { frame6 += 1 }
                if isHouse { house += 1; sumAbs += (0..<3).reduce(0) { $0 + abs(Int(ref.data[i + $1]) - Int(mine.data[i + $1])) }; if mx > 24 { off24 += 1 }; if mx > 6 { off6 += 1 } }
                if isAgent { agent += 1; if mx > 24 { aOff24 += 1 }; if mx > 6 { aOff6 += 1 } }
                for c in 0..<3 { diff[i + c] = mx > 24 ? (c == 0 ? 255 : 0) : ref.data[i + c] >> 2 }
                let y = p / ref.w, x = p % ref.w
                for c in 0..<4 { side[(y * ref.w * 2 + x) * 4 + c] = ref.data[i + c]; side[(y * ref.w * 2 + ref.w + x) * 4 + c] = mine.data[i + c] }
            }
            save(diff, ref.w, ref.h, to: out.appendingPathComponent("\(s.file)-diff.png"))
            save(side, ref.w * 2, ref.h, to: out.appendingPathComponent("\(s.file)-side.png"))
            save(mine.data, mine.w, mine.h, to: out.appendingPathComponent("\(s.file)-scene.png"))
            let h = Double(max(1, house)), a = Double(max(1, agent)), f = Double(ref.w * ref.h)
            let p24 = 100 * Double(off24) / h, p6 = 100 * Double(off6) / h, mae = Double(sumAbs) / (h * 3)
            let f24 = 100 * Double(frame24) / f, f6 = 100 * Double(frame6) / f, a24 = 100 * Double(aOff24) / a, a6 = 100 * Double(aOff6) / a
            let tag = "\(name)@\(s.t)"
            print(String(format: "%-22@ %3d %9d %8.4f %8.4f %7.4f | %7.4f %7.4f | %8d %8.3f %8.3f | %d agents, %d falling", tag as NSString, sc.light.variant, house, p24, p6, mae, f24, f6, agent, a24, a6,
                         meta["agents"] as! Int, meta["falling"] as! Int))
            if let b = sc.behaviour { let fw = b.life.fireworks.filter { Double(s.t) - $0.t0 <= 3800 }.count; if fw > 0 { print("    fireworks active: \(fw)") } }
            if p24 > 0.1 || p6 > GATE_PCT6 || mae > GATE_MAE || f24 > GATE_FRAME24 || f6 > GATE_FRAME6 || a24 > GATE_AGENT24 || a6 > GATE_AGENT6 { failed = true; print("    ^ over a gate") }
        }
    }
    print(failed ? "LIVE PROOF: FAILED (a sample is over a gate)" : "LIVE PROOF: all samples within the gates")
    exit(failed ? 3 : 0)

case "bench":
    // bench <atlas dir> <fixtures dir> <fixture> <work|idle|life> <seconds> [label]: the scene driven like the app drives it (update(_:) at the rate it
    // asks for, paused when it naps) over a scripted run on a virtual clock. Prints main-thread ms per frame, frames requested per second
    // and the nodes made after the first 35 s; with `check` as the 8th argument it exits 3 when an idle house does not rest or a steady
    // one keeps making nodes.
    //   work: the fixture's rows as they are (agents working); idle: no agents, no residents; life: no agents, the life layer on.
    let atlas = URL(fileURLWithPath: args[2], isDirectory: true), fixDir = URL(fileURLWithPath: args[3], isDirectory: true)
    let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: fixDir.appendingPathComponent(args[4] + ".json"))) as! [String: Any]
    let kind = args[5], seconds0 = Double(args[6])!, label = args.count > 7 ? args[7] : kind, check = args.count > 8 && args[8] == "check"
    let input = fixture["input"] as! [String: Any]
    let events = (input["events"] as! [[String: Any]]).filter { $0["rows"] != nil }
    func rows(_ e: [String: Any]) -> [HouseAgentRow] { try! JSONDecoder().decode([HouseAgentRow].self, from: JSONSerialization.data(withJSONObject: e["rows"]!)) }
    let rng = HouseRandom(seed: UInt32(input["seed"] as! Int))
    let behaviour = HouseBehaviour(layout: .islands, canvas: .init(width: 1728, height: 1117, dpr: 2), insets: .init(top: 0, bottom: 0, right: 0), random: { rng.nextDouble() })
    if kind != "idle" && kind != "type" { behaviour.enableLife(hour: 12, dark: 0) }
    let lay = behaviour.layout
    let even = { (v: Double) in (v / texScale / 2).rounded(.up) * 2 }
    let size = CGSize(width: even(Double(lay.view.width)), height: even(Double(lay.view.height)))
    guard let sc = HouseScene2.load(from: atlas, layout: lay, unit: CGFloat(1 / texScale), size: size) else { print("no atlas"); exit(1) }
    sc.followsLayoutScale = false; sc.followClock = true
    sc.env = HouseSkyEnv(innerHeight: 1117, insetBottom: 0)
    sc.attach(behaviour)
    let v = SKView(frame: NSRect(origin: .zero, size: size)); v.ignoresSiblingOrder = true
    sc.setTime(hour: 12, day: 100)
    v.presentScene(sc)
    spin(1.0)
    func count(_ n: SKNode) -> Int { n.children.reduce(1) { $0 + count($1) } }
    // walk: the rows alternate every 6 s so agents keep changing rooms; type: the fixture's rows, measured after they have settled (35 s on)
    var pending = kind == "work" || kind == "type" ? events : []
    if kind == "walk" { behaviour.setAgents(rows(events[1])) }
    if kind == "idle" || kind == "life" { behaviour.setAgents([]) }
    var lastFlip = -1, why = [String: Int]()
    let seconds = kind == "type" ? seconds0 + 55 : seconds0
    var T = 1000.0, frames = 0, spent = 0.0, worst = [Double](), nodes20 = 0, created20 = 0, framesAfter20 = 0, spentAfter20 = 0.0
    var paused = false, pausedAt: Double?
    let start = T
    sc.update(T) // the first update only anchors lastTime
    while T - start < seconds {
        while let e = pending.first, Double(e["at"] as! Int) / 1000 <= T - start { behaviour.setAgents(rows(e)); pending.removeFirst() }
        if v.isPaused { if pausedAt == nil { pausedAt = T - start }; paused = true; T += 0.5; continue } // the minute timer is not simulated
        if kind == "walk", Int((T - start) / 6) != lastFlip { lastFlip = Int((T - start) / 6); behaviour.setAgents(rows(events[lastFlip % 2 == 0 ? 2 : 0])) }
        let t0 = ProcessInfo.processInfo.systemUptime
        sc.update(T)
        let ms = (ProcessInfo.processInfo.systemUptime - t0) * 1000
        frames += 1; spent += ms; worst.append(ms)
        if T - start >= (kind == "type" ? 55 : 35) { framesAfter20 += 1; spentAfter20 += ms } else { nodes20 = count(sc); created20 = HouseRects.created }
        #if !OLDREV
        if kind == "type", T - start >= 55, let sim = sc.sim {
            let b = sc.behaviour
            for (k, on) in [("settling", sim.roomsSettling), ("rows", sc.pendingRows != nil), ("cab", sim.cabins.contains { $0.state != "idle" }), ("link", sim.links.contains { $0.turn != nil }),
                            ("puff", !(b?.puffs.isEmpty ?? true)), ("paper", !(b?.papers.isEmpty ?? true)), ("fw", !(b?.life.fireworks.isEmpty ?? true)),
                            ("path", sim.sprites.contains { !$0.path.isEmpty }), ("bridge", sim.sprites.contains { $0.onBridge != nil }), ("fall", sim.sprites.contains { $0.fall != nil }),
                            ("hand", sim.sprites.contains { $0.behaviour.handover != nil }), ("fade", sim.sprites.contains { $0.alpha != $0.fade }), ("moving", sim.sprites.contains { $0.moving })] where on { why[k, default: 0] += 1 }
        }
        #endif
        T += 1 / Double(max(1, sc.rate))
    }
    worst.sort()
    let p95 = worst.isEmpty ? 0 : worst[min(worst.count - 1, Int(Double(worst.count) * 0.95))]
    let madeAfter = HouseRects.created - created20, nodesEnd = count(sc)
    let steady = kind == "type"
    let nF = steady ? framesAfter20 : frames, nMs = steady ? spentAfter20 : spent
    print(String(format: "bench %@: %d frames in %.0f s = %.1f frames/s requested, %.2f ms/frame mean (%.2f p95), %.1f ms of main thread per second; nodes %d -> %d, pool nodes made after 35 s: %d, paused %@",
                 label as NSString, nF, seconds0, Double(nF) / seconds0, nF > 0 ? nMs / Double(nF) : 0, p95, nMs / seconds0, nodes20, nodesEnd, madeAfter,
                 paused ? "at \(Int(pausedAt ?? 0)) s" as NSString : "never" as NSString))
    #if !OLDREV
    if kind == "type" { print("  type why60 frames:", why.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")) }
    #endif
    var bad = false
    if check {
        if kind == "idle" && !(paused && (pausedAt ?? 99) <= 10) { print("FAIL: the idle house did not rest within 10 s"); bad = true }
        if madeAfter > (kind == "walk" ? 12 : 0) || nodesEnd > nodes20 + 8 { print("FAIL: nodes are made in steady state (made \(madeAfter), count \(nodes20) -> \(nodesEnd))"); bad = true }
        print(bad ? "BENCH CHECK: FAILED" : "BENCH CHECK: ok")
    }
    exit(bad ? 3 : 0)

case "selftest":
    // selftest <atlas>: the atlas guards (exact variant, short arrays, corrupt page) and the growth store; exits 1 on the first failure
    let atlas = URL(fileURLWithPath: args[2], isDirectory: true)
    var bad = 0
    func check(_ ok: Bool, _ what: String) { print((ok ? "ok   " : "FAIL ") + what); if !ok { bad += 1 } }
    let data = try Data(contentsOf: atlas.appendingPathComponent("parts.json"))
    let parts = try JSONDecoder().decode(HouseParts.self, from: data)
    check(parts.problem() == nil, "the shipped atlas passes problem()")
    let exactIdx = parts.light.variants.firstIndex { $0.exact == true } ?? -1
    check(exactIdx >= 0 && parts.variant(dark: 0.3) == exactIdx, "DARK == 0.3 picks the exact variant (\(exactIdx))")
    check(parts.variant(dark: 0.2999) != exactIdx && parts.variant(dark: 0.3001) != exactIdx, "DARK 0.2999 / 0.3001 do not")
    check(parts.variant(dark: 0.19) == 0 && parts.variant(dark: 0.96) == parts.light.variants.count - 2, "the ends of the range")
    var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    var sky = obj["sky"] as! [String: Any]; sky["ground"] = -5; obj["sky"] = sky
    let negative = try JSONDecoder().decode(HouseParts.self, from: JSONSerialization.data(withJSONObject: obj))
    check(negative.problem() != nil, "a negative ground is refused")
    obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    obj["clockColors"] = Array((obj["clockColors"] as! [Any]).dropLast(2))
    let short = try JSONDecoder().decode(HouseParts.self, from: JSONSerialization.data(withJSONObject: obj))
    check(short.problem() != nil, "short variant arrays are refused")
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("house-selftest-\(getpid())", isDirectory: true)
    try? FileManager.default.removeItem(at: tmp)
    try FileManager.default.copyItem(at: atlas, to: tmp)
    try Data("not a png".utf8).write(to: tmp.appendingPathComponent(parts.pages[0].file))
    check(HousePages(parts: parts, dir: tmp) == nil, "a corrupt page is refused at load")
    try? FileManager.default.removeItem(at: tmp)
    let suite = "house-selftest-\(getpid())", ud = UserDefaults(suiteName: suite)!
    ud.removePersistentDomain(forName: suite)
    let g = HouseGrowthStore(defaults: ud)
    let beh = HouseBehaviour(seed: 1)
    beh.setAgents([HouseAgentRow(id: "a", project: "p"), HouseAgentRow(id: "b", project: "p"), HouseAgentRow(id: "c", project: "")])
    check(g.capture(from: beh) && g.level(project: "p") == 1 && g.level(project: "") == 0, "capture: two ids make level 1, the nameless project is \"—\"")
    check(!g.capture(from: beh), "capture: unchanged counts change nothing")
    let other = HouseBehaviour(seed: 1)
    g.seed(other)
    check(other.growth.first { $0.project == "p" }?.n == 2, "seed: a behaviour starts from the stored counts")
    check(g.merge(page: ["p": ["n": 7, "ids": ["x"]], "q": ["n": 1, "ids": []]]) && g.level(project: "p") == 2, "merge: the page's larger count wins")
    check(!g.merge(page: ["p": ["n": 3, "ids": []]]) && g.level(project: "p") == 2, "merge: a smaller one does not")
    check(HouseGrowthStore(defaults: ud).level(project: "p") == 2, "the count survives a restart")
    check(g.merge(page: "junk") == false && g.merge(page: ["z": ["n": -4]]) == false, "merge: junk is ignored")
    ud.removePersistentDomain(forName: suite)
    print(bad == 0 ? "SELFTEST: ok" : "SELFTEST: \(bad) failed")
    exit(bad == 0 ? 0 : 1)

case "hitch":
    // hitch <atlas> <projects>: main-thread cost of the per-minute refresh and of a light-variant change
    let atlas = URL(fileURLWithPath: args[2], isDirectory: true), n = Int(args[3]) ?? 14
    let layout = makeLayout(projects: n, innerW: 1728, innerH: 1117, insets: .init(top: 32, bottom: 70, right: 120))
    let (scene, view) = makeScene(atlas: atlas, layout: layout)
    _ = view
    scene.env = HouseSkyEnv(innerHeight: 1117, insetBottom: 70)
    scene.freezeClock = true; scene.colon = true
    var applied: [Double] = []
    #if !OLDPAINT
    scene.onApply = { applied.append($0) }
    #endif
    func ms(_ f: () -> Void) -> Double { let t = CACurrentMediaTime(); f(); return (CACurrentMediaTime() - t) * 1000 }
    let first = ms { scene.setTime(hour: 12, day: 294) }
    spin(1.0)
    var minute: [Double] = [], variant: [(Double, Double)] = []
    for k in 1...4 {
        applied.removeAll()
        let m: Double = 12.0 + Double(k) / 60.0
        let t0: Double = ms { scene.setTime(hour: m, day: 294) }
        spin(0.6)
        let extra: Double = applied.reduce(0.0, +)
        minute.append(t0 + extra)
    }
    for h in [14.0, 16.6, 18.6, 19.0, 20.1, 21.0, 22.0, 23.0, 3.0, 5.2, 6.0, 7.0, 9.0] {
        applied.removeAll()
        let v0 = scene.light.variant
        let t = ms { scene.setTime(hour: h, day: 294) }
        spin(0.6)
        if scene.light.variant != v0 { variant.append((t + applied.reduce(0, +), Double(scene.light.variant))) }
    }
    let mStr: String = minute.map { String(format: "%.1f", $0) }.joined(separator: " ")
    let vStr: String = variant.map { String(format: "%.0f(v%d)", $0.0, Int($0.1)) }.joined(separator: " ")
    print("n=\(n) first build \(first) ms; per-minute main ms: \(mStr); variant changes main ms: \(vStr)")
    exit(0)

case "snapdemo":
    // snapdemo <atlas> <projects> <hour> <seconds> <out.png>
    let atlas = URL(fileURLWithPath: args[2], isDirectory: true), n = Int(args[3]) ?? 3, hour = Double(args[4]) ?? 12, secs = Double(args[5]) ?? 20
    let layout = makeLayout(projects: n, innerW: 1728, innerH: 1117, insets: .init(top: 38, bottom: 73, right: 120))
    let (scene, view) = makeScene(atlas: atlas, layout: layout)
    scene.env = HouseSkyEnv(innerHeight: 1117, insetBottom: 73)
    scene.freezeClock = true; scene.colon = true
    scene.setTime(hour: hour, day: 294)
    let sim = HouseSim(layout: layout)
    var vendors: [String: String] = [:]
    func goal(_ sp: HouseSprite, _ room: String, _ cat: String) {
        let spots = sim.spots(room)[cat] ?? []
        let p = spots.first.map { [$0[0], $0[1]] } ?? [sim.hub(room)[0], sim.hub(room)[1]]
        sim.setGoal(sp, HouseGoal(room: room, p: p, cat: cat))
    }
    let rooms = layout.rooms.map(\.key).filter { !$0.hasPrefix("__") }
    for (i, key) in (["__bath"] + rooms + ["__kitchen"]).prefix(5).enumerated() {
        let sp = sim.spawn(id: "a\(i)", room: i == 0 ? "__bath" : key, small: i % 2 == 1)
        sp.state = "working"
        vendors["a\(i)"] = i % 2 == 0 ? "claude" : "codex"
        _ = sp
    }
    // send the first agents a floor up and across the village
    for (i, sp) in sim.sprites.enumerated() {
        let target = (rooms.isEmpty ? ["__kitchen"] : rooms)[i % max(1, rooms.count)]
        goal(sp, target, "desk")
    }
    scene.sim = sim
    scene.look = { HouseLook(vendor: vendors[$0.id] ?? "claude", activity: "Edit · f.swift") }
    var t = 0.0
    while t < secs * 1000 { sim.step(dt: 50); t += 50 }
    scene.clockMillis = 100_000 + t
    scene.sync(sim: sim)
    let img = render(scene, view: view)
    try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[6]))
    print("snapdemo \(img.width)x\(img.height) sprites \(sim.sprites.map { "\($0.id)@\($0.room ?? "transit")" })")

case "idle", "demo":
    let atlas = URL(fileURLWithPath: args[2], isDirectory: true), n = Int(args[3]) ?? 3, secs = Double(args[4]) ?? 20
    let screen = NSScreen.screens[0]
    let layout = makeLayout(projects: n, innerW: Double(screen.frame.width), innerH: Double(screen.frame.height), insets: .init(top: 38, bottom: 73, right: 120))
    let unit = CGFloat(layout.view.PXD / layout.view.DPR)
    guard let scene = HouseScene2.load(from: atlas, layout: layout, unit: unit, size: screen.frame.size) else { print("no atlas"); exit(1) }
    scene.env = HouseSkyEnv(innerHeight: Double(screen.frame.height), insetBottom: 73)
    let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
    w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    w.isOpaque = true; w.backgroundColor = .black; w.ignoresMouseEvents = true
    let view = SKView(frame: NSRect(origin: .zero, size: screen.frame.size))
    view.ignoresSiblingOrder = true
    view.preferredFramesPerSecond = 60
    view.showsFPS = true; view.showsDrawCount = true; view.showsNodeCount = true
    w.contentView = view
    scene.setTime(hour: 12, day: 294)
    if mode == "demo" {
        let sim = HouseSim(layout: layout)
        for (i, key) in (["__bath", "__kitchen"] + layout.rooms.map(\.key).filter { !$0.hasPrefix("__") }).prefix(3).enumerated() {
            let sp = sim.spawn(id: "a\(i)", room: key); sp.state = "working"
        }
        scene.sim = sim; scene.driveSim = true
    }
    view.presentScene(scene)
    w.orderFrontRegardless()
    var frames = 0
    scene.onFrame = { _ in frames += 1 }
    Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in print("fps \(Double(frames) / 5)"); frames = 0; fflush(stdout) }
    DispatchQueue.main.asyncAfter(deadline: .now() + secs) { exit(0) }
    app.run()

default:
    print("usage: harness proof <atlas> <ref dir> <out dir> | snapdemo <atlas> <n> <hour> <secs> <png> | idle|demo <atlas> <n> <secs>")
    exit(2)
}
