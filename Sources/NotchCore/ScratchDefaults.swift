import Foundation

/// Throwaway defaults for checks and snapshot renders. A named suite always leaves a plist in
/// ~/Library/Preferences (cfprefsd rewrites it even after removePersistentDomain), so the suite
/// is a plist path inside its own temporary folder and `remove()` deletes that folder.
public final class ScratchDefaults {
    public let defaults: UserDefaults
    private let folder: URL

    public init?(_ label: String) {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentsNotch-\(label)-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
              let defaults = UserDefaults(suiteName: folder.appendingPathComponent("defaults.plist").path)
        else { return nil }
        self.defaults = defaults
    }

    public func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}
