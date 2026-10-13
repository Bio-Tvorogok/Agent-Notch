import AppKit
import NotchCore

/// Logos are read from the installed apps once, shrunk once, and kept for the life of the process.
@MainActor
enum AppIconCache {
    private static var images: [String: NSImage] = [:]
    private static var missing: Set<String> = []
    private static let pixels = 128

    static func image(_ vendor: Vendor, dark: Bool) -> NSImage? {
        let key = "\(vendor.rawValue)-\(dark)"
        if let image = images[key] { return image }
        if missing.contains(key) { return nil }
        let source = AppIcon.source(for: vendor, dark: dark) { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        let full: NSImage? = switch source {
        case .bundle(let url): NSWorkspace.shared.icon(forFile: url.path)
        case .file(let url): NSImage(contentsOf: url)
        case nil: nil
        }
        guard let full, let small = shrink(full) else { missing.insert(key); return nil }
        images[key] = small
        return small
    }

    private static func shrink(_ image: NSImage) -> NSImage? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let small = NSImage(size: NSSize(width: pixels / 2, height: pixels / 2))
        small.addRepresentation(rep)
        return small
    }
}
