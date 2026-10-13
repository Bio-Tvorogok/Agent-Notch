import AppKit
import SwiftUI
import NotchCore

/// The look of the list, the card and the toast. The wing stays black: it sits on the camera housing.
enum ThemeID: String, Codable, CaseIterable, Sendable {
    case terminal, glass, paper, midnight, console, phosphor, synthwave, blueprint, brutal, hologram
}

/// Colour roles every themed view draws with. `Ink` resolves a role against the theme in the environment.
enum InkRole: CaseIterable {
    case text, strong, secondary, dim, faint, rule, hover, inset, option, optionOn
    case pill, pillText, pillStroke, primary, primaryText, waitingBg, errorBg, waiting, error, working, code, accent
}

struct Theme {
    let id: ThemeID
    let scheme: ColorScheme
    let radius: CGFloat
    let pillRadius: CGFloat
    /// Highlights and attention rows sit inside the panel with this margin; 0 runs them edge to edge.
    let rowInset: CGFloat
    let rowRadius: CGFloat
    let design: Font.Design
    /// Project names: the theme's heading face, optionally small caps in the Linear manner.
    let headingFont: Font
    let headingUppercase: Bool
    let colors: [InkRole: Color]
    /// Light the text gives off: CRT phosphor, neon tubes.
    var glow: Color? = nil
    /// A fill for the primary button richer than one colour.
    var primaryGradient: [Color]? = nil
    /// Buttons cast a hard offset shadow and wear a thick border.
    var hardShadow = false

    func color(_ role: InkRole) -> Color { colors[role] ?? .clear }

    static func of(_ id: ThemeID) -> Theme {
        switch id {
        case .terminal: terminal
        case .glass: glass
        case .paper: paper
        case .midnight: midnight
        case .console: console
        case .phosphor: phosphor
        case .synthwave: synthwave
        case .blueprint: blueprint
        case .brutal: brutal
        case .hologram: hologram
        }
    }
}

extension Theme {
    private static func white(_ w: Double, _ a: Double = 1) -> Color { Color(white: w, opacity: a) }
    private static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color { Color(red: r, green: g, blue: b, opacity: a) }
    private static let amber = rgb(1, 0.69, 0.12)
    private static let red = rgb(1, 0.27, 0.23)
    private static let green = rgb(0.19, 0.82, 0.35)

    /// The original look: flat graphite, amber for what needs you.
    static let terminal = Theme(
        id: .terminal, scheme: .dark, radius: 12, pillRadius: 6, rowInset: 0, rowRadius: 0, design: .default,
        headingFont: .system(size: 11.5, weight: .semibold), headingUppercase: false,
        colors: [
            .text: white(0.92), .strong: .white, .secondary: white(0.68), .dim: white(0.56), .faint: white(0.23),
            .rule: white(0.17), .hover: white(0.15), .inset: white(0.14), .option: white(0.19), .optionOn: white(0.27),
            .pill: white(0.23), .pillText: .white, .pillStroke: .clear, .primary: amber, .primaryText: .black,
            .waitingBg: rgb(0.17, 0.16, 0.1), .errorBg: rgb(0.17, 0.11, 0.11),
            .waiting: amber, .error: red, .working: green, .code: white(0.92), .accent: amber,
        ])

    /// Liquid Glass: the desktop shows through, a lit rim, capsule controls, white primary like system sheets.
    static let glass = Theme(
        id: .glass, scheme: .dark, radius: 24, pillRadius: 100, rowInset: 6, rowRadius: 14, design: .default,
        headingFont: .system(size: 12, weight: .semibold), headingUppercase: false,
        colors: [
            .text: white(1, 0.95), .strong: .white, .secondary: white(1, 0.74), .dim: white(1, 0.56), .faint: white(1, 0.2),
            .rule: white(1, 0.1), .hover: white(1, 0.09), .inset: white(1, 0.08), .option: white(1, 0.09), .optionOn: white(1, 0.2),
            .pill: white(1, 0.14), .pillText: .white, .pillStroke: white(1, 0.16), .primary: white(1, 0.94), .primaryText: .black,
            .waitingBg: rgb(1, 0.72, 0.2, 0.16), .errorBg: rgb(1, 0.3, 0.26, 0.17),
            .waiting: rgb(1, 0.78, 0.3), .error: rgb(1, 0.45, 0.4), .working: rgb(0.36, 0.9, 0.5), .code: .white, .accent: rgb(1, 0.78, 0.3),
        ])

