import Foundation

/// Colour app icons come from the apps installed on this Mac.
public enum AppIcon {
    public enum Source: Equatable, Sendable {
        /// The app's own icon, as Finder shows it.
        case bundle(URL)
        /// A picture inside the app bundle.
        case file(URL)
    }

    public static func bundleID(_ vendor: Vendor) -> String {
        vendor == .claude ? "com.anthropic.claudefordesktop" : "com.openai.codex"
    }

    /// Use the OpenAI knot shown in the reference Dock, in either appearance.
    public static func resource(_ vendor: Vendor, dark: Bool) -> String? {
        vendor == .claude ? nil : "icon-chatgpt.png"
    }

    /// nil when the app or its picture is missing: the caller draws the original vendor glyph.
    public static func source(for vendor: Vendor, dark: Bool, locate: (String) -> URL?,
                              exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Source? {
        guard let app = locate(bundleID(vendor)), exists(app.path) else { return nil }
        guard let name = resource(vendor, dark: dark) else { return .bundle(app) }
        let file = app.appendingPathComponent("Contents/Resources").appendingPathComponent(name)
        return exists(file.path) ? .file(file) : nil
    }
}
