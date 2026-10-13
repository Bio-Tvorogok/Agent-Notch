import Foundation

/// Resolved paths and repository roots for the list filter. Rendering asks on every frame,
/// so answers are kept for a short while instead of touching the disk each time.
enum PathCache {
    private static let lock = NSLock()
    private static var paths: [String: (String, Date)] = [:]
    private static var repositories: [String: (String, Date)] = [:]
    private static let ttl: TimeInterval = 30

    static func path(_ value: String) -> String {
        cached(value, in: &paths) {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath().path
        }
    }

    /// Match worktrees to their main repository without relying on display names.
    static func repository(_ path: String) -> String {
        cached(path, in: &repositories, resolve: findRepository)
    }

    private static func cached(_ key: String, in store: inout [String: (String, Date)], resolve: (String) -> String) -> String {
        let now = Date()
        lock.lock()
        if let (value, at) = store[key], now.timeIntervalSince(at) < ttl { lock.unlock(); return value }
        lock.unlock()
        let value = resolve(key)
        lock.lock()
        if store.count > 512 { store.removeAll() }
        store[key] = (value, now)
        lock.unlock()
        return value
    }

    private static func findRepository(_ path: String) -> String {
        var dir = URL(fileURLWithPath: path)
        while dir.path != "/" {
            let git = dir.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: git.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue { return Self.path(dir.path) }
                if let text = try? String(contentsOf: git, encoding: .utf8), text.hasPrefix("gitdir:") {
                    let target = String(text.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let gitdir = target.hasPrefix("/") ? target : dir.appendingPathComponent(target).path
                    if let cut = gitdir.range(of: "/.git/") { return Self.path(String(gitdir[..<cut.lowerBound])) }
                }
                return Self.path(dir.path)
            }
            dir.deleteLastPathComponent()
        }
        return path
    }
}