    /// Warm paper and ink: a light editorial page with New York headings, ink-black primary.
    static let paper = Theme(
        id: .paper, scheme: .light, radius: 14, pillRadius: 7, rowInset: 0, rowRadius: 0, design: .default,
        headingFont: .system(size: 13.5, weight: .semibold, design: .serif), headingUppercase: false,
        colors: [
            .text: rgb(0.13, 0.12, 0.11), .strong: rgb(0.08, 0.07, 0.06), .secondary: rgb(0.33, 0.31, 0.29),
            .dim: rgb(0.5, 0.47, 0.43), .faint: rgb(0.13, 0.1, 0.05, 0.16), .rule: rgb(0.13, 0.1, 0.05, 0.1),
            .hover: rgb(0.13, 0.1, 0.05, 0.05), .inset: rgb(0.13, 0.1, 0.05, 0.045), .option: rgb(0.13, 0.1, 0.05, 0.05),
            .optionOn: rgb(0.13, 0.1, 0.05, 0.11), .pill: rgb(0.13, 0.1, 0.05, 0.07), .pillText: rgb(0.13, 0.12, 0.11),
            .pillStroke: .clear, .primary: rgb(0.13, 0.12, 0.11), .primaryText: rgb(0.98, 0.97, 0.94),
            .waitingBg: rgb(0.99, 0.93, 0.79), .errorBg: rgb(0.99, 0.89, 0.86),
            .waiting: rgb(0.72, 0.43, 0), .error: rgb(0.8, 0.18, 0.13), .working: rgb(0.1, 0.55, 0.24),
            .code: rgb(0.13, 0.12, 0.11), .accent: rgb(0.72, 0.43, 0),
        ])

    /// Deep indigo night with a soft glow at the top, small-caps sections, violet primary.
    static let midnight = Theme(
        id: .midnight, scheme: .dark, radius: 14, pillRadius: 7, rowInset: 6, rowRadius: 8, design: .default,
        headingFont: .system(size: 10, weight: .semibold), headingUppercase: true,
        colors: [
            .text: rgb(0.92, 0.93, 0.98), .strong: .white, .secondary: rgb(0.66, 0.68, 0.79), .dim: rgb(0.5, 0.52, 0.64),
            .faint: rgb(0.62, 0.66, 1, 0.16), .rule: rgb(0.62, 0.66, 1, 0.09), .hover: rgb(0.62, 0.66, 1, 0.07),
            .inset: rgb(0.62, 0.66, 1, 0.06), .option: rgb(0.62, 0.66, 1, 0.07), .optionOn: rgb(0.5, 0.46, 1, 0.3),
            .pill: rgb(0.62, 0.66, 1, 0.1), .pillText: rgb(0.88, 0.9, 1), .pillStroke: rgb(0.62, 0.66, 1, 0.12),
            .primary: rgb(0.43, 0.38, 0.98), .primaryText: .white,
            .waitingBg: rgb(1, 0.72, 0.2, 0.08), .errorBg: rgb(1, 0.3, 0.3, 0.09),
            .waiting: rgb(1, 0.76, 0.3), .error: rgb(1, 0.42, 0.42), .working: rgb(0.32, 0.88, 0.62),
            .code: rgb(0.8, 0.82, 1), .accent: rgb(0.6, 0.55, 1),
        ])

    /// Industrial console: brushed light grey, mono labels in caps, signal orange for what needs you.
    static let console = Theme(
        id: .console, scheme: .light, radius: 8, pillRadius: 3, rowInset: 0, rowRadius: 0, design: .default,
        headingFont: .system(size: 10, weight: .bold, design: .monospaced), headingUppercase: true,
        colors: [
            .text: white(0.07), .strong: .black, .secondary: white(0.28), .dim: white(0.44), .faint: white(0, 0.22),
            .rule: white(0, 0.14), .hover: white(0, 0.05), .inset: white(1, 0.6), .option: white(1, 0.7), .optionOn: rgb(1, 0.38, 0.05, 0.18),
            .pill: white(0.97), .pillText: white(0.07), .pillStroke: white(0, 0.28), .primary: rgb(1, 0.36, 0), .primaryText: .black,
            .waitingBg: rgb(1, 0.36, 0, 0.12), .errorBg: rgb(0.9, 0.1, 0.1, 0.1),
            .waiting: rgb(0.88, 0.3, 0), .error: rgb(0.82, 0.08, 0.08), .working: rgb(0.05, 0.55, 0.3),
            .code: white(0.07), .accent: rgb(1, 0.36, 0),
        ])
}

