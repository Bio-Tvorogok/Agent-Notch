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
        return .paths(Set(paths))
    }
}

/// File streams cover log trees; directory streams notice missing roots and symlink replacements.
public final class FileWatcher: @unchecked Sendable {
    private var streams: [FSEventStreamRef] = []
    private let queue = DispatchQueue(label: "agents-notch.events", qos: .utility)
    private let queueKey = DispatchSpecificKey<Bool>()
    private let receive: @Sendable (FileChanges) -> Void
    private let interests: Set<String>
    private let shallowInterests: Set<String>
    public private(set) var isWatching = false
    private var pending: FileChanges?
    private var scheduled = false

    public init(paths: [String], shallowPaths: [String] = [], receive: @escaping @Sendable (FileChanges) -> Void) {
        self.receive = receive
        let shallow = Set(shallowPaths)
        interests = Set(paths.filter { !shallow.contains($0) }.map { ConfigRoots.physical(URL(fileURLWithPath: $0)).path })
        shallowInterests = Set(shallowPaths.flatMap { path -> [String] in
            let url = URL(fileURLWithPath: path)
            return [ConfigRoots.physical(url).path,
                    ConfigRoots.physical(url.deletingLastPathComponent()).appendingPathComponent(url.lastPathComponent).path]
        })
        queue.setSpecific(key: queueKey, value: true)
        let plan = Self.plan(for: paths, shallowPaths: shallowPaths)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, rawPaths, flags, _ in
            guard let info else { return }
            let owner = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(rawPaths, to: NSArray.self) as! [String]
            if let changes = owner.eventChanges(paths: Array(paths.prefix(count)), flags: Array(UnsafeBufferPointer(start: flags, count: count))) {
                owner.enqueue(changes)
            }
        }
        var started = true
        for (roots, fileEvents) in [(plan.files, true), (plan.directories, false)] where !roots.isEmpty {
            let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot) |
                (fileEvents ? UInt32(kFSEventStreamCreateFlagFileEvents) : 0)
            guard let stream = FSEventStreamCreate(nil, callback, &context, roots as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags) else {
                started = false
                continue
            }
            FSEventStreamSetDispatchQueue(stream, queue)
            if FSEventStreamStart(stream) { streams.append(stream) }
            else {
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                started = false
            }
        }
        isWatching = started && !streams.isEmpty
        if !isWatching { receive(.full) }
    }

    struct WatchPlan {
        var files: [String]
        var directories: [String]
    }

    static func plan(for paths: [String], shallowPaths: [String] = []) -> WatchPlan {
        var files: Set<String> = [], directories: Set<String> = []
        let shallow = Set(shallowPaths)
        func ancestor(_ url: URL) -> URL {
            var url = url
            while !FileManager.default.fileExists(atPath: url.path), url.path != "/" { url.deleteLastPathComponent() }
            return url
        }
        for path in paths {
            let logical = URL(fileURLWithPath: path)
            let physical = ConfigRoots.physical(logical)
            let entry = ConfigRoots.physical(logical.deletingLastPathComponent()).appendingPathComponent(logical.lastPathComponent)
            if entry.path != physical.path { directories.insert(ancestor(entry.deletingLastPathComponent()).path) }
            if shallow.contains(path) {
                directories.insert(ancestor(physical).path)
            } else {
                var directory: ObjCBool = false
                if FileManager.default.fileExists(atPath: physical.path, isDirectory: &directory) {
                    files.insert(directory.boolValue ? physical.path : physical.deletingLastPathComponent().path)
                } else if physical.pathExtension == "jsonl",
                          FileManager.default.fileExists(atPath: physical.deletingLastPathComponent().path) {
                    files.insert(physical.deletingLastPathComponent().path)
                } else { directories.insert(ancestor(physical).path) }
            }
        }
        // Never collapse an existing log watch into a missing root's broad ancestor.
        return WatchPlan(files: files.sorted(), directories: directories.sorted())
    }

    public static func roots(for paths: [String], shallowPaths: [String] = []) -> [String] {
        let plan = plan(for: paths, shallowPaths: shallowPaths)
        return plan.files + plan.directories
    }

    func accepts(_ path: String) -> Bool {
        interests.contains { root in path == root || path.hasPrefix(root + "/") || root.hasPrefix(path + "/") } ||
            shallowInterests.contains { root in path == root || root.hasPrefix(path + "/") }
    }

    func eventChanges(paths: [String], flags: [UInt32]) -> FileChanges? {
        let lost = UInt32(kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped |
            kFSEventStreamEventFlagEventIdsWrapped)
        if flags.contains(where: { $0 & lost != 0 }) { return .full }
        let relevant = paths.indices.filter { accepts(paths[$0]) }
        guard !relevant.isEmpty else { return nil }
        return .events(paths: relevant.map { paths[$0] }, flags: relevant.map { flags[$0] })
    }

    private func enqueue(_ input: FileChanges) {
        var changes = input
        if let paths = input.changedPaths {
            let relevant = paths.filter { accepts($0) }
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
        for stream in streams {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
        }
        // Drain callbacks before releasing their unretained context.
        if DispatchQueue.getSpecific(key: queueKey) == nil { queue.sync {} }
        for stream in streams { FSEventStreamRelease(stream) }
    }
}
