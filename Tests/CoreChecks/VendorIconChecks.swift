import Foundation

struct VendorIconChecks {
    func preferences() throws {
        let scratch = try XCTUnwrap(ScratchDefaults("icon-checks"))
        let defaults = scratch.defaults
        defer { scratch.remove() }
        XCTAssertEqual(SettingsStorage.read(VendorIconPrefs.self, key: "vendorIcons", default: VendorIconPrefs(), in: defaults), VendorIconPrefs())
        var prefs = VendorIconPrefs()
        prefs[.codex] = .symbol("bolt.fill")
        prefs[.claude] = .builtIn(.letters)
        SettingsStorage.write(prefs, key: "vendorIcons", in: defaults)
        XCTAssertEqual(SettingsStorage.read(VendorIconPrefs.self, key: "vendorIcons", default: VendorIconPrefs(), in: defaults), prefs)
        XCTAssertEqual(try JSONDecoder().decode(VendorIconPrefs.self, from: Data("{}".utf8)), VendorIconPrefs())
        for name in ["", "not.a.real.symbol", "bolt.fill"] {
            let icon = VendorIcon.symbol(name)
            let decoded = try JSONDecoder().decode(VendorIcon.self, from: JSONEncoder().encode(icon))
            XCTAssertEqual(decoded, name == "bolt.fill" ? icon : .auto)
        }
        XCTAssertEqual(try JSONDecoder().decode(VendorIcon.self, from: Data("\"future-option\"".utf8)), .auto)
    }

    /// `theme:<id>` keeps one theme's mark in every theme; unknown ids and the markless terminal fall back to auto.
    func themeChoice() throws {
        func decode(_ raw: String) throws -> VendorIcon { try JSONDecoder().decode(VendorIcon.self, from: Data("\"\(raw)\"".utf8)) }
        for id in ThemeID.allCases {
            let icon = VendorIcon.theme(id)
            let encoded = String(decoding: try JSONEncoder().encode(icon), as: UTF8.self)
            XCTAssertEqual(encoded, "\"theme:\(id.rawValue)\"")
            XCTAssertEqual(try decode("theme:" + id.rawValue), id.hasMark ? icon : .auto)
        }
        XCTAssertEqual(ThemeID.withMarks, ThemeID.allCases.filter { $0 != .terminal })
        for raw in ["theme:", "theme:nope", "theme:Paper", "THEME:paper"] { XCTAssertEqual(try decode(raw), .auto) }
        // Older saved values keep decoding.
        XCTAssertEqual(try decode("auto"), .auto)
        XCTAssertEqual(try decode("letters"), .builtIn(.letters))
        XCTAssertEqual(try decode("sf:bolt.fill"), .symbol("bolt.fill"))
        var prefs = VendorIconPrefs()
        prefs[.claude] = .theme(.ducks)
        XCTAssertEqual(try JSONDecoder().decode(VendorIconPrefs.self, from: JSONEncoder().encode(prefs)), prefs)
        for themed in [false, true] {
            for style in MarkStyle.allCases {
                for id in ThemeID.withMarks {
                    XCTAssertEqual(VendorIcon.theme(id).resolve(themeMarks: themed, style: style), .themeMark(id))
                }
                let fallback: VendorIcon.Resolution = themed ? .theme : .builtIn(style)
                XCTAssertEqual(VendorIcon.theme(.terminal).resolve(themeMarks: themed, style: style), fallback)
            }
        }
    }

    func resolution() {
        // Kept in sync with ThemeID; all non-terminal themes currently replace marks.
        let themes = ["terminal", "glass", "paper", "midnight", "console", "phosphor", "synthwave", "blueprint", "brutal", "hologram", "wasteland", "pixel", "ducks"]
        for theme in themes {
            for enabled in [false, true] {
                for style in MarkStyle.allCases {
                    let themed = enabled && theme != "terminal"
                    let legacy: VendorIcon.Resolution = themed ? .theme : .builtIn(style)
                    XCTAssertEqual(VendorIcon.auto.resolve(themeMarks: themed, style: style), legacy)
                    XCTAssertEqual(VendorIcon.symbol("invalid.symbol").resolve(themeMarks: themed, style: style), legacy)
                    XCTAssertEqual(VendorIcon.symbol("bolt.fill").resolve(themeMarks: themed, style: style), .symbol("bolt.fill"))
                    for chosen in MarkStyle.allCases {
                        XCTAssertEqual(VendorIcon.builtIn(chosen).resolve(themeMarks: themed, style: style), .builtIn(chosen))
                    }
                }
            }
        }
    }
}