extension Theme {
    private static func amb(_ a: Double) -> Color { Color(red: 1, green: 0.7, blue: 0.22, opacity: a) }

    /// An amber CRT: everything glows, scan lines run across, the glass curves dark at the edges.
    static let phosphor = Theme(
        id: .phosphor, scheme: .dark, radius: 10, pillRadius: 2, rowInset: 0, rowRadius: 0, design: .monospaced,
        headingFont: .system(size: 11, weight: .bold, design: .monospaced), headingUppercase: true,
        colors: [
            .text: amb(0.95), .strong: Color(red: 1, green: 0.84, blue: 0.45), .secondary: amb(0.75), .dim: amb(0.5), .faint: amb(0.25),
            .rule: amb(0.2), .hover: amb(0.09), .inset: amb(0.07), .option: amb(0.07), .optionOn: amb(0.2),
            .pill: .clear, .pillText: amb(0.95), .pillStroke: amb(0.6), .primary: amb(0.95), .primaryText: .black,
            .waitingBg: amb(0.12), .errorBg: Color(red: 1, green: 0.25, blue: 0.1, opacity: 0.14),
            .waiting: Color(red: 1, green: 0.86, blue: 0.4), .error: Color(red: 1, green: 0.38, blue: 0.2), .working: Color(red: 0.6, green: 1, blue: 0.45),
            .code: Color(red: 1, green: 0.84, blue: 0.45), .accent: amb(1),
        ],
        glow: amb(0.55))

    /// 1986 at night: violet sky, a striped sun sinking into a neon grid, chrome pink and cyan.
    static let synthwave = Theme(
        id: .synthwave, scheme: .dark, radius: 16, pillRadius: 100, rowInset: 6, rowRadius: 10, design: .default,
        headingFont: .system(size: 12, weight: .black).italic(), headingUppercase: true,
        colors: [
            .text: Color(red: 0.98, green: 0.9, blue: 1), .strong: .white, .secondary: Color(red: 0.88, green: 0.72, blue: 0.98),
            .dim: Color(red: 0.72, green: 0.55, blue: 0.9), .faint: Color(red: 1, green: 0.3, blue: 0.75, opacity: 0.35),
            .rule: Color(red: 0.3, green: 0.95, blue: 1, opacity: 0.3), .hover: Color(red: 1, green: 0.3, blue: 0.75, opacity: 0.13),
            .inset: Color(white: 1, opacity: 0.07), .option: Color(white: 1, opacity: 0.07), .optionOn: Color(red: 1, green: 0.3, blue: 0.75, opacity: 0.3),
            .pill: Color(red: 0.3, green: 0.95, blue: 1, opacity: 0.1), .pillText: Color(red: 0.55, green: 0.97, blue: 1),
            .pillStroke: Color(red: 0.3, green: 0.95, blue: 1, opacity: 0.7), .primary: Color(red: 1, green: 0.25, blue: 0.65), .primaryText: .white,
            .waitingBg: Color(red: 1, green: 0.55, blue: 0.2, opacity: 0.16), .errorBg: Color(red: 1, green: 0.2, blue: 0.4, opacity: 0.18),
            .waiting: Color(red: 1, green: 0.78, blue: 0.3), .error: Color(red: 1, green: 0.35, blue: 0.5), .working: Color(red: 0.3, green: 1, blue: 0.75),
            .code: Color(red: 0.55, green: 0.97, blue: 1), .accent: Color(red: 1, green: 0.3, blue: 0.75),
        ],
        glow: Color(red: 1, green: 0.3, blue: 0.8, opacity: 0.55),
        primaryGradient: [Color(red: 1, green: 0.22, blue: 0.62), Color(red: 1, green: 0.55, blue: 0.25)])

