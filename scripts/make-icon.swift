// Draws assets/AppIcon.icns: a dark Mac-style tile with the notch and three agent marks beside it.
// Run: swift scripts/make-icon.swift  (needs iconutil, which ships with macOS)
import AppKit

func draw(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let k = size / 1024
    // Apple's icon grid: an 824 pt tile centred in 1024 with a ~185 pt corner radius.
    let tile = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * k, yRadius: 185 * k)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * k
    shadow.shadowOffset = NSSize(width: 0, height: -10 * k)
    shadow.set()
    NSGradient(colors: [NSColor(white: 0.17, alpha: 1), NSColor(white: 0.04, alpha: 1)])!.draw(in: shape, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()
    shape.addClip()

    // Soft glow under the notch.
    let glow = NSGradient(colors: [NSColor(calibratedRed: 1, green: 0.62, blue: 0.25, alpha: 0.28), .clear])!
    glow.draw(fromCenter: NSPoint(x: 512 * k, y: 780 * k), radius: 0,
              toCenter: NSPoint(x: 512 * k, y: 780 * k), radius: 420 * k, options: [])

    // The notch hanging from the top edge.
    let notch = NSRect(x: 392 * k, y: 730 * k, width: 240 * k, height: 220 * k)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: notch, xRadius: 44 * k, yRadius: 44 * k).fill()
    NSBezierPath(rect: NSRect(x: 392 * k, y: 800 * k, width: 240 * k, height: 150 * k)).fill()

    // Marks to the left of the notch: a Claude circle (working) and a Codex square (waiting).
    func dot(_ x: CGFloat, _ y: CGFloat, _ c: NSColor) {
        c.setFill(); NSBezierPath(ovalIn: NSRect(x: (x - 22) * k, y: (y - 22) * k, width: 44 * k, height: 44 * k)).fill()
    }
    let y: CGFloat = 800
    NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 190 * k, y: (y - 46) * k, width: 92 * k, height: 92 * k)).fill()
    dot(272, y - 38, NSColor(calibratedRed: 0.2, green: 0.84, blue: 0.4, alpha: 1))
    NSColor(calibratedRed: 0.36, green: 0.45, blue: 0.98, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 296 * k, y: (y - 40) * k, width: 80 * k, height: 80 * k),
                 xRadius: 18 * k, yRadius: 18 * k).fill()
    dot(368, y - 34, NSColor(calibratedRed: 1, green: 0.78, blue: 0.1, alpha: 1))

    // The list panel that drops from the notch.
    NSColor(white: 1, alpha: 0.06).setFill()
    NSBezierPath(roundedRect: NSRect(x: 170 * k, y: 180 * k, width: 684 * k, height: 480 * k),
                 xRadius: 56 * k, yRadius: 56 * k).fill()

    // Wordless caption bars, like rows in the list.
    for (i, w) in [440.0, 340, 390].enumerated() {
        NSColor(white: 1, alpha: i == 0 ? 0.85 : 0.35).setFill()
        NSBezierPath(roundedRect: NSRect(x: 250 * k, y: CGFloat(540 - i * 120) * k, width: CGFloat(w) * k, height: 44 * k),
                     xRadius: 22 * k, yRadius: 22 * k).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let set = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try draw(CGFloat(base * scale)).representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent(name))
    }
}
try draw(1024).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("assets/icon-1024.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", root.appendingPathComponent("assets/AppIcon.icns").path]
try p.run(); p.waitUntilExit()
exit(p.terminationStatus)
