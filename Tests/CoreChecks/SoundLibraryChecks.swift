import Foundation

struct SoundLibraryChecks {
    private func fixture(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root, root.appendingPathComponent("library"))
    }
    func rejectsStartupDirectoryAndReplacedManifestLinks() throws {
        try fixture { root, directory in
            let outside = root.appendingPathComponent("outside")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: outside)
            let source = root.appendingPathComponent("Bell.wav")
            try Data([1, 2]).write(to: source)
            let library = SoundLibrary(directory: directory)
            do { _ = try library.importFile(source); XCTFail("initial linked library directory must not import outside") } catch {}
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
        }
        try fixture { root, directory in
            let source = root.appendingPathComponent("Bell.wav")
            try Data([3, 4]).write(to: source)
            let library = SoundLibrary(directory: directory)
            let original = try library.importFile(source)
            let manifest = directory.appendingPathComponent("manifest.json")
            try FileManager.default.removeItem(at: manifest)
            let outside = root.appendingPathComponent("must-not-be-created.json")
            try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: outside)
            do { _ = try library.importFile(source); XCTFail("replaced dangling manifest must not write outside") } catch {}
            XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
            XCTAssertEqual(library.sounds, [original])
            XCTAssertEqual(try Data(contentsOf: source), Data([3, 4]))
            XCTAssertEqual(try? FileManager.default.destinationOfSymbolicLink(atPath: manifest.path), Optional(outside.path))
        }
    }
    func persistsOwnedCopy() throws {
        try fixture { root, directory in
            let source = root.appendingPathComponent("Bell.aiff")
            try Data([1, 2, 3]).write(to: source)
            let library = SoundLibrary(directory: directory)
            let sound = try library.importFile(source)
            XCTAssertEqual(sound.name, "Bell")
            XCTAssertTrue(SoundLibrary.isCustomID(sound.id))
            XCTAssertFalse(SoundLibrary.isCustomID(source.path))
            XCTAssertFalse(SoundLibrary.isCustomID("custom:../../Bell.aiff"))
            try FileManager.default.removeItem(at: source)
            let restored = SoundLibrary(directory: directory)
            XCTAssertEqual(restored.sounds, [sound])
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(restored.url(for: sound.id))), Data([1, 2, 3]))
            XCTAssertNil(restored.url(for: source.path))
            XCTAssertNil(restored.url(for: "custom:../../Bell.aiff"))
        }
    }
    func duplicateNamesAndRemoval() throws {
        try fixture { root, directory in
            let source = root.appendingPathComponent("Bell.wav")
            try Data([4, 5]).write(to: source)
            let library = SoundLibrary(directory: directory)
            let first = try library.importFile(source)
            let second = try library.importFile(source)
            XCTAssertEqual(first.name, "Bell")
            XCTAssertEqual(second.name, "Bell (2)")
            XCTAssertFalse(first.fileName == second.fileName)
            try library.remove(id: first.id)
            XCTAssertEqual(library.sounds, [second])
            XCTAssertNil(library.url(for: first.id))
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(first.fileName).path))
            XCTAssertEqual(try Data(contentsOf: source), Data([4, 5]))
            XCTAssertEqual(SoundLibrary(directory: directory).sounds, [second])
        }
    }
    func rejectsBadManifestAndPaths() throws {
        try fixture { root, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let source = root.appendingPathComponent("Bell.wav")
            try Data([7]).write(to: source)
            let manifest = directory.appendingPathComponent("manifest.json")
            for contents in [Data("bad json".utf8), Data("[{\"id\":\"custom:00000000-0000-0000-0000-000000000000\",\"name\":\"Outside\",\"fileName\":\"../Bell.wav\"}]".utf8)] {
                try contents.write(to: manifest)
                let library = SoundLibrary(directory: directory)
                XCTAssertEqual(library.sounds, [])
                do { _ = try library.importFile(source); XCTFail("import must reject invalid manifest") } catch {}
                XCTAssertEqual(try Data(contentsOf: manifest), contents)
                XCTAssertEqual(try Data(contentsOf: source), Data([7]))
            }
        }
    }
    func rollsBackPersistenceFailure() throws {
        try fixture { root, directory in
            let source = root.appendingPathComponent("Bell.wav")
            try Data([8, 9]).write(to: source)
            let library = SoundLibrary(directory: directory)
            let sound = try library.importFile(source)
            let manifest = directory.appendingPathComponent("manifest.json")
            try FileManager.default.removeItem(at: manifest)
            try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
            let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            do { _ = try library.importFile(source); XCTFail("import must fail when manifest cannot be written") } catch {}
            XCTAssertEqual(library.sounds, [sound])
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), before)
            do { try library.remove(id: sound.id); XCTFail("remove must fail when manifest cannot be written") } catch {}
            XCTAssertEqual(library.sounds, [sound])
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(library.url(for: sound.id))), Data([8, 9]))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), before)
        }
    }
    func rejectsSymlinkAndNonFile() throws {
        try fixture { root, directory in
            let source = root.appendingPathComponent("Bell.wav")
            try Data([10]).write(to: source)
            let library = SoundLibrary(directory: directory)
            do { _ = try library.importFile(root); XCTFail("directory import must fail") } catch {}
            let link = root.appendingPathComponent("link.wav")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
            do { _ = try library.importFile(link); XCTFail("symlink import must fail") } catch {}
            let sound = try library.importFile(source)
            let managed = directory.appendingPathComponent(sound.fileName)
            try FileManager.default.removeItem(at: managed)
            try FileManager.default.createSymbolicLink(at: managed, withDestinationURL: source)
            XCTAssertNil(library.url(for: sound.id))
            do { try library.remove(id: sound.id); XCTFail("symlink removal must fail") } catch {}
            XCTAssertEqual(try Data(contentsOf: source), Data([10]))
        }
    }
    func rejectsDanglingManifestAndReplacedDirectory() throws {
        try fixture { root, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let manifest = directory.appendingPathComponent("manifest.json")
            try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: root.appendingPathComponent("missing.json"))
            let source = root.appendingPathComponent("Bell.wav")
            try Data([11]).write(to: source)
            let broken = SoundLibrary(directory: directory)
            do { _ = try broken.importFile(source); XCTFail("dangling manifest must block import") } catch {}
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: manifest.path), root.appendingPathComponent("missing.json").path)
            try FileManager.default.removeItem(at: manifest)
            let library = SoundLibrary(directory: directory)
            let sound = try library.importFile(source)
            let moved = root.appendingPathComponent("moved")
            try FileManager.default.moveItem(at: directory, to: moved)
            try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: moved)
            XCTAssertNil(library.url(for: sound.id))
            do { _ = try library.importFile(source); XCTFail("replaced directory must block import") } catch {}
            do { try library.remove(id: sound.id); XCTFail("replaced directory must block remove") } catch {}
            XCTAssertEqual(SoundLibrary(directory: moved).sounds, [sound])
        }
    }

}