    /// An architect's blueprint: cyan-blue sheet, white grid, dashed outline, everything in drafting mono.
    static let blueprint = Theme(
        id: .blueprint, scheme: .dark, radius: 3, pillRadius: 1, rowInset: 0, rowRadius: 0, design: .monospaced,
        headingFont: .system(size: 10.5, weight: .bold, design: .monospaced), headingUppercase: true,
        colors: [
            .text: Color(white: 1, opacity: 0.95), .strong: .white, .secondary: Color(white: 1, opacity: 0.78), .dim: Color(red: 0.72, green: 0.85, blue: 1, opacity: 0.75),
            .faint: Color(white: 1, opacity: 0.4), .rule: Color(white: 1, opacity: 0.35), .hover: Color(white: 1, opacity: 0.08),
            .inset: Color(white: 1, opacity: 0.06), .option: Color(white: 1, opacity: 0.06), .optionOn: Color(white: 1, opacity: 0.2),
            .pill: .clear, .pillText: .white, .pillStroke: Color(white: 1, opacity: 0.8), .primary: .white, .primaryText: Color(red: 0.06, green: 0.3, blue: 0.62),
            .waitingBg: Color(red: 1, green: 0.85, blue: 0.3, opacity: 0.14), .errorBg: Color(red: 1, green: 0.4, blue: 0.4, opacity: 0.16),
            .waiting: Color(red: 1, green: 0.88, blue: 0.4), .error: Color(red: 1, green: 0.6, blue: 0.55), .working: Color(red: 0.6, green: 1, blue: 0.8),
            .code: .white, .accent: Color(red: 1, green: 0.88, blue: 0.4),
        ])

    /// Neo-brutalism: acid yellow, heavy black lines, hard shadows, loud type.
    static let brutal = Theme(
        id: .brutal, scheme: .light, radius: 10, pillRadius: 6, rowInset: 6, rowRadius: 6, design: .default,
        headingFont: .system(size: 14, weight: .black), headingUppercase: true,
        colors: [
            .text: .black, .strong: .black, .secondary: Color(white: 0.12), .dim: Color(white: 0, opacity: 0.58), .faint: .black,
            .rule: .black, .hover: Color(white: 1, opacity: 0.55), .inset: .white, .option: .white, .optionOn: Color(red: 0.55, green: 0.85, blue: 1),
            .pill: .white, .pillText: .black, .pillStroke: .black, .primary: Color(red: 1, green: 0.45, blue: 0.72), .primaryText: .black,
            .waitingBg: .white, .errorBg: Color(red: 1, green: 0.6, blue: 0.55),
            .waiting: Color(red: 0.75, green: 0.3, blue: 0), .error: Color(red: 0.8, green: 0, blue: 0.1), .working: Color(red: 0, green: 0.5, blue: 0.2),
            .code: .black, .accent: Color(red: 1, green: 0.45, blue: 0.72),
        ],
        hardShadow: true)

    /// Holographic foil: near-black with a rainbow sheen that drifts across, iridescent rim and button.
    static let hologram = Theme(
        id: .hologram, scheme: .dark, radius: 18, pillRadius: 100, rowInset: 6, rowRadius: 12, design: .rounded,
        headingFont: .system(size: 12, weight: .bold, design: .rounded), headingUppercase: false,
        colors: [
            .text: Color(white: 0.95), .strong: .white, .secondary: Color(white: 0.75), .dim: Color(red: 0.62, green: 0.66, blue: 0.75),
            .faint: Color(white: 1, opacity: 0.18), .rule: Color(white: 1, opacity: 0.1), .hover: Color(white: 1, opacity: 0.07),
            .inset: Color(white: 1, opacity: 0.06), .option: Color(white: 1, opacity: 0.07), .optionOn: Color(red: 0.7, green: 0.6, blue: 1, opacity: 0.3),
            .pill: Color(white: 1, opacity: 0.08), .pillText: .white, .pillStroke: Color(white: 1, opacity: 0.22), .primary: .white, .primaryText: .black,
            .waitingBg: Color(red: 1, green: 0.8, blue: 0.4, opacity: 0.1), .errorBg: Color(red: 1, green: 0.4, blue: 0.5, opacity: 0.12),
            .waiting: Color(red: 1, green: 0.84, blue: 0.45), .error: Color(red: 1, green: 0.48, blue: 0.55), .working: Color(red: 0.45, green: 1, blue: 0.8),
            .code: Color(red: 0.85, green: 0.92, blue: 1), .accent: Color(red: 0.75, green: 0.65, blue: 1),
        ],
        primaryGradient: [Color(red: 1, green: 0.7, blue: 0.9), Color(red: 0.7, green: 0.85, blue: 1), Color(red: 0.75, green: 1, blue: 0.85), Color(red: 1, green: 0.95, blue: 0.7)])

