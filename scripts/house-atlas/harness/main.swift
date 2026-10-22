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
    let view = SKView(frame: NSRect(origin: .zero, size: size))
    view.ignoresSiblingOrder = true
    return (scene, view)
}

switch mode {
case "proof":
    let atlas = URL(fileURLWithPath: args[2], isDirectory: true), refDir = URL(fileURLWithPath: args[3], isDirectory: true), out = URL(fileURLWithPath: args[4], isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let metas = try FileManager.default.contentsOfDirectory(atPath: refDir.path).filter { $0.hasPrefix("ref-") && $0.hasSuffix(".json") }.sorted()
    var failed = false
    print("fixture                         variant  house px   off>24     % house   (whole frame %)")
    for m in metas {
        let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: refDir.appendingPathComponent(m))) as! [String: Any]
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
        let ours = render(scene, view: view)
        let tag = m.dropFirst(4).dropLast(5)
        let ref = pixels(load(refDir.appendingPathComponent("ref-\(tag).png"))), sky = pixels(load(refDir.appendingPathComponent("ref-\(tag)-sky.png"))), mineRaw = pixels(ours)
        guard mineRaw.w >= ref.w, mineRaw.h >= ref.h, mineRaw.w - ref.w <= 8, mineRaw.h - ref.h <= 8 else { print("size mismatch \(mineRaw.w)x\(mineRaw.h) vs \(ref.w)x\(ref.h)"); exit(1) }
        let mine = crop(mineRaw, ref.w, ref.h)
        var house = 0, off = 0, offAll = 0
        var hot: [Int: Int] = [:]
        var diff = [UInt8](repeating: 255, count: ref.w * ref.h * 4)
        var side = [UInt8](repeating: 255, count: ref.w * 2 * ref.h * 4)
        for p in 0..<(ref.w * ref.h) {
            let i = p * 4
            var mx = 0
            for c in 0..<3 { mx = max(mx, abs(Int(ref.data[i + c]) - Int(mine.data[i + c]))) }
            let isHouse = abs(Int(ref.data[i]) - Int(sky.data[i])) + abs(Int(ref.data[i + 1]) - Int(sky.data[i + 1])) + abs(Int(ref.data[i + 2]) - Int(sky.data[i + 2])) > 0
            if isHouse { house += 1 }
            if mx > 24 { offAll += 1; if isHouse { off += 1; hot[(p / ref.w / 48) * 1000 + (p % ref.w) / 48, default: 0] += 1 } }
            for c in 0..<3 { diff[i + c] = mx > 24 ? (c == 0 ? 255 : 0) : ref.data[i + c] >> 2 }
            let y = p / ref.w, x = p % ref.w
            for c in 0..<4 { side[(y * ref.w * 2 + x) * 4 + c] = ref.data[i + c]; side[(y * ref.w * 2 + ref.w + x) * 4 + c] = mine.data[i + c] }
        }
        save(diff, ref.w, ref.h, to: out.appendingPathComponent("\(tag)-diff.png"))
        save(side, ref.w * 2, ref.h, to: out.appendingPathComponent("\(tag)-side.png"))
        save(mine.data, mine.w, mine.h, to: out.appendingPathComponent("\(tag)-scene.png"))
        let pct = 100 * Double(off) / Double(max(1, house))
        print(String(format: "%-32@ %3d %10d %9d %11.4f   (%.4f)", "n=\(n) h=\(String(format: "%.2f", hour))" as NSString, scene.light.variant, house, off, pct, 100 * Double(offAll) / Double(ref.w * ref.h)))
        if ProcessInfo.processInfo.environment["HOT"] != nil { for (k, v) in hot.sorted(by: { $0.value > $1.value }).prefix(8) { print("    cell x\((k % 1000) * 48) y\((k / 1000) * 48): \(v)") } }
        if pct > 0.1 { failed = true }
    }
    print(failed ? "PROOF: above the 0.1% target" : "PROOF: all fixtures within 0.1%")
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
