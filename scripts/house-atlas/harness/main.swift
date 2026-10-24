import AppKit
import NotchCore
import SpriteKit
import Metal
import QuartzCore

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
    defer { v.isPaused = true; v.presentScene(nil) } // its display link would keep running for the life of the process
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
        behaviour.enableSkyLife() // the page draws its sky life in this proof (live-ref.js), with the sim's random numbers
        // the eggs the case names (live-ref.js: trigger names and date=YYYY-MM-DD), triggered at 1000 ms like the page
        let eggSpec = first["egg"] as? [String]
        if let eggSpec {
            behaviour.enableEggs()
            behaviour.eggs?.dark = first["dark"] as! Double
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
            let ds = eggSpec.first { $0.hasPrefix("date=") }.map { String($0.dropFirst(5)) } ?? "2026-10-15"
            let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd'T'HH:mm"
            let hr = Int(first["hour"] as! Double)
            let at = f.date(from: ds + String(format: "T%02d:00", hr))!
            behaviour.eggs?.calendar = cal; behaviour.eggs?.date = { at }
        }
        var scene: HouseScene2?, view: SKView?
        var bt = 0
        for s in samples {
            // the same timeline as the page: rows at their time, 50 ms steps in between
            while bt <= s.t {
                let ev = events.filter { ($0["at"] as! Int) == bt }.last.map(rows)
                if bt == 1000, let eggSpec { for n in eggSpec where !n.hasPrefix("date=") { _ = behaviour.eggs?.trigger(n, at: Double(bt)) } }
                if bt == 0 { if let ev { behaviour.setAgents(ev) } } else { behaviour.advance(frame: 50, agents: ev) }
                bt += 50
            }
            if ProcessInfo.processInfo.environment["SKY_DEBUG"] != nil {
                let k = behaviour.skyLife, ps = (s.meta["sky"] as? [String: Any])?["birds"] as? [[Double]] ?? []
                print("  sky t=\(s.t) mine", k.birds.map { String(format: "%.1f/%.1f", $0.x, $0.y) }, "plane", k.plane.map { String(format: "%.1f", $0.x) } ?? "-", "page", ps.map { String(format: "%.1f/%.1f", $0[0], $0[1]) })
            }
            if eggSpec != nil, ProcessInfo.processInfo.environment["EGG_DEBUG"] != nil { print("  ufoT page", s.meta["ufoT"] ?? "-"); print("  ufo page", ((s.meta["ufo"] as? [Double]) ?? []), "target", behaviour.eggs?.ufo.map { "\($0.target.id) \($0.target.x) \($0.target.y) \($0.target.z)" } ?? "-", "mine", behaviour.eggs?.ufo.map { [$0.x, $0.y, $0.lift, $0.beam] + ($0.at ?? []) } ?? []) }
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
                guard let sc = HouseScene2.load(from: HouseScene2.atlasDir(atlas, season: meta["season"] as? String ?? "autumn"), layout: lay, unit: CGFloat(1 / texScale), size: size) else { print("no atlas"); exit(1) }
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
            sc.setSeason(meta["season"] as? String ?? "autumn"); sc.weather = meta["weather"] as? String ?? "clear"
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

case "render":
    // render <atlas dir> <fixtures dir> <fixture> <walk|type|idle> <seconds> [label]: the real per-frame cost of drawing. The scene of the app's
    // screen (1728x1117 points, unit PXD/DPR) is driven in real time at the rate it asks for and drawn by SKRenderer with Metal into an
    // offscreen 2x texture (the app's drawable), no window. Prints the process CPU (getrusage user+sys) over the measured seconds as % of
    // one core, the frames drawn per second and the main-thread ms of update+encode. The house naps like the app's (3 s still: no frames).
    //   walk: rows alternate every 6 s; type: the fixture's rows, measured after 55 s of settling on a virtual clock; idle: no agents.
    let atlas = URL(fileURLWithPath: args[2], isDirectory: true), fixDir = URL(fileURLWithPath: args[3], isDirectory: true)
    let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: fixDir.appendingPathComponent(args[4] + ".json"))) as! [String: Any]
    let kind = args[5], seconds = Double(args[6])!, label = args.count > 7 ? args[7] : kind
    let input = fixture["input"] as! [String: Any]
    let events = (input["events"] as! [[String: Any]]).filter { $0["rows"] != nil }
    func rows(_ e: [String: Any]) -> [HouseAgentRow] { try! JSONDecoder().decode([HouseAgentRow].self, from: JSONSerialization.data(withJSONObject: e["rows"]!)) }
    let rng = HouseRandom(seed: UInt32(input["seed"] as! Int))
    let behaviour = HouseBehaviour(layout: .islands, canvas: .init(width: 1728, height: 1117, dpr: 2), insets: .init(top: 38, bottom: 73, right: 120), random: { rng.nextDouble() })
    if kind == "walk" || kind == "crowd" { behaviour.enableLife(hour: 12, dark: 0) }
    // crowd: the fixture's first rows (14-projects: 14 agents in 14 rooms, with context batteries), each agent moving one room on every 6 s
    let crowd0 = kind == "crowd" ? rows(events[0]) : []
    func crowd(_ k: Int) -> [HouseAgentRow] {
        crowd0.enumerated().map { i, r in var r = r; r.project = crowd0[(i + k) % crowd0.count].project; r.state = "working"; return r }
    }
    if kind == "crowd" { behaviour.setAgents(crowd(0)) }
    let lay = behaviour.layout
    let pts = CGSize(width: 1728, height: 1117)
    guard let sc = HouseScene2.load(from: atlas, layout: lay, unit: CGFloat(lay.view.PXD / lay.view.DPR), size: pts) else { print("no atlas"); exit(1) }
    sc.followClock = true
    // the sky follows a clock pinned to RB_HOUR (default noon) of today, running at real speed: the night adds the city's lights
    let pinned = Calendar.current.startOfDay(for: Date()).addingTimeInterval((Double(ProcessInfo.processInfo.environment["RB_HOUR"] ?? "12") ?? 12) * 3600), began = Date()
    sc.wallClock = { pinned.addingTimeInterval(Date().timeIntervalSince(began)) }
    sc.env = HouseSkyEnv(innerHeight: 1117, insetBottom: 73)
    sc.attach(behaviour)
    sc.setTime(hour: 12, day: 100)
    guard let dev = MTLCreateSystemDefaultDevice(), let queue = dev.makeCommandQueue() else { print("no Metal"); exit(1) }
    let renderer = SKRenderer(device: dev)
    renderer.scene = sc
    renderer.ignoresSiblingOrder = true
    if ProcessInfo.processInfo.environment["RB_NOCULL"] != nil { renderer.shouldCullNonVisibleNodes = false }
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 3456, height: 2234, mipmapped: false)
    td.usage = [.renderTarget, .shaderRead]; td.storageMode = .private
    let targets = (0..<3).map { _ in dev.makeTexture(descriptor: td)! }
    let inflight = DispatchSemaphore(value: 2)
    var tex = 0, updMs = 0.0, encMs = 0.0
    let noUpdate = ProcessInfo.processInfo.environment["RB_NOUPDATE"] != nil, noRender = ProcessInfo.processInfo.environment["RB_NORENDER"] != nil
    func draw(_ t: TimeInterval) {
        let u0 = CACurrentMediaTime()
        if !noUpdate || tex == 0 { renderer.update(atTime: t) }
        if noRender && tex > 0 { return }
        let u1 = CACurrentMediaTime(); updMs += (u1 - u0) * 1000
        defer { encMs += (CACurrentMediaTime() - u1) * 1000 }
        inflight.wait()
        let cb = queue.makeCommandBuffer()!
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = targets[tex % 3]; tex += 1
        rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        renderer.render(withViewport: CGRect(x: 0, y: 0, width: 3456, height: 2234), commandBuffer: cb, renderPassDescriptor: rp)
        cb.addCompletedHandler { _ in inflight.signal() }
        cb.commit()
    }
    // warm-up on a virtual clock (type: until the rows settle), then real time from where it left off
    var pending = kind == "type" ? events : []
    if kind == "walk" { behaviour.setAgents(rows(events[1])) }
    if kind == "idle" { behaviour.setAgents([]) }
    var V = 1000.0
    draw(V)
    let warm = kind == "type" ? 55.0 : 2.0
    while V - 1000 < warm {
        while let e = pending.first, Double(e["at"] as! Int) / 1000 <= V - 1000 { behaviour.setAgents(rows(e)); pending.removeFirst() }
        sc.update(V); V += 1 / Double(max(1, sc.rate))
    }
    sc.stillSince = nil
    // probes for finding the cost (wrong pixels): RB_NOSHADER strips the shaders, RB_HIDE=root|movers|sky hides a group
    let env = ProcessInfo.processInfo.environment
    func walkNodes(_ n: SKNode, _ f: (SKNode) -> Void) { f(n); for c in n.children { walkNodes(c, f) } }
    if env["RB_NOSHADER"] != nil { walkNodes(sc) { ($0 as? SKSpriteNode)?.shader = nil } }
    let hideKinds = Set((env["RB_HIDE"] ?? "").split(separator: ",").map(String.init))
    for k in hideKinds where ["root", "movers", "sky"].contains(k) { (k == "root" ? sc.root : k == "movers" ? sc.movers : sc.skyGroup).isHidden = true }
    // live: the painted signs, clocks and panes; color: untextured sprites (marks, batteries, ropes); battery: the movers' info rects
    if hideKinds.contains("live") { for l in sc.liveItems { l.node?.alpha = 0; l.node?.removeFromParent() } }
    if hideKinds.contains("color") { walkNodes(sc) { if let s = $0 as? SKSpriteNode, s.texture == nil { s.removeFromParent() } } }
    if hideKinds.contains("battery") { for (_, r) in sc.infoRects { r.removeFromParent() } }
    draw(V); spin(1.0)
    func cpu() -> Double { var u = rusage(); getrusage(RUSAGE_SELF, &u); return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6 }
    func work() -> (ins: Double, cyc: Double, p: Double) {
        var ri = rusage_info_v6()
        let ok = withUnsafeMutablePointer(to: &ri) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0) } }
        guard ok == 0 else { return (0, 0, 0) }
        return (Double(ri.ri_instructions), Double(ri.ri_cycles), Double(ri.ri_user_ptime + ri.ri_system_ptime) / 1e9)
    }
    let t0 = CACurrentMediaTime(), c0 = cpu(), w0 = work(), base = V - t0
    updMs = 0; encMs = 0
    var frames = 0, mainMs = 0.0, napped = 0.0, lastFlip = -1, at60 = 0
    var next = t0
    while CACurrentMediaTime() - t0 < seconds {
        let now = CACurrentMediaTime()
        if now < next { RunLoop.current.run(until: Date(timeIntervalSinceNow: next - now)); continue }
        if kind == "walk", Int((now - t0) / 6) != lastFlip { lastFlip = Int((now - t0) / 6); behaviour.setAgents(rows(events[lastFlip % 2 == 0 ? 2 : 0])) }
        if kind == "crowd", Int((now - t0) / 6) != lastFlip { lastFlip = Int((now - t0) / 6); behaviour.setAgents(crowd(lastFlip + 1)) }
        if let s = sc.stillSince, (base + now) - s >= 3 { napped += 0.5; next = now + 0.5; continue } // the app's view rests until the next minute
        let a = CACurrentMediaTime()
        draw(base + now)
        mainMs += (CACurrentMediaTime() - a) * 1000
        frames += 1
        if sc.rate >= 60 { at60 += 1 }
        next += 1 / Double(max(1, sc.rate))
        if next < now { next = now + 1 / Double(max(1, sc.rate)) / 2 }
    }
    let wall = CACurrentMediaTime() - t0, used = cpu() - c0, w1 = work()
    func count(_ n: SKNode) -> Int { n.children.reduce(1) { $0 + count($1) } }
    func drawn(_ n: SKNode) -> Int { n.isHidden ? 0 : n.children.reduce(n is SKSpriteNode ? 1 : 0) { $0 + drawn($1) } }
    func shaded(_ n: SKNode) -> Int { n.isHidden ? 0 : n.children.reduce((n as? SKSpriteNode)?.shader != nil ? 1 : 0) { $0 + shaded($1) } }
    print(String(format: "render %@: CPU %.1f%% of a core, %.1f fps drawn (%d%% of frames at the 60 rate), %.2f ms main per frame (update %.2f + render %.2f), napped %.0f s; nodes %d, sprites drawn %d (shaded %d); %.1f M instructions/s, %.1f M cycles/s, %.0f%% of the CPU time on P cores",
                 label as NSString, 100 * used / wall, Double(frames) / wall, frames > 0 ? 100 * at60 / frames : 0, frames > 0 ? mainMs / Double(frames) : 0, updMs / Double(max(1, frames)), encMs / Double(max(1, frames)), napped,
                 count(sc), drawn(sc), shaded(sc), (w1.ins - w0.ins) / wall / 1e6, (w1.cyc - w0.cyc) / wall / 1e6, 100 * (w1.p - w0.p) / max(1e-9, used)))
    if env["RB_GROUPS"] != nil {
        func drawnIn(_ n: SKNode) -> Int { n.isHidden ? 0 : n.children.reduce(n is SKSpriteNode ? 1 : 0) { $0 + drawnIn($1) } }
        for (name, g) in [("sky", sc.skyGroup), ("mist", sc.mistGroup), ("movers", sc.movers)] {
            var kinds: [String: Int] = [:]
            for c in g.children where !c.isHidden { kinds["\(type(of: c))/\(c.name ?? "-")/children \(c.children.count)", default: 0] += 1 }
            print("  \(name): drawn \(drawnIn(g)); \(kinds.sorted { $0.value > $1.value }.prefix(10))")
        }
        var rootKinds: [String: Int] = [:]
        for c in sc.root.children where !c.isHidden && c !== sc.skyGroup && c !== sc.mistGroup { rootKinds["\(type(of: c))/shader \((c as? SKSpriteNode)?.shader != nil)/tex \((c as? SKSpriteNode)?.texture != nil)", default: 0] += 1 }
        print("  root: drawn \(drawnIn(sc.root) - drawnIn(sc.skyGroup) - drawnIn(sc.mistGroup)); \(rootKinds)")
    }
    if env["RB_SEGMENTS"] != nil {
        // how far the static house could fold: runs of static sprites in z order, broken by any place a mover can stand and any node that changes
        var dyn = Set<ObjectIdentifier>()
        for (n, _) in sc.glows { dyn.insert(ObjectIdentifier(n)) }
        for (_, v) in sc.dynNodes { dyn.insert(ObjectIdentifier(v.node)) }
        for (_, n) in sc.lampNodes { dyn.insert(ObjectIdentifier(n)) }
        for p in sc.cagePieces { dyn.insert(ObjectIdentifier(p.node)) }
        for l in sc.liveItems { if let n = l.node { dyn.insert(ObjectIdentifier(n)) } }
        for (_, i) in sc.linkInfo { for n in i.down + i.up { dyn.insert(ObjectIdentifier(n)) } }
        var cuts: [CGFloat] = [sc.topZ]
        for (_, i) in sc.roomInfo { cuts += i.slots.map { $0.z - 4 }; cuts.append(i.endZ) }
        for (_, i) in sc.linkInfo { cuts += [i.backZ + 4, i.stepsZ + 4] }
        for (_, f) in sc.riderZ { cuts += f.values }
        var items: [(CGFloat, Bool)] = []
        for c in sc.root.children where c !== sc.skyGroup && c !== sc.mistGroup && !c.isHidden {
            items.append((c.zPosition, c is SKSpriteNode && !(c is HouseRects) && !dyn.contains(ObjectIdentifier(c)) && (c as! SKSpriteNode).shader != nil))
        }
        for z in cuts { items.append((z, false)) }
        items.sort { $0.0 < $1.0 }
        var runs = 0, inRun = false, st = 0, dy = 0
        for (_, s) in items { if s { st += 1; if !inRun { runs += 1; inRun = true } } else { inRun = false } }
        dy = sc.root.children.filter { !$0.isHidden && dyn.contains(ObjectIdentifier($0)) }.count
        var zeroA = 0; walkNodes(sc) { if !$0.isHidden && $0.alpha == 0 && $0 is SKSpriteNode { zeroA += 1 } }
        print("  glows \(sc.glows.count) (alpha 0: \(sc.glows.filter { $0.0.alpha == 0 }.count)); visible sprites with alpha 0: \(zeroA)")
        print("  static sprites \(st) in \(runs) runs between \(cuts.count) mover places; changing nodes \(dy)")
    }
    if env["RB_BATCHES"] != nil {
        // an estimate of SpriteKit's batches: the drawn sprites in z order, a new batch where the texture's backing, the shader or the blend changes
        var page: [ObjectIdentifier: String] = [:]
        for id in 0..<sc.parts.sprites.count { let r = sc.pages.rect(id); page[ObjectIdentifier(sc.pages.texture(id))] = sc.pages.sparsePages.contains(r.page) ? "cut\(id)" : "p\(r.page)" }
        var list: [(CGFloat, String, String)] = []
        func gather(_ n: SKNode, _ z: CGFloat) {
            guard !n.isHidden, n.alpha > 0 else { return }
            let zz = z + n.zPosition
            if let s = n as? SKSpriteNode {
                let t = s.texture.map { page[ObjectIdentifier($0)] ?? "own\(ObjectIdentifier($0).hashValue)" } ?? "color"
                list.append((zz, t, (s.shader.map { "\(ObjectIdentifier($0).hashValue)" } ?? "-") + "/\(s.blendMode.rawValue)"))
            }
            for c in n.children { gather(c, zz) }
        }
        gather(sc, 0)
        list.sort { $0.0 < $1.0 }
        var batches = 0, prev = ""
        var why: [String: Int] = [:]
        for (_, t, sh) in list { let k = t + "|" + sh; if k != prev { batches += 1; why[t.hasPrefix("own") ? "own" : t.hasPrefix("cut") ? "cut" : t, default: 0] += 1 }; prev = k }
        print("  batches ~\(batches) for \(list.count) sprites; batch starts by texture: \(why.sorted { $0.value > $1.value }.prefix(8))")
    }
    exit(0)

