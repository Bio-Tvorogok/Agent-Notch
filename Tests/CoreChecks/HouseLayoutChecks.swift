import Foundation
import CoreFoundation
#if canImport(NotchCore)
import NotchCore
#endif

struct HouseLayoutChecks {
    // The caller (scripts/test.sh) runs from the repo root. Never fall back to
    // skipping fixtures: a missing directory or a missing case fails the check.
    func goldenFixtures() throws {
        let js = Process()
        js.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        js.arguments = ["node", "Tests/HouseChecks/layout-fixtures.mjs", "--check"]
        try js.run(); js.waitUntilExit()
        XCTAssertEqual(js.terminationStatus, 0, "current JS must match the committed golden fixtures")
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/Fixtures/house-layout")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(files.count, 84)
        for file in files {
            let data = try Data(contentsOf: file)
            let fixture = try JSONDecoder().decode(Fixture.self, from: data)
            let input = fixture.input
            let actual = HouseLayout.make(projects: input.projects, layout: input.layout, canvas: input.canvas, insets: input.insets)
            let expected = try XCTUnwrap((JSONSerialization.jsonObject(with: data) as? [String: Any])?["output"])
            try compare(expected, JSONSerialization.jsonObject(with: JSONEncoder().encode(actual)), at: file.lastPathComponent)
        }
        print("houseLayoutGoldenFixtures: compared \(files.count) JS fixtures (tolerance 1e-6)")
    }

    /// JS strings are sequences of UTF-16 units; Swift String equality also
    /// considers canonically equivalent spellings equal. Keep distinct JS keys.
    func projectIdentity() {
        let names = ["😀", "Проект", "é", "e\u{301}", "😀", ""]
        let result = HouseLayout.make(projects: names, canvas: .init(width: 1440, height: 900))
        let projects = Array(result.rooms.dropFirst(3))
        let expected = ["p:😀", "p:Проект", "p:é", "p:e\u{301}", "p:—"]
        XCTAssertEqual(projects.map { Array($0.key.utf16) }, expected.map { Array($0.utf16) })
        // Expected themes independently evaluated through projectTheme in scene.mjs.
        XCTAssertEqual(projects.map(\.theme), ["greenhouse", "library", "library", "bedroom", "arcade"])
        let choices = HouseLayout.make(projects: ["e\u{301}"], canvas: .init(width: 1440, height: 900), themes: ["é": "server"])
        XCTAssertEqual(choices.rooms.last?.theme, "bedroom", "theme choices use JS exact string identity")
        let both = HouseLayout.make(projects: ["é", "e\u{301}"], canvas: .init(width: 1440, height: 900),
                                    themes: [.init(project: "é", theme: "server"), .init(project: "e\u{301}", theme: "arcade")])
        XCTAssertEqual(both.rooms.suffix(2).map(\.theme), ["server", "arcade"])
        let invalid = HouseLayout.make(projects: ["😀", "Проект"], canvas: .init(width: 1440, height: 900),
                                       themes: ["😀": "bath", "Проект": "unknown"])
        XCTAssertEqual(invalid.rooms.suffix(2).map(\.theme), ["greenhouse", "library"])
    }

    private struct Fixture: Decodable {
        let input: Input
        struct Input: Decodable {
            let projects: [String]
            let layout: HouseLayout.Style
            let canvas: HouseLayout.Canvas
            let insets: HouseLayout.Insets
        }
    }

    private func compare(_ expected: Any, _ actual: Any, at path: String) throws {
        if let a = expected as? [String: Any], let b = actual as? [String: Any] {
            XCTAssertEqual(Set(a.keys), Set(b.keys), path)
            for key in a.keys.sorted() { if let value = b[key] { try compare(a[key]!, value, at: path + "." + key) } }
        } else if let a = expected as? [Any], let b = actual as? [Any] {
            XCTAssertEqual(a.count, b.count, path)
            for i in 0..<min(a.count, b.count) { try compare(a[i], b[i], at: "\(path)[\(i)]") }
        } else if let a = expected as? NSNumber, let b = actual as? NSNumber {
            let ab = CFGetTypeID(a) == CFBooleanGetTypeID(), bb = CFGetTypeID(b) == CFBooleanGetTypeID()
            XCTAssertEqual(ab, bb, path + " boolean/number type")
            if ab { XCTAssertEqual(a, b, path) }
            else { XCTAssertTrue(a.doubleValue.isFinite && b.doubleValue.isFinite && abs(a.doubleValue - b.doubleValue) <= 1e-6,
                                 "\(path): \(a) != \(b)") }
        } else if expected is NSNull, actual is NSNull {
            return
        } else if let a = expected as? String, let b = actual as? String {
            XCTAssertEqual(Array(a.utf16), Array(b.utf16), path)
        } else {
            XCTFail("\(path): expected \(expected), got \(actual)")
        }
    }
}
