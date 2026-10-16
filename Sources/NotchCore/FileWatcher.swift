import CoreServices
import Foundation

/// Empty paths refresh only cached process liveness and time-dependent states.
public struct FileChanges: Sendable, Equatable {
    let changedPaths: Set<String>?
    let refreshProcesses: Bool
    public static let full = FileChanges(changedPaths: nil, refreshProcesses: true)
    public static let processes = FileChanges(changedPaths: [], refreshProcesses: true)
    public static func paths(_ paths: Set<String>) -> FileChanges {
        FileChanges(changedPaths: paths, refreshProcesses: false)
    }

    public func merging(_ other: FileChanges) -> FileChanges {
        guard let a = changedPaths, let b = other.changedPaths else { return .full }
        return FileChanges(changedPaths: a.union(b), refreshProcesses: refreshProcesses || other.refreshProcesses)
    }

    static func events(paths: [String], flags: [UInt32]) -> FileChanges {
        let dropped = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped |
            kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged |
            kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)
        if flags.contains(where: { $0 & dropped != 0 }) { return .full }
        return .paths(Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }))
    }
}

/// Owns one serial file-level stream. Delivery is coalesced for at most one extra 0.1s window.
public final class FileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "agents-notch.events", qos: .utility)
    private let queueKey = DispatchSpecificKey<Bool>()
    private let receive: @Sendable (FileChanges) -> Void
    private let interests: Set<String>
    public var isWatching: Bool { stream != nil }
    private var pending: FileChanges?
    private var scheduled = false

    public init(paths: [String], receive: @escaping @Sendable (FileChanges) -> Void) {
        self.receive = receive
        interests = Set(paths.flatMap { path -> [String] in
            let url = URL(fileURLWithPath: path)
            return [ConfigRoots.physical(url).path,
                    ConfigRoots.physical(url.deletingLastPathComponent()).appendingPathComponent(url.lastPathComponent).path]
        })
        queue.setSpecific(key: queueKey, value: true)
        // Watching an existing ancestor also catches a missing/recreated config root.
        let roots = Self.roots(for: paths)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, rawPaths, flags, _ in
            guard let info else { return }
            let owner = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(rawPaths, to: NSArray.self) as! [String]
            owner.enqueue(.events(paths: Array(paths.prefix(count)), flags: Array(UnsafeBufferPointer(start: flags, count: count))))
        }
        stream = FSEventStreamCreate(nil, callback, &context, Array(roots) as CFArray,
                                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                    UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            if !FSEventStreamStart(stream) {
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
                receive(.full)
            }
        } else { receive(.full) }
    }

    public static func roots(for paths: [String]) -> [String] {
        var roots: Set<String> = []
        for path in paths {
            let logical = URL(fileURLWithPath: path)
            var url = ConfigRoots.physical(logical)
            let entry = ConfigRoots.physical(logical.deletingLastPathComponent()).appendingPathComponent(logical.lastPathComponent)
            if entry.path != url.path { roots.insert(entry.deletingLastPathComponent().path) }
            while !FileManager.default.fileExists(atPath: url.path), url.path != "/" { url.deleteLastPathComponent() }
            roots.insert(url.path)
        }
        return roots.filter { root in !roots.contains { other in other != root && root.hasPrefix(other + "/") } }.sorted()
    }

    private func enqueue(_ input: FileChanges) {
        var changes = input
        if let paths = input.changedPaths {
            let relevant = paths.filter { path in
                interests.contains { root in path == root || path.hasPrefix(root + "/") || root.hasPrefix(path + "/") }
            }
            guard !relevant.isEmpty else { return }
            changes = .paths(relevant)
        }
        pending = pending.map { $0.merging(changes) } ?? changes
        guard !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            let changes = self.pending
            self.pending = nil
            self.scheduled = false
            if let changes { self.receive(changes) }
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            // Drain callbacks before releasing their unretained context.
            if DispatchQueue.getSpecific(key: queueKey) == nil { queue.sync {} }
            FSEventStreamRelease(stream)
        }
    }
}