#if !OLDREV // the pointer: not in the revisions bench.sh compares against
case "interact":
    // interact <atlas> <ref dir> <fixtures dir> <out dir>: replays the page's pointer / pinch / scroll / click sequence (interact-ref.js) on the
    // scene and compares the camera, the overview button, the hovered agent, the hover card and the click's {open} at every record;
    // two settled zoomed views are also compared as frames (house and agent pixels, the same gates as the live proof; the sky is magnified
    // here and repainted by the page, so its difference is printed but not gated).
    let atlas = URL(fileURLWithPath: args[2], isDirectory: true), refDir = URL(fileURLWithPath: args[3], isDirectory: true)
    let fixDir = URL(fileURLWithPath: args[4], isDirectory: true), out = URL(fileURLWithPath: args[5], isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let info = try JSONSerialization.jsonObject(with: Data(contentsOf: refDir.appendingPathComponent("interact.json"))) as! [String: Any]
    let name = info["case"] as! String, T0 = info["T0"] as! Int, hour = info["hour"] as! Double
    let ops = info["ops"] as! [[String: Any]], recs = info["recs"] as! [[String: Any]]
    let ins = info["insets"] as! [String: Double], dpr = info["DPR"] as! Double
    let innerW = info["innerWidth"] as! Double, innerH = info["innerHeight"] as! Double
    let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: fixDir.appendingPathComponent(name + ".json"))) as! [String: Any]
    let input = fixture["input"] as! [String: Any]
    let events = (input["events"] as! [[String: Any]]).filter { $0["rows"] != nil }
    func rows(_ e: [String: Any]) -> [HouseAgentRow] { try! JSONDecoder().decode([HouseAgentRow].self, from: JSONSerialization.data(withJSONObject: e["rows"]!)) }
    let rng = HouseRandom(seed: UInt32(input["seed"] as! Int))
    let behaviour = HouseBehaviour(layout: .islands, canvas: .init(width: innerW, height: innerH, dpr: dpr),
                                   insets: .init(top: ins["top"]!, bottom: ins["bottom"]!, right: ins["right"]!), random: { rng.nextDouble() })
    var bt = 0
    while bt <= T0 {
        let ev = events.filter { ($0["at"] as! Int) == bt }.last.map(rows)
        if bt == 0 { if let ev { behaviour.setAgents(ev) } } else { behaviour.advance(frame: 50, agents: ev) }
        bt += 50
    }
    let lay = behaviour.layout
    let even = { (v: Double) in (v / texScale / 2).rounded(.up) * 2 }
    let size = CGSize(width: even(lay.view.width), height: even(lay.view.height))
    guard let sc = HouseScene2.load(from: atlas, layout: lay, unit: CGFloat(1 / texScale), size: size) else { print("no atlas"); exit(1) }
    sc.followsLayoutScale = false; sc.freezeClock = true; sc.freezeSim = true; sc.colon = false
    sc.env = HouseSkyEnv(innerHeight: innerH, insetBottom: ins["bottom"]!)
    sc.attach(behaviour)
    let v = SKView(frame: NSRect(origin: .zero, size: size)); v.ignoresSiblingOrder = true
    sc.setTime(hour: hour, day: 294)
    sc.clockMillis = Double(T0)
    v.presentScene(sc)
    sc.repaint(sync: true)
    if let sim = sc.sim { sc.sync(sim: sim) }
    spin(0.5)
    var VT = 1e6
    sc.nowMs = { VT }
    sc.hudEnabled = false
    sc.installCamera(HouseCamera(layout: lay, innerWidth: innerW, innerHeight: innerH, insets: .init(top: ins["top"]!, bottom: ins["bottom"]!, right: ins["right"]!)))
    var opened: String?
    sc.onOpen = { opened = $0 }
    var failed = false, ri = 0, fresh = false
    func num(_ x: Any?) -> Double { (x as? NSNumber)?.doubleValue ?? .nan }
    func hexNorm(_ h: String) -> String { var s = h.lowercased(); if s.count == 4 { s = "#" + s.dropFirst().map { "\($0)\($0)" }.joined() }; return s }
    print("record             page zoom  scene zoom  |d at|     home hovered tip   opened")
    for op in ops {
        switch op["op"] as! String {
        case "pointer": sc.pointerMoved(x: num(op["x"]), y: num(op["y"])); fresh = true
        case "leave": sc.pointerLeft(); fresh = true
        case "zoom": sc.zoom(num(op["f"]), x: num(op["x"]), y: num(op["y"])); fresh = false
        case "pan": sc.pan(dx: num(op["dx"]), dy: num(op["dy"])); fresh = false
        case "click": sc.pointerClicked(x: num(op["x"]), y: num(op["y"])); fresh = true
        case "reset": sc.resetView(); fresh = false
        case "ticks":
            for _ in 0..<Int(num(op["n"])) { VT += num(op["dt"]); sc.stepInteraction(frameMs: num(op["dt"])) }
            fresh = false
        case "draw": sc.updateHover(); fresh = true
        case "frame":
            sc.updateHover(); fresh = true
            let fname = op["name"] as! String
            let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: refDir.appendingPathComponent("interact-\(fname)-meta.json"))) as! [String: Any]
            let k = Int((meta["zoom"] as! Double).rounded())
            guard abs(Double(k) - (meta["zoom"] as! Double)) < 1e-9, k >= 1 else { print("frame \(fname): zoom \(meta["zoom"]!) is not whole"); exit(1) }
            sc.repaint(sync: true)
            if let sim = sc.sim { sc.sync(sim: sim) }
            spin(0.8)
            if let sim = sc.sim { sc.sync(sim: sim) }
            var img = v.texture(from: sc)!.cgImage()
            spin(0.3)
            img = v.texture(from: sc)!.cgImage()
            func up(_ p: (data: [UInt8], w: Int, h: Int)) -> (data: [UInt8], w: Int, h: Int) {
                var d = [UInt8](repeating: 0, count: p.w * k * p.h * k * 4)
                for y in 0..<(p.h * k) { for x in 0..<(p.w * k) { for c in 0..<4 { d[(y * p.w * k + x) * 4 + c] = p.data[((y / k) * p.w + x / k) * 4 + c] } } }
                return (d, p.w * k, p.h * k)
            }
            let ref = up(pixels(load(refDir.appendingPathComponent("interact-\(fname).png"))))
            // the house's pixels are the ones that differ from the scene's own sky with its glows (house hidden; the halos of lamps lie over the sky): the page's sky-only frame has its own
            // regenerated city (a disc of it differs around a lit window), which is not the house
            let hid = sc.root.children.filter { $0 !== sc.skyGroup && $0 !== sc.mistGroup && !$0.isHidden && ($0 as? SKSpriteNode)?.blendMode != .add }
            hid.forEach { $0.isHidden = true }; sc.movers.isHidden = true
            spin(0.3)
            _ = v.texture(from: sc)
            let skyImg = v.texture(from: sc)!.cgImage()
            hid.forEach { $0.isHidden = false }; sc.movers.isHidden = false
            let skyM = pixels(skyImg)
            let bare = up(pixels(load(refDir.appendingPathComponent("interact-\(fname)-bare.png"))))
            let mineRaw = pixels(img)
            let cw = min(ref.w, mineRaw.w), chh = min(ref.h, mineRaw.h)
            guard ref.w - cw <= 8, ref.h - chh <= 8, mineRaw.w - cw <= 8, mineRaw.h - chh <= 8 else { print("frame \(fname): size \(mineRaw.w)x\(mineRaw.h) vs \(ref.w)x\(ref.h)"); exit(1) }
            // the house is what the scene draws over its own sky inside a room's outline (an island slab, a tower), widened by 8 art pixels;
            // the page repaints sky, city and mist for the zoomed canvas, so what lies outside is the sky's and is only printed
            let pose = sc.houseCamera!.pose, sh = sc.houseCamera!.shiftFromHome(pose)
            let polys = lay.rooms.map { HouseHit.roomOutline($0, in: lay, world: false, island: true) }
            let boxes = polys.map { p in (p.map { $0[0] }.min()! - 8, p.map { $0[0] }.max()! + 8, p.map { $0[1] }.min()! - 8, p.map { $0[1] }.max()! + 8) }
            let aw = cw / k + 2, ah = chh / k + 2
            var inRoom = [Bool](repeating: false, count: aw * ah)
            for ay in 0..<ah { for ax in 0..<aw {
                let lx = Double(ax) + 0.5 - sh.x, ly = Double(ay) + 0.5 - sh.y
                for (i, b) in boxes.enumerated() where lx >= b.0 && lx <= b.1 && ly >= b.2 && ly <= b.3 {
                    if [(0.0, 0.0), (8, 0), (-8, 0), (0, 8), (0, -8)].contains(where: { HouseHit.inside(polys[i], lx + $0.0, ly + $0.1) }) { inRoom[ay * aw + ax] = true; break }
                }
            } }
            var house = 0, off24 = 0, off6 = 0, sumAbs = 0, agent = 0, aOff24 = 0, aOff6 = 0, skyN = 0, skyOff = 0
            var diff = [UInt8](repeating: 255, count: cw * chh * 4), side = [UInt8](repeating: 255, count: cw * 2 * chh * 4)
            for y in 0..<chh { for x in 0..<cw {
                let ri = (y * ref.w + x) * 4, mi = (y * mineRaw.w + x) * 4, p = y * cw + x
                var mx = 0, dBare = 0, dSky = 0
                let si = (y * skyM.w + x) * 4
                for c in 0..<3 {
                    mx = max(mx, abs(Int(ref.data[ri + c]) - Int(mineRaw.data[mi + c])))
                    dBare += abs(Int(ref.data[ri + c]) - Int(bare.data[ri + c])); dSky += abs(Int(mineRaw.data[mi + c]) - Int(skyM.data[si + c]))
                }
                if dSky > 0 && inRoom[(y / k) * aw + x / k] { house += 1; sumAbs += (0..<3).reduce(0) { $0 + abs(Int(ref.data[ri + $1]) - Int(mineRaw.data[mi + $1])) }; if mx > 24 { off24 += 1 }; if mx > 6 { off6 += 1 } }
                else { skyN += 1; if mx > 24 { skyOff += 1 } }
                if dBare > 0 { agent += 1; if mx > 24 { aOff24 += 1 }; if mx > 6 { aOff6 += 1 } }
                for c in 0..<3 { diff[p * 4 + c] = mx > 24 ? (c == 0 ? 255 : 0) : ref.data[ri + c] >> 2 }
                for c in 0..<4 { side[(y * cw * 2 + x) * 4 + c] = ref.data[ri + c]; side[(y * cw * 2 + cw + x) * 4 + c] = mineRaw.data[mi + c] }
            } }
            save(diff, cw, chh, to: out.appendingPathComponent("\(fname)-diff.png"))
            save(side, cw * 2, chh, to: out.appendingPathComponent("\(fname)-side.png"))
            let h = Double(max(1, house)), a = Double(max(1, agent))
            let p24 = 100 * Double(off24) / h, p6 = 100 * Double(off6) / h, mae = Double(sumAbs) / (h * 3), a24 = 100 * Double(aOff24) / a, a6 = 100 * Double(aOff6) / a
            print(String(format: "frame %@ (zoom %d): house %d px, %%24 %.4f, %%6 %.4f, MAE %.3f | agent %d px, %%24 %.3f, %%6 %.3f | sky (not gated) %d px, %.2f%% off", fname as NSString, k, house, p24, p6, mae, agent, a24, a6, skyN, 100 * Double(skyOff) / Double(max(1, skyN))))
            if p24 > 0.1 || p6 > GATE_PCT6 || mae > GATE_MAE || a24 > GATE_AGENT24 || a6 > GATE_AGENT6 { failed = true; print("    ^ over a gate") }
        case "record":
            let r = recs[ri]; ri += 1
            let cam = sc.houseCamera!, pose = cam.pose
            var bad: [String] = []
            let pz = num(r["zoom"]), pat = r["at"] as! [Double]
            let dat = hypot(pat[0] - pose.at[0], pat[1] - pose.at[1])
            if abs(pz - pose.zoom) > 1e-6 { bad.append("zoom") }
            if dat > 1e-6 { bad.append("at") }
            if abs(num(r["tz"]) - cam.target.zoom) > 1e-6 { bad.append("target") }
            if (r["home"] as! Bool) != cam.homeOn { bad.append("home") }
            let po = r["opened"] as? String
            if po != opened { bad.append("opened") }
            var hv = "-", tp = "-"
            if fresh {
                let ph = r["hovered"] as? String
                if ph != sc.hoveredId { bad.append("hovered") }
                hv = ph == sc.hoveredId ? (ph ?? "none") : "\(ph ?? "none")!=\(sc.hoveredId ?? "none")"
                let t = sc.lastTip
                if let pt = r["tip"] as? [String: Any] {
                    let m = pt["mouse"] as Any?; _ = m
                    if let t, t.title == pt["title"] as? String, t.status == pt["status"] as? String, t.detail == pt["detail"] as? String,
                       hexNorm(t.color) == hexNorm(pt["color"] as? String ?? "") { tp = "same" } else { bad.append("tip"); tp = "DIFF" }
                    if let mo = r["mouse"] as? [Double], let t, abs(t.x - mo[0]) > 1e-9 || abs(t.y - mo[1]) > 1e-9 { bad.append("tip xy") }
                } else if t != nil { bad.append("tip"); tp = "extra" } else { tp = "none" }
            }
            opened = nil
            func pad(_ t: String, _ n: Int) -> String { t.count >= n ? t : t + String(repeating: " ", count: n - t.count) }
            print(pad(r["name"] as! String, 18) + String(format: "%9.6f %11.6f  %9.2e  ", pz, pose.zoom, dat) + pad(cam.homeOn ? "on" : "off", 5) + pad(hv, 8) + pad(tp, 6) + (po ?? "-")
                  + (bad.isEmpty ? "" : "   <-- DIFF: " + bad.joined(separator: ",")))
            if !bad.isEmpty { failed = true }
        default: break
        }
    }
    guard ri == recs.count else { print("replayed \(ri) of \(recs.count) records"); exit(1) }
    print(failed ? "INTERACT PROOF: FAILED" : "INTERACT PROOF: the scene answers like the page (\(recs.count) records)")
    exit(failed ? 3 : 0)

