import AppKit
import Foundation

/// Stable identifiers, independent of themes and of the legacy global mark style.
public enum VendorIcon: Equatable, Hashable, Codable, Sendable {
    case auto
    case builtIn(MarkStyle)
    case symbol(String)

    public enum Resolution: Equatable, Sendable {
        case theme
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
            Self.isValidSymbol(name) ? .symbol(name) : (themeMarks ? .theme : .builtIn(style))
        }
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        if let style = MarkStyle(rawValue: value) { self = .builtIn(style) }
        else if value.hasPrefix("sf:"), Self.isValidSymbol(String(value.dropFirst(3))) { self = .symbol(String(value.dropFirst(3))) }
        else { self = .auto }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto: try container.encode("auto")
        case .builtIn(let style): try container.encode(style.rawValue)
        case .symbol(let name): try container.encode("sf:" + name)
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