    static let holoColors: [Color] = [Color(red: 1, green: 0.4, blue: 0.75), Color(red: 1, green: 0.85, blue: 0.4), Color(red: 0.4, green: 1, blue: 0.75),
                                      Color(red: 0.35, green: 0.75, blue: 1), Color(red: 0.7, green: 0.45, blue: 1), Color(red: 1, green: 0.4, blue: 0.75)]
}

extension EnvironmentValues {
    @Entry var theme: Theme = .terminal
}

/// A colour that follows the theme in the environment, so shared views need no theme argument.
struct Ink: ShapeStyle {
    let role: InkRole
    func resolve(in environment: EnvironmentValues) -> Color.Resolved { environment.theme.color(role).resolve(in: environment) }

    static let text = Ink(role: .text), strong = Ink(role: .strong), secondary = Ink(role: .secondary), dim = Ink(role: .dim)
    static let faint = Ink(role: .faint), rule = Ink(role: .rule), hover = Ink(role: .hover), inset = Ink(role: .inset)
    static let option = Ink(role: .option), optionOn = Ink(role: .optionOn), pill = Ink(role: .pill), pillText = Ink(role: .pillText)
    static let pillStroke = Ink(role: .pillStroke), primary = Ink(role: .primary), primaryText = Ink(role: .primaryText)
    static let waitingBg = Ink(role: .waitingBg), errorBg = Ink(role: .errorBg), waiting = Ink(role: .waiting)
    static let error = Ink(role: .error), working = Ink(role: .working), code = Ink(role: .code), accent = Ink(role: .accent)
}

extension View {
    /// Puts the theme into the environment with its colour scheme, so system controls match it too.
    func themed(_ theme: Theme) -> some View {
        environment(\.theme, theme).environment(\.colorScheme, theme.scheme)
    }

    /// The panel body of the theme: its surface, rim and corner radius.
    func themeSurface(_ theme: Theme, radius: CGFloat? = nil) -> some View {
        let r = radius ?? theme.radius
        return background(ThemeSurface(theme: theme, radius: r))
            .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay(ThemeRim(theme: theme, radius: r))
    }
}

/// Snapshots cannot draw a window blur; they get a still picture of the glass instead.
extension EnvironmentValues {
    @Entry var themeSnapshot = false
}

