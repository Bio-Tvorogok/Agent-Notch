import SwiftUI
import NotchCore

/// Five small panels, each drawn by its own theme, over a wallpaper so glass has something to show.
struct SettingsThemePicker: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        HStack(spacing: 8) {
            ForEach(ThemeID.allCases, id: \.self) { id in
                ThemeSwatch(theme: .of(id), selected: settings.theme == id) { settings.theme = id }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 6) {
                ZStack {
                    ThemeWallpaper()
                    mini.padding(8)
                }
                .frame(height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 0.5))
                Text(SettingsText.theme(theme.id)).font(.system(size: 11, weight: selected ? .semibold : .regular)).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SettingsText.theme(theme.id))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A panel in miniature: a header line, an amber request with its button, two rows.
    private var mini: some View {
        VStack(alignment: .leading, spacing: 4) {
            line(Ink.secondary, 0.5)
            HStack(spacing: 3) {
                Circle().fill(Ink.waiting).frame(width: 4, height: 4)
                line(Ink.text, 0.45)
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: min(theme.pillRadius, 3)).fill(Ink.primary).frame(width: 14, height: 5)
            }
            .padding(.vertical, 2).padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: theme.rowInset > 0 ? 3 : 0).fill(Ink.waitingBg))
            HStack(spacing: 3) { Circle().fill(Ink.working).frame(width: 4, height: 4); line(Ink.text, 0.6) }.padding(.horizontal, 3)
            HStack(spacing: 3) { Circle().fill(Ink.working).frame(width: 4, height: 4); line(Ink.dim, 0.4) }.padding(.horizontal, 3)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themeSurface(theme, radius: min(theme.radius, 12) * 0.6)
        .themed(theme)
        .environment(\.themeSnapshot, true)
    }

    private func line(_ ink: Ink, _ fraction: CGFloat) -> some View {
        GeometryReader { g in Capsule().fill(ink).frame(width: g.size.width * fraction, height: 3) }.frame(height: 3)
    }
}

/// A calm desktop picture, the same in every preview, so themes compare on equal ground.
struct ThemeWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.2, green: 0.36, blue: 0.62), Color(red: 0.52, green: 0.32, blue: 0.6), Color(red: 0.95, green: 0.55, blue: 0.42)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.4, green: 0.85, blue: 0.9).opacity(0.55), .clear], center: UnitPoint(x: 0.85, y: 0.15), startRadius: 0, endRadius: 220)
        }
    }
}
