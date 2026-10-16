import Foundation

struct VendorIconChecks {
    func preferences() throws {
        let suite = "AN-icons-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
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