#endif
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

#if !OLDREV // the pointer, the saver and the extra screen: not in the revisions bench.sh compares against
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

case "addproject":
    // addproject <atlas> <projects>: the main-thread cost of a project joining, through the path the app takes: scene.deliver(rows) then the
    // next frame's advanceBehaviour (HouseBehaviour relays out, followBehaviour rebuilds the scene), plus the paint that is swapped in after.
    // Warm-up first; the figure is the median of five joins (each from n projects to n+1, the scene fresh each time).
    let atlas = URL(fileURLWithPath: args[2], isDirectory: true), n = Int(args[3]) ?? 5
    let ins = HouseLayout.Insets(top: 32, bottom: 70, right: 120)
    func rows(_ k: Int) -> [HouseAgentRow] { (0..<k).map { HouseAgentRow(id: "a\($0)", project: NAMES[$0], state: "working", title: "t\($0)") } }
    func ms(_ f: () -> Void) -> Double { let t = CACurrentMediaTime(); f(); return (CACurrentMediaTime() - t) * 1000 }
    var advances: [Double] = [], applies: [Double] = [], gaps: [Double] = []
    for k in 0..<7 {
        let rng = HouseRandom(seed: 7 + UInt32(k))
        let behaviour = HouseBehaviour(layout: .islands, canvas: .init(width: 1728, height: 1117, dpr: 2), insets: ins, random: { rng.nextDouble() })
        behaviour.setAgents(rows(n))
        let (scene, view) = makeScene(atlas: atlas, layout: behaviour.layout)
        scene.env = HouseSkyEnv(innerHeight: 1117, insetBottom: 70)
        scene.freezeClock = true; scene.colon = true; scene.freezeSim = true
        scene.attach(behaviour)
        view.presentScene(scene)
        scene.setTime(hour: 12, day: 294)
        spin(1.0)
        var applied: [Double] = []
        scene.onApply = { applied.append($0) }
        // the longest stall of the main run loop over the join and the second after it (a 2 ms ticker that records the gap between ticks)
        var last = CACurrentMediaTime(), worst = 0.0
        let ticker = Timer(timeInterval: 0.002, repeats: true) { _ in let t = CACurrentMediaTime(); worst = max(worst, (t - last) * 1000); last = t }
        RunLoop.main.add(ticker, forMode: .common)
        scene.deliver(rows(n + 1))
        let a = ms { scene.advanceBehaviour(ms: 16) }
        spin(1.2)
        ticker.invalidate()
        if k >= 2 { advances.append(a); applies.append(applied.reduce(0, +)); gaps.append(worst) }
    }
    func med(_ a: [Double]) -> Double { a.sorted()[a.count / 2] }
    print(String(format: "ADDPROJECT n=%d->%d: advanceBehaviour main %.1f ms (median of %d, max %.1f), async apply on main %.1f ms; total %.1f ms; longest main-loop stall in the next 1.2 s %.1f ms (max %.1f)",
                 n, n + 1, med(advances), advances.count, advances.max()!, med(applies), med(advances) + med(applies), med(gaps), gaps.max()!))
    // gate: a join must stay well inside one 60 Hz frame (measured 1.4-3.5 ms; 4x headroom for a loaded machine)
    if med(advances) + med(applies) > 8 { print("ADDPROJECT: over the 8 ms gate"); exit(3) }
    exit(0)

