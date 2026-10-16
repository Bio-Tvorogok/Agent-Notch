import AppKit
import SwiftUI
import NotchCore

/// App icons and original vendor glyphs share the same status colour and pulse.
struct StatusMark: View {
    let vendor: Vendor
    let state: AgentState
    let isLight: Bool
    var style: MarkStyle = .dots
    var size: CGFloat = 6
    var symbol: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if state == .working {
                SurfaceTimeline(every: 0.25) { date in
                    drawing.opacity(0.86 + 0.14 * sin(date.timeIntervalSinceReferenceDate * 2))
                }
            } else if state == .waiting {
                SurfaceTimeline(every: 0.5) { date in
                    drawing.opacity(Int(date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0.4)
                }
            } else { drawing }
        }
        .frame(width: size, height: size)
        .accessibilityLabel((vendor == .claude ? SettingsText.claude : SettingsText.codex) + ", " + stateLabel)
    }

    private var stateLabel: String {
        switch state {
        case .working: SettingsText.name("working")
        case .waiting: SettingsText.name("waiting")
        case .error: SettingsText.name("error")
        case .done: SettingsText.name("done")
        }
    }
    private var tint: Color {
        guard style == .logos, state == .working else { return state.color }
        return vendor == .claude ? Color(red: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0) :
            (scheme == .dark ? Color(white: 0.93) : Color(white: 0.15))
    }
    private var appIcon: NSImage? { AppIconCache.image(vendor, dark: scheme == .dark) }
    private var line: CGFloat { max(0.8, size * 0.10) }

    private var drawing: some View {
        ZStack(alignment: .bottomTrailing) {
            if let symbol {
                Image(systemName: symbol)
                    .resizable().scaledToFit()
                    .fontWeight(isLight ? .regular : .semibold)
                    .foregroundStyle(state.color).opacity(isLight ? 0.55 : 1)
            } else {
                switch style {
                case .dots:
                    if vendor == .claude { mark(Circle()) }
                    else { mark(RoundedRectangle(cornerRadius: size * 0.22)) }
                case .logos:
                    if let icon = appIcon { Image(nsImage: icon).resizable().interpolation(.high).opacity(isLight ? 0.55 : 1) }
                    else { vendorLogo }
                case .logosMono: vendorLogo
                case .letters:
                    mark(Circle())
                    Text(vendor == .claude ? "C" : "X")
                        .font(.system(size: size * 0.62, weight: .bold, design: .rounded))
                        .foregroundStyle(isLight ? tint : Color.black)
                        .frame(width: size, height: size)
                }
            }
            if symbol == nil && style == .logos {
                let dot = max(3, size * 0.36)
                Circle().fill(state.color)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.85), lineWidth: max(0.8, dot * 0.22)))
                    .frame(width: dot, height: dot).offset(x: dot * 0.18, y: dot * 0.18)
            }
        }
    }

    private var vendorLogo: some View {
        VendorLogo(vendor: vendor).fill(tint).opacity(isLight ? 0.55 : 1)
    }

    @ViewBuilder private func mark<S: Shape>(_ shape: S) -> some View {
        if isLight { shape.stroke(tint, lineWidth: line).padding(line / 2) }
        else { shape.fill(tint) }
    }
}

/// Every agent surface reads the same style and size from its injected settings.
struct AgentStatusMark: View {
    let agent: Agent
    var small = false
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ResolvedVendorMark(vendor: agent.vendor, state: agent.state, isLight: agent.isLight,
                           size: small ? settings.wingDisplay.childSize : settings.appearance.markSize.points)
    }
}

/// One resolution path for wings, rows, cards, toasts and summary counts.
struct ResolvedVendorMark: View {
    let vendor: Vendor
    let state: AgentState
    let isLight: Bool
    let size: CGFloat
    var onDark = false
    /// A candidate the settings picker draws instead of the saved choice.
    var icon: VendorIcon? = nil
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.theme) private var theme

    var body: some View {
        switch (icon ?? settings.vendorIcons[vendor]).resolve(themeMarks: settings.usesThemeMarks, style: settings.appearance.markStyle) {
        case .theme:
            ThemeMark(theme: onDark ? settings.currentTheme : theme, vendor: vendor, state: state,
                      isLight: isLight, size: size, onDark: onDark)
        case .themeMark(let id):
            // A mark borrowed from a light theme takes the terminal's state colours on a dark surface.
            ThemeMark(theme: .of(id), vendor: vendor, state: state, isLight: isLight, size: size,
                      onDark: onDark || (onDark ? settings.currentTheme : theme).scheme == .dark)
        case .builtIn(let style):
            StatusMark(vendor: vendor, state: state, isLight: isLight, style: style, size: size)
        case .symbol(let name):
            StatusMark(vendor: vendor, state: state, isLight: isLight, size: size, symbol: name)
        }
    }
}