struct ThemeSurface: View {
    let theme: Theme
    let radius: CGFloat
    @Environment(\.themeSnapshot) private var snapshot

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch theme.id {
        case .terminal:
            shape.fill(Color(white: 0.11))
        case .glass:
            ZStack {
                if snapshot { shape.fill(Color(red: 0.16, green: 0.19, blue: 0.27).opacity(0.86)) } else { GlassBlur().clipShape(shape) }
                // A dark wash keeps text readable over any wallpaper; the sheen is the light hitting the top.
                shape.fill(Color.black.opacity(snapshot ? 0.18 : 0.32))
                shape.fill(LinearGradient(colors: [.white.opacity(0.13), .white.opacity(0.02), .clear],
                                          startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35)))
                shape.fill(RadialGradient(colors: [.white.opacity(0.08), .clear], center: UnitPoint(x: 0.15, y: 0), startRadius: 0, endRadius: 260))
            }
        case .paper:
            ZStack {
                shape.fill(LinearGradient(colors: [Color(red: 0.985, green: 0.975, blue: 0.95), Color(red: 0.965, green: 0.952, blue: 0.92)],
                                          startPoint: .top, endPoint: .bottom))
            }
        case .midnight:
            ZStack {
                shape.fill(LinearGradient(colors: [Color(red: 0.085, green: 0.09, blue: 0.15), Color(red: 0.05, green: 0.055, blue: 0.09)],
                                          startPoint: .top, endPoint: .bottom))
                shape.fill(RadialGradient(colors: [Color(red: 0.45, green: 0.38, blue: 1).opacity(0.24), .clear],
                                          center: UnitPoint(x: 0.5, y: -0.05), startRadius: 0, endRadius: 240))
                    .scaleEffect(x: 1.5, y: 1, anchor: .top)
            }
        case .console:
            ZStack {
                shape.fill(LinearGradient(colors: [Color(white: 0.925), Color(white: 0.875)], startPoint: .top, endPoint: .bottom))
                // A fine horizontal grain, like brushed aluminium.
                Canvas { ctx, size in
                    var y: CGFloat = 0
                    while y < size.height {
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)), with: .color(.white.opacity(0.35)))
                        y += 2
                    }
                }
                .opacity(0.5)
            }
        case .phosphor:
            ZStack {
                shape.fill(Color(red: 0.045, green: 0.03, blue: 0.01))
                shape.fill(RadialGradient(colors: [Color(red: 1, green: 0.6, blue: 0.15).opacity(0.12), .clear],
                                          center: .center, startRadius: 10, endRadius: 360))
                Canvas { ctx, size in
                    var y: CGFloat = 0
                    while y < size.height {
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.32)))
                        y += 3
                    }
                }
                // The tube darkens toward its curved edges.
                shape.fill(RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center, startRadius: 160, endRadius: 420))
            }
        case .synthwave:
            ZStack {
                shape.fill(LinearGradient(colors: [Color(red: 0.07, green: 0.02, blue: 0.16), Color(red: 0.2, green: 0.03, blue: 0.3), Color(red: 0.32, green: 0.04, blue: 0.32)],
                                          startPoint: .top, endPoint: .bottom))
                SynthSun().opacity(0.85)
                SynthGrid()
            }
        case .blueprint:
            ZStack {
                shape.fill(RadialGradient(colors: [Color(red: 0.1, green: 0.36, blue: 0.7), Color(red: 0.05, green: 0.24, blue: 0.52)],
                                          center: .topLeading, startRadius: 0, endRadius: 600))
                Canvas { ctx, size in
                    for (step, alpha) in [(CGFloat(10), 0.06), (CGFloat(50), 0.14)] {
                        var x: CGFloat = 0
                        while x < size.width { ctx.fill(Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)), with: .color(.white.opacity(alpha))); x += step }
                        var y: CGFloat = 0
                        while y < size.height { ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)), with: .color(.white.opacity(alpha))); y += step }
                    }
                }
            }
        case .brutal:
            ZStack {
                shape.fill(Color(red: 1, green: 0.9, blue: 0.2))
                // Halftone dots in one corner, like a cheap print.
                Canvas { ctx, size in
                    // Bottom-right corner, away from the summary line.
                    var y = size.height - 4
                    while y > size.height - 120 {
                        var x = size.width - 4
                        while x > size.width - 140 {
                            let d = max(0, 3.2 - (size.width - x + size.height - y) / 50)
                            if d > 0.3 { ctx.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)), with: .color(.black.opacity(0.22))) }
                            x -= 7
                        }
                        y -= 7
                    }
                }
            }
        case .hologram:
            ZStack {
                shape.fill(Color(red: 0.05, green: 0.055, blue: 0.08))
                shape.fill(LinearGradient(colors: Theme.holoColors.map { $0.opacity(0.16) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                shape.fill(AngularGradient(colors: Theme.holoColors.map { $0.opacity(0.1) }, center: UnitPoint(x: 0.8, y: 0.1)))
                shape.fill(LinearGradient(colors: [.clear, .white.opacity(0.07), .clear], startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.6, y: 0.5)))
            }
        }
    }
}

/// A striped sun low on the horizon.
private struct SynthSun: View {
    var body: some View {
        GeometryReader { g in
            let d = min(g.size.width * 0.45, 170)
            Circle()
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.3), Color(red: 1, green: 0.3, blue: 0.6)], startPoint: .top, endPoint: .bottom))
                .mask {
                    VStack(spacing: 0) {
                        Rectangle().frame(height: d * 0.55)
                        ForEach(0..<6, id: \.self) { i in
                            Rectangle().frame(height: d * 0.075 - CGFloat(i) * 0.6).padding(.bottom, CGFloat(i + 1) * 1.6)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: d, height: d)
                .opacity(0.2)
                .position(x: g.size.width * 0.8, y: g.size.height - d * 0.12)
                .blur(radius: 0.3)
        }
    }
}

