import AppKit
import SwiftUI
import NotchCore

/// Logos come from the installed apps, with our own shapes when an app is missing; the status colour and pulse mean the same in every style.
struct StatusMark: View {
    let vendor: Vendor
    let state: AgentState
    let isLight: Bool
    var style: MarkStyle = .dots
    var size: CGFloat = 6
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if state == .working {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    drawing.opacity(0.86 + 0.14 * sin(context.date.timeIntervalSinceReferenceDate * 2))
                }
            } else if state == .waiting {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    drawing.opacity(Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0.4)
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
            switch style {
            case .dots:
                if vendor == .claude { mark(Circle()) }
                else { mark(RoundedRectangle(cornerRadius: size * 0.22)) }
            case .logos:
                if let icon = appIcon { Image(nsImage: icon).resizable().interpolation(.high).opacity(isLight ? 0.55 : 1) }
                else { ownLogo }
            case .logosMono: ownLogo
            case .letters:
                mark(Circle())
                Text(vendor == .claude ? "C" : "X")
                    .font(.system(size: size * 0.62, weight: .bold, design: .rounded))
                    .foregroundStyle(isLight ? tint : Color.black)
                    .frame(width: size, height: size)
            }
            if style == .logos {
                let dot = max(3, size * 0.36)
                Circle().fill(state.color)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.85), lineWidth: max(0.8, dot * 0.22)))
                    .frame(width: dot, height: dot).offset(x: dot * 0.18, y: dot * 0.18)
            }
        }
    }

    @ViewBuilder private var ownLogo: some View {
        if vendor == .claude { mark(SparkMark()) }
        else {
            mark(KnotHexagon())
            KnotLines().stroke(isLight ? tint : (scheme == .dark ? .black : .white),
                               style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
                .padding(size * 0.19)
        }
    }

    @ViewBuilder private func mark<S: Shape>(_ shape: S) -> some View {
        if isLight { shape.stroke(tint, lineWidth: line).padding(line / 2) }
        else { shape.fill(tint) }
    }
}

private struct SparkMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0..<16 {
            let angle: CGFloat = CGFloat(i) * .pi / 8 - .pi / 2
            let radius = min(rect.width, rect.height) * (i.isMultiple(of: 2) ? 0.5 : 0.19)
            let point = CGPoint(x: rect.midX + cos(angle) * radius, y: rect.midY + sin(angle) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

private struct KnotHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let points = (0..<6).map { i in
            let angle: CGFloat = CGFloat(i) * .pi / 3 - .pi / 2
            return CGPoint(x: rect.midX + sin(angle) * rect.width * 0.5, y: rect.midY + cos(angle) * rect.height * 0.5)
        }
        func between(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x * 0.82 + b.x * 0.18, y: a.y * 0.82 + b.y * 0.18) }
        var path = Path()
        path.move(to: between(points[0], points[5]))
        for i in 0..<6 {
            path.addQuadCurve(to: between(points[i], points[(i + 1) % 6]), control: points[i])
            path.addLine(to: between(points[(i + 1) % 6], points[i]))
        }
        path.closeSubpath()
        return path
    }
}

private struct KnotLines: Shape {
    func path(in r: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.midY))
        path.addLine(to: CGPoint(x: r.midX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        path.move(to: CGPoint(x: r.minX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.midX, y: r.midY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return path
    }
}


/// Every agent surface reads the same style and size from its injected settings.
struct AgentStatusMark: View {
    let agent: Agent
    var small = false
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        StatusMark(vendor: agent.vendor, state: agent.state, isLight: agent.isLight,
                   style: settings.appearance.markStyle,
                   size: small ? settings.wingDisplay.childSize : settings.appearance.markSize.points)
    }
}
