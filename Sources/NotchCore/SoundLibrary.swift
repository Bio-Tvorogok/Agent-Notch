import Foundation

public struct CustomSound: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let fileName: String

    public init(id: String, name: String, fileName: String) {
        self.id = id
        self.name = name
        self.fileName = fileName
    }
}

public final class SoundLibrary {
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentsNotch/Sounds", isDirectory: true)
    }

    public private(set) var sounds: [CustomSound] = []
    private let directory: URL
    private var loadError: Error?
    private var manifest: URL { directory.appendingPathComponent("manifest.json") }
    private let files = FileManager.default

    private enum StorageError: LocalizedError {
        case invalidManifest, invalidFile, invalidID
        var errorDescription: String? {
            switch self {
            case .invalidManifest: return Loc.t("Could not read the sound library.", "Не удалось прочитать библиотеку звуков.")
            case .invalidFile: return Loc.t("The sound file is missing or unavailable.", "Файл звука отсутствует или недоступен.")
            case .invalidID: return Loc.t("This sound is not in the library.", "Этого звука нет в библиотеке.")
            }
        }
    }

    public init(directory: URL = SoundLibrary.defaultDirectory) {
        let supplied = directory.standardizedFileURL
        self.directory = supplied.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(supplied.lastPathComponent, isDirectory: true)
        do {
            try checkDirectory()
            guard try isRegularFile(manifest) else { throw StorageError.invalidManifest }
            let loaded = try JSONDecoder().decode([CustomSound].self, from: Data(contentsOf: manifest))
            var ids = Set<String>()
            var names = Set<String>()
            for sound in loaded {
                guard Self.valid(sound), ids.insert(sound.id).inserted,
                      names.insert(sound.name).inserted else { throw StorageError.invalidManifest }
            }
            sounds = loaded
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain,
               [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(nsError.code) { return }
            loadError = error
        }
    }

    public static func isCustomID(_ id: String) -> Bool {
        guard id.hasPrefix("custom:") else { return false }
        let suffix = String(id.dropFirst(7))
        guard let uuid = UUID(uuidString: suffix) else { return false }
        return uuid.uuidString.caseInsensitiveCompare(suffix) == .orderedSame
    }

    public func importFile(_ source: URL) throws -> CustomSound {
        if let loadError { throw loadError }
        try checkDirectory()
        guard source.isFileURL, try isRegularFile(source) else { throw StorageError.invalidFile }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let uuid = UUID().uuidString.lowercased()
        let ext = source.pathExtension
        let base = source.deletingPathExtension().lastPathComponent
        var name = base
        var suffix = 2
        while sounds.contains(where: { $0.name == name }) {
            name = "\(base) (\(suffix))"
            suffix += 1
        }
        let sound = CustomSound(id: "custom:\(uuid)", name: name,
                                fileName: uuid + (ext.isEmpty ? "" : ".\(ext)"))
        let destination = directory.appendingPathComponent(sound.fileName)
        try files.copyItem(at: source, to: destination)
        do {
            try persist(sounds + [sound])
        } catch {
            try files.removeItem(at: destination)
            throw error
        }
        sounds.append(sound)
        return sound
    }

    public func url(for id: String) -> URL? {
        guard directory.resolvingSymlinksInPath().path == directory.path,
              Self.isCustomID(id), let sound = sounds.first(where: { $0.id == id }),
              Self.valid(sound) else { return nil }
        let url = directory.appendingPathComponent(sound.fileName)
        guard (try? isRegularFile(url)) == true else { return nil }
        return url
    }

    public func remove(id: String) throws {
        if let loadError { throw loadError }
        try checkDirectory()
        guard Self.isCustomID(id) else { throw StorageError.invalidID }
        guard let index = sounds.firstIndex(where: { $0.id == id }) else { return }
        let source = directory.appendingPathComponent(sounds[index].fileName)
        let exists = files.fileExists(atPath: source.path)
        if exists, try !isRegularFile(source) { throw StorageError.invalidFile }
        let backup = directory.appendingPathComponent(".removed-\(UUID().uuidString)")
        if exists { try files.moveItem(at: source, to: backup) }
        var updated = sounds
        updated.remove(at: index)
        do {
            try persist(updated)
        } catch {
            if exists { try files.moveItem(at: backup, to: source) }
            throw error
        }
        sounds = updated
        if exists { try files.removeItem(at: backup) }
    }

    private func persist(_ entries: [CustomSound]) throws {
        do {
            guard try isRegularFile(manifest) else { throw StorageError.invalidManifest }
        } catch {
            let nsError = error as NSError
            guard nsError.domain == NSCocoaErrorDomain,
                  [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(nsError.code) else { throw error }
        }
        try JSONEncoder().encode(entries).write(to: manifest, options: .atomic)
    }

    private func isRegularFile(_ url: URL) throws -> Bool {
        let attributes = try files.attributesOfItem(atPath: url.path)
        return attributes[.type] as? FileAttributeType == .typeRegular
    }

    private func checkDirectory() throws {
        guard directory.resolvingSymlinksInPath().path == directory.path else { throw StorageError.invalidFile }
    }

    private static func valid(_ sound: CustomSound) -> Bool {
        guard isCustomID(sound.id), !sound.name.isEmpty else { return false }
        let uuid = String(sound.id.dropFirst(7)).lowercased()
        let file = sound.fileName
        guard file == URL(fileURLWithPath: file).lastPathComponent else { return false }
        if file == uuid { return true }
        guard file.hasPrefix(uuid + ".") else { return false }
        let ext = String(file.dropFirst(uuid.count + 1))
        return !ext.isEmpty && !ext.contains("/") && !ext.contains("\\") && !ext.contains("\0")
    }
}