/// A neon floor in perspective, fading out toward the text.
private struct SynthGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let horizon = size.height * 0.72
            let color = Color(red: 1, green: 0.3, blue: 0.8)
            var p = Path()
            for i in -12...12 {
                let x0 = size.width / 2 + CGFloat(i) * 22
                let x1 = size.width / 2 + CGFloat(i) * 110
                p.move(to: CGPoint(x: x0, y: horizon)); p.addLine(to: CGPoint(x: x1, y: size.height))
            }
            var t: CGFloat = 0.02
            while t < 1 {
                let y = horizon + (size.height - horizon) * t
                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                t *= 1.6
            }
            ctx.stroke(p, with: .color(color.opacity(0.32)), lineWidth: 0.8)
            ctx.fill(Path(CGRect(x: 0, y: horizon - 0.5, width: size.width, height: 1)), with: .color(Color(red: 0.4, green: 0.95, blue: 1).opacity(0.5)))
        }
        .mask(LinearGradient(colors: [.clear, .black], startPoint: UnitPoint(x: 0.5, y: 0.7), endPoint: .bottom))
    }
}

/// The edge: a lit rim for glass, a hairline elsewhere, a machined double line for the console.
struct ThemeRim: View {
    let theme: Theme
    let radius: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch theme.id {
        case .terminal:
            shape.strokeBorder(Color(white: 0.23), lineWidth: 0.5)
        case .glass:
            ZStack {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.12), .white.opacity(0.05), .white.opacity(0.22)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                shape.inset(by: 1).strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5)
            }
        case .paper:
            shape.strokeBorder(Color(red: 0.3, green: 0.24, blue: 0.15).opacity(0.18), lineWidth: 0.5)
        case .midnight:
            shape.strokeBorder(LinearGradient(colors: [Color(red: 0.62, green: 0.6, blue: 1).opacity(0.38), Color.white.opacity(0.06)],
                                              startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)), lineWidth: 0.75)
        case .console:
            ZStack {
                shape.strokeBorder(Color.black.opacity(0.32), lineWidth: 1)
                shape.inset(by: 1).strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
            }
        case .phosphor:
            ZStack {
                shape.strokeBorder(Color(white: 0.2), lineWidth: 2)
                shape.inset(by: 2).strokeBorder(Color(red: 1, green: 0.7, blue: 0.22).opacity(0.25), lineWidth: 0.5)
            }
        case .synthwave:
            shape.strokeBorder(LinearGradient(colors: [Color(red: 0.3, green: 0.95, blue: 1), Color(red: 1, green: 0.3, blue: 0.75), Color(red: 1, green: 0.6, blue: 0.25)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
        case .blueprint:
            ZStack {
                shape.strokeBorder(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                shape.inset(by: 4).strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
            }
        case .brutal:
            shape.strokeBorder(Color.black, lineWidth: 2.5)
        case .hologram:
            shape.strokeBorder(AngularGradient(colors: Theme.holoColors, center: .center), lineWidth: 1.2).opacity(0.85)
        }
    }
}

/// The real thing on macOS 26; a behind-window blur before it.
private struct GlassBlur: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.clear, in: Rectangle())
        } else {
            BehindWindowBlur()
        }
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .vibrantDark)
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Row highlight and attention backgrounds: edge to edge, or a rounded inset card.
struct ThemeRowFill<S: ShapeStyle>: View {
    let style: S
    @Environment(\.theme) private var theme
    var body: some View {
        if theme.rowInset > 0 {
            RoundedRectangle(cornerRadius: theme.rowRadius, style: .continuous).fill(style)
                .overlay { if theme.hardShadow { RoundedRectangle(cornerRadius: theme.rowRadius, style: .continuous).strokeBorder(Color.black, lineWidth: 2) } }
                .padding(.horizontal, theme.rowInset)
        } else {
            Rectangle().fill(style)
        }
    }
}

extension AppSettings {
    var currentTheme: Theme { Theme.of(theme) }
}