case "saver":
    // saver <atlas> <out.png>: the screen saver's SpriteKit house (SaverSpriteHouse) from a snapshot, as the saver builds it. Gates: it is built for the
    // snapshot's projects, takes a later snapshot's agents, shows a house (not blank), draws every season, and refuses what the atlas cannot draw (another layout).
    let atlas = URL(fileURLWithPath: args[2], isDirectory: true), out = args[3]
    let agentsJSON = { (n: Int) in String(data: try! JSONEncoder().encode((0..<n).map { HouseAgentRow(id: "a\($0)", project: NAMES[$0], state: "working", title: "t\($0)") }), encoding: .utf8)! }
    func snap(_ n: Int, config: String = #"{"layout":"islands","themes":{}}"#) -> HouseSnapshot { HouseSnapshot(agents: agentsJSON(n), usage: nil, config: config, fps: 30, written: Date(), renderer: "spritekit") }
    var bad = 0
    func check(_ ok: Bool, _ what: String) { print(ok ? "ok   \(what)" : "FAIL \(what)"); if !ok { bad += 1 } }
    check(SaverSpriteHouse(size: CGSize(width: 1728, height: 1117), scale: 2, atlas: atlas, snapshot: snap(2), month: 3, onFailure: {}) != nil, "spring: a SpriteKit house")
    check(SaverSpriteHouse(size: CGSize(width: 1728, height: 1117), scale: 2, atlas: atlas, snapshot: snap(2, config: #"{"layout":"tower","themes":{}}"#), month: 10, onFailure: {}) == nil, "another layout: no SpriteKit house")
    check(SaverSpriteHouse(size: CGSize(width: 1728, height: 1117), scale: 2, atlas: URL(fileURLWithPath: "/nonexistent"), snapshot: snap(2), month: 10, onFailure: {}) == nil, "no atlas: no SpriteKit house")
    var failed = false
    guard let house = SaverSpriteHouse(size: CGSize(width: 1728, height: 1117), scale: 2, atlas: atlas, snapshot: snap(2), month: 10, onFailure: { failed = true }) else { print("FAIL cannot build"); exit(3) }
    house.scene.setTime(hour: 12, day: 294)
    spin(1.5)
    let projects = { house.scene.layout.rooms.filter { !$0.key.hasPrefix("__") }.count }
    check(projects() == 2, "built for the snapshot's 2 projects (got \(projects()))")
    house.apply(snap(4))
    house.scene.advanceBehaviour(ms: 16)
    spin(1.5)
    check(projects() == 4, "a later snapshot with 4 projects grows the house (got \(projects()))")
    check(!failed, "no failure callback")
    let img = house.view.texture(from: house.scene)!.cgImage()
    let px = pixels(img)
    var distinct = Set<UInt32>()
    for i in stride(from: 0, to: px.data.count - 3, by: 4 * 37) { distinct.insert(UInt32(px.data[i]) << 16 | UInt32(px.data[i + 1]) << 8 | UInt32(px.data[i + 2])) }
    check(distinct.count > 40, "the frame shows a house (\(distinct.count) distinct colours sampled)")
    if let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil) { CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d) }
    print(bad == 0 ? "SAVER PROOF: ok" : "SAVER PROOF: \(bad) failed")
    exit(bad == 0 ? 0 : 3)

case "extra":
    // extra <atlas> <ref dir> <out dir>: the extra screen's sky and city (HouseScene2.extraScreen, an empty layout, no sun or moon) against the page's own
    // ?scene=extra frames (harness/extra-ref.js, islets left out), whole frame, with the scene proof's frame gates.
    let atlas = URL(fileURLWithPath: args[2], isDirectory: true), refDir = URL(fileURLWithPath: args[3], isDirectory: true), out = URL(fileURLWithPath: args[4], isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let metas = try FileManager.default.contentsOfDirectory(atPath: refDir.path).filter { $0.hasPrefix("ref-x") && $0.hasSuffix(".json") }.sorted()
    var failed = metas.isEmpty
    print("fixture      var | frame%24  frame%6  MAE/ch")
    for m in metas {
        let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: refDir.appendingPathComponent(m))) as! [String: Any]
        let hour = meta["hour"] as! Double, W = meta["W"] as! Int, H = meta["H"] as! Int, dpr = meta["DPR"] as! Double
        let layout = HouseLayout.extraScreen(canvas: .init(width: meta["innerW"] as! Double, height: meta["innerH"] as! Double, dpr: dpr))
        guard Int(layout.view.width) == W, Int(layout.view.height) == H, layout.view.PXD == meta["PXD"] as! Double, layout.rooms.isEmpty else {
            print("canvas mismatch \(layout.view.width)x\(layout.view.height)@\(layout.view.PXD) vs \(W)x\(H)@\(meta["PXD"]!)"); exit(1)
        }
        let (scene, view) = makeScene(atlas: atlas, layout: layout)
        scene.extraScreen = ProcessInfo.processInfo.environment["PROOF_SUN"] == nil // PROOF_SUN: a deliberate defect (the main screen's sun and moon on an extra screen), to prove the gate fails
        scene.env = HouseSkyEnv(innerHeight: meta["innerH"] as! Double, insetBottom: 0)
        scene.freezeClock = true; scene.clockMillis = meta["T"] as! Double; scene.colon = false
        scene.setTime(hour: hour, day: meta["day"] as! Int)
        let ours = render(scene, view: view)
        let tag = String(m.dropFirst(4).dropLast(5))
        let ref = pixels(load(refDir.appendingPathComponent("ref-\(tag).png"))), mineRaw = pixels(ours)
        guard mineRaw.w >= ref.w, mineRaw.h >= ref.h, mineRaw.w - ref.w <= 8, mineRaw.h - ref.h <= 8 else { print("size mismatch \(mineRaw.w)x\(mineRaw.h) vs \(ref.w)x\(ref.h)"); exit(1) }
        let mine = crop(mineRaw, ref.w, ref.h)
        var off24 = 0, off6 = 0, sumAbs = 0
        var diff = [UInt8](repeating: 255, count: ref.w * ref.h * 4)
        var side = [UInt8](repeating: 255, count: ref.w * 2 * ref.h * 4)
        for p in 0..<(ref.w * ref.h) {
            let i = p * 4
            var mx = 0
            for c in 0..<3 { let d = abs(Int(ref.data[i + c]) - Int(mine.data[i + c])); mx = max(mx, d); sumAbs += d }
            if mx > 6 { off6 += 1 }
            if mx > 24 { off24 += 1 }
            for c in 0..<3 { diff[i + c] = mx > 24 ? (c == 0 ? 255 : 0) : ref.data[i + c] >> 2 }
            let y = p / ref.w, x = p % ref.w
            for c in 0..<4 { side[(y * ref.w * 2 + x) * 4 + c] = ref.data[i + c]; side[(y * ref.w * 2 + ref.w + x) * 4 + c] = mine.data[i + c] }
        }
        save(diff, ref.w, ref.h, to: out.appendingPathComponent("\(tag)-diff.png"))
        save(side, ref.w * 2, ref.h, to: out.appendingPathComponent("\(tag)-side.png"))
        let n = Double(ref.w * ref.h), f24 = 100 * Double(off24) / n, f6 = 100 * Double(off6) / n, mae = Double(sumAbs) / (n * 3)
        print(String(format: "%-12@ %3d | %8.4f %8.4f %7.4f", tag as NSString, scene.light.variant, f24, f6, mae))
        if f24 > GATE_FRAME24 || f6 > GATE_FRAME6 { failed = true; print("    ^ over a gate") }
    }
    print(failed ? "EXTRA PROOF: FAILED" : "EXTRA PROOF: all fixtures within the gates")
    exit(failed ? 3 : 0)

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

#endif
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
    print("usage: harness interact <atlas> <ref dir> <fixtures> <out> | proof <atlas> <ref dir> <out dir> | snapdemo <atlas> <n> <hour> <secs> <png> | idle|demo <atlas> <n> <secs>")
    exit(2)
}
