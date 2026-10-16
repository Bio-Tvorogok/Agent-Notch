import AppKit
import Foundation

/// The look of the list, the card and the toast. The wing stays black: it sits on the camera housing.
public enum ThemeID: String, Codable, CaseIterable, Sendable {
    case terminal, glass, paper, midnight, console, phosphor, synthwave, blueprint, brutal, hologram, wasteland, pixel, ducks

    /// The terminal keeps the chosen mark style; every other theme draws its own mark.
    public var hasMark: Bool { self != .terminal }
    public static var withMarks: [ThemeID] { allCases.filter(\.hasMark) }
}

/// Stable identifiers, independent of themes and of the legacy global mark style.
public enum VendorIcon: Equatable, Hashable, Codable, Sendable {
    case auto
    case builtIn(MarkStyle)
    case symbol(String)
    /// One theme's mark, kept in every theme.
    case theme(ThemeID)

    public enum Resolution: Equatable, Sendable {
        /// The current theme's mark.
        case theme
        case themeMark(ThemeID)
        case builtIn(MarkStyle)
        case symbol(String)
    }

    public static func isValidSymbol(_ name: String) -> Bool {
        !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    public func resolve(themeMarks: Bool, style: MarkStyle) -> Resolution {
        switch self {
        case .auto: themeMarks ? .theme : .builtIn(style)
        case .builtIn(let style): .builtIn(style)
        case .symbol(let name):
            Self.isValidSymbol(name) ? .symbol(name) : Self.auto.resolve(themeMarks: themeMarks, style: style)
        case .theme(let id):
            id.hasMark ? .themeMark(id) : Self.auto.resolve(themeMarks: themeMarks, style: style)
        }
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        if let style = MarkStyle(rawValue: value) { self = .builtIn(style) }
        else if value.hasPrefix("sf:"), Self.isValidSymbol(String(value.dropFirst(3))) { self = .symbol(String(value.dropFirst(3))) }
        else if value.hasPrefix("theme:"), let id = ThemeID(rawValue: String(value.dropFirst(6))), id.hasMark { self = .theme(id) }
        else { self = .auto }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto: try container.encode("auto")
        case .builtIn(let style): try container.encode(style.rawValue)
        case .symbol(let name): try container.encode("sf:" + name)
        case .theme(let id): try container.encode("theme:" + id.rawValue)
        }
    }
}

public struct VendorIconPrefs: Codable, Equatable, Sendable {
    public var claude: VendorIcon = .auto
    public var codex: VendorIcon = .auto
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        claude = (try? c.decode(VendorIcon.self, forKey: .claude)) ?? .auto
        codex = (try? c.decode(VendorIcon.self, forKey: .codex)) ?? .auto
    }
    public subscript(_ vendor: Vendor) -> VendorIcon {
        get { vendor == .claude ? claude : codex }
        set { if vendor == .claude { claude = newValue } else { codex = newValue } }
    }
}
