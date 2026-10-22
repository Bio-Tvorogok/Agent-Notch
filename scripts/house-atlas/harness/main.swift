import AppKit
import SpriteKit

// Hosts HouseScene like the wallpaper does (a full screen window at desktop level) to measure it and to compare it
// with the page. usage: harness <atlas dir> <idle|demo|demo60|snapshot> <seconds> [snapshot.png]
let args = CommandLine.arguments
let dir = URL(fileURLWithPath: args[1], isDirectory: true), mode = args[2], secs = Double(args[3]) ?? 30
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.screens[0]
let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
w.isOpaque = true; w.backgroundColor = .black; w.ignoresMouseEvents = true
let view = SKView(frame: NSRect(origin: .zero, size: screen.frame.size))
view.ignoresSiblingOrder = true
view.preferredFramesPerSecond = 60
if ProcessInfo.processInfo.environment["SHOW_STATS"] != nil { view.showsFPS = true; view.showsDrawCount = true; view.showsNodeCount = true }
guard let scene = HouseScene.load(from: dir, script: mode == "demo" || mode == "demo60" ? .demo : .idle) else { print("no atlas in \(dir.path)"); exit(1) }
if mode == "demo60" { scene.fixedFps = 60 }
if mode == "snapshot" { scene.freezeClock = true; scene.fixedHour = 12 }
w.contentView = view
view.presentScene(scene)
w.orderFrontRegardless()
Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in print(String(format: "fps %.1f paused %@", scene.deliveredFps, view.isPaused ? "yes" : "no")); fflush(stdout) }
if mode == "snapshot" {
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        guard let img = view.texture(from: scene)?.cgImage() else { print("no snapshot"); exit(1) }
        let rep = NSBitmapImageRep(cgImage: img)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[4]))
        print("snapshot \(img.width)x\(img.height)"); exit(0)
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + secs) { exit(0) }
app.run()
