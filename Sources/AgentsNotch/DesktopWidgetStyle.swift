import SwiftUI
import NotchCore

/// The widget's top: the number of running agents, big, and what needs the user. Each theme dresses it its own way.
struct WidgetHero: View {
    let live: Int
    let waiting: Int
    let errors: Int
    let size: WidgetSize
    @Environment(\.theme) private var theme

    private var numberSize: CGFloat { size == .small ? 44 : 60 }
    private var title: String { live == 0 ? WidgetText.idle : WidgetText.working(live) }

    var body: some View {
        Group {
            switch theme.id {
            case .terminal: plain(weight: .bold, design: .default)
            case .glass: plain(weight: .ultraLight, design: .default)
            case .paper: paper
            case .midnight: flaps
            case .console: lcd
            case .phosphor, .wasteland: prompt
            case .synthwave, .hologram: ring
            case .blueprint: titleBlock
            case .brutal: brutal
            case .pixel: party
            case .ducks: pond
            }
        }
        .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 8)
    }

    /// "1 ждёт ответа · 1 ошибка" with the state colours; nothing when all is calm.
    @ViewBuilder private func states(dots: Bool = true, font: Font = .system(size: 12)) -> some View {
        if waiting > 0 || errors > 0 {
            HStack(spacing: 6) {
                if waiting > 0 { state(WidgetText.waiting(waiting), Ink.waiting, dot: dots) }
                if waiting > 0 && errors > 0 { Text("·").foregroundStyle(dim) }
                if errors > 0 { state(WidgetText.errors(errors), Ink.error, dot: dots) }
            }
            .font(font).lineLimit(1)
        }
    }

    private func state(_ text: String, _ color: Ink, dot: Bool) -> some View {
        HStack(spacing: 4) {
            if dot { Circle().fill(color).frame(width: 7, height: 7) }
            Text(text).foregroundStyle(dot ? AnyShapeStyle(Ink.secondary) : AnyShapeStyle(color))
        }
    }

    private func plain(weight: Font.Weight, design: Font.Design) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(live)").font(.system(size: numberSize, weight: weight, design: design)).foregroundStyle(Ink.strong)
                .monospacedDigit().lineLimit(1).fixedSize()
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: size == .small ? 15 : 19, weight: weight == .bold ? .semibold : .regular))
                    .foregroundStyle(Ink.strong).lineLimit(2).minimumScaleFactor(0.8)
                states()
            }
        }
        .overlay(alignment: .bottom) {
            if theme.id == .glass { Rectangle().fill(Ink.rule).frame(height: 0.5).offset(y: 8) }
        }
    }

    /// A newspaper front page: masthead, rule, a heavy serif number.
    private var paper: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Agent Notch").font(.system(size: 13, weight: .bold, design: .serif)).foregroundStyle(Ink.strong)
            Rectangle().fill(Ink.strong).frame(height: 1)
            HStack(alignment: .center, spacing: 10) {
                Text("\(live)").font(.system(size: numberSize + 6, weight: .black, design: .serif)).foregroundStyle(Ink.strong)
                    .lineLimit(1).fixedSize()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: size == .small ? 16 : 22, weight: .bold, design: .serif))
                        .foregroundStyle(Ink.strong).lineLimit(2).minimumScaleFactor(0.7)
                    states(dots: false, font: .system(size: 13, design: .serif))
                }
            }
            Rectangle().fill(Ink.rule).frame(height: 0.5)
        }
    }

    /// A departures board: the count on split-flap tiles.
    private var flaps: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 3) {
                ForEach(Array(String(format: "%02d", min(live, 99)).enumerated()), id: \.offset) { _, digit in
                    ZStack {
                        RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.07, green: 0.07, blue: 0.11))
                        Text(String(digit)).font(.system(size: numberSize * 0.7, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.4))
                        Rectangle().fill(Color.black.opacity(0.6)).frame(height: 1)
                    }
                    .frame(width: numberSize * 0.6, height: numberSize * 0.85)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased()).font(.system(size: 13, weight: .semibold, design: .monospaced)).tracking(1)
                    .foregroundStyle(Ink.strong).lineLimit(2).minimumScaleFactor(0.7)
                states(font: .system(size: 11, design: .monospaced))
            }
        }
    }

    /// An instrument panel: the count on a backlit LCD.
    private var lcd: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(String(format: "%02d", min(live, 99)))
                .font(.system(size: numberSize * 0.8, weight: .medium, design: .monospaced)).monospacedDigit()
                .foregroundStyle(Color(red: 0.12, green: 0.16, blue: 0.1))
                .padding(.horizontal, 10).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [Color(red: 0.72, green: 0.78, blue: 0.62), Color(red: 0.62, green: 0.7, blue: 0.54)],
                                                                                   startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black.opacity(0.45), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased()).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Ink.strong)
                    .lineLimit(2).minimumScaleFactor(0.7)
                states(font: .system(size: 11, design: .monospaced))
            }
        }
    }

    /// A terminal prompt: "> 5 агентов работают", the cursor blinking after it.
    private var prompt: some View {
        VStack(alignment: .leading, spacing: 4) {
            if theme.id == .wasteland {
                HStack(spacing: 10) {
                    ForEach(["STAT", "DATA", "LIMITS"], id: \.self) { tab in
                        Text(tab).font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(tab == "STAT" ? Ink.strong : Ink.dim)
                            .padding(.horizontal, 4)
                            .overlay(alignment: .bottom) { if tab == "STAT" { Rectangle().fill(Ink.strong).frame(height: 1.5).offset(y: 2) } }
                    }
                }
                .padding(.bottom, 4)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(">").foregroundStyle(Ink.accent)
                Text("\(live)").font(.system(size: numberSize * 0.75, weight: .bold, design: .monospaced)).foregroundStyle(Ink.strong)
                Text(title.uppercased()).foregroundStyle(Ink.strong).lineLimit(1).minimumScaleFactor(0.6)
                Rectangle().fill(Ink.strong).frame(width: 8, height: 14).offset(y: 2)
            }
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            states(dots: false, font: .system(size: 11, design: .monospaced))
        }
    }

    /// Neon or iridescent ring around the count.
    private var ring: some View {
        HStack(alignment: .center, spacing: 14) {
            let d = numberSize + 10
            ZStack {
                Circle().stroke(Ink.faint, lineWidth: 4)
                Circle()
                    .stroke(theme.id == .hologram ? AnyShapeStyle(AngularGradient(colors: Theme.holoColors, center: .center))
                            : AnyShapeStyle(LinearGradient(colors: [Color(red: 0.3, green: 0.95, blue: 1), Color(red: 1, green: 0.3, blue: 0.75)],
                                                           startPoint: .top, endPoint: .bottom)), lineWidth: 4)
                    .shadow(color: theme.id == .synthwave ? Color(red: 1, green: 0.3, blue: 0.75).opacity(0.8) : .clear, radius: 6)
                Text("\(live)").font(.system(size: numberSize * 0.55, weight: .bold, design: theme.design)).foregroundStyle(Ink.strong)
            }
            .frame(width: d, height: d)
            VStack(alignment: .leading, spacing: 4) {
                Text(theme.id == .synthwave ? title.uppercased() : title)
                    .font(.system(size: size == .small ? 14 : 17, weight: .bold, design: theme.design))
                    .foregroundStyle(Ink.strong).lineLimit(2).minimumScaleFactor(0.7)
                states()
            }
        }
    }

    /// A drawing's title block: a framed table with the count in its big cell.
    private var titleBlock: some View {
        HStack(spacing: 0) {
            Text("\(live)").font(.system(size: numberSize * 0.75, weight: .light, design: .monospaced)).foregroundStyle(Ink.strong)
                .frame(width: numberSize * 1.2).frame(maxHeight: .infinity)
                .overlay(alignment: .trailing) { Rectangle().fill(Ink.strong.opacity(0.7)).frame(width: 1) }
            VStack(alignment: .leading, spacing: 0) {
                Text(title.uppercased()).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Ink.strong)
                    .lineLimit(1).minimumScaleFactor(0.6).padding(6)
                Rectangle().fill(Ink.strong.opacity(0.7)).frame(height: 1)
                Group {
                    if waiting > 0 || errors > 0 { states(font: .system(size: 11, design: .monospaced)) }
                    else { Text(Loc.t("SHEET 1 · AGENT NOTCH", "ЛИСТ 1 · AGENT NOTCH")).font(.system(size: 10, design: .monospaced)).foregroundStyle(dim) }
                }
                .padding(6)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(Rectangle().strokeBorder(Ink.strong.opacity(0.7), lineWidth: 1))
    }

    /// Neo-brutal: a black slab with the number, sitting on a hard shadow.
    private var brutal: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(live)").font(.system(size: numberSize * 1.5, weight: .black)).foregroundStyle(Color.black)
                .lineLimit(1).fixedSize()
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased()).font(.system(size: size == .small ? 14 : 18, weight: .black)).foregroundStyle(Color.black)
                    .lineLimit(2).minimumScaleFactor(0.7)
                if waiting > 0 || errors > 0 {
                    HStack(spacing: 6) {
                        if waiting > 0 { tag(WidgetText.waiting(waiting), fill: Color.white) }
                        if errors > 0 { tag(WidgetText.errors(errors), fill: Color(red: 1, green: 0.35, blue: 0.3)) }
                    }
                }
            }
        }
    }

    private func tag(_ text: String, fill: Color) -> some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .heavy)).foregroundStyle(Color.black)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Rectangle().fill(fill)).overlay(Rectangle().strokeBorder(Color.black, lineWidth: 1.5))
    }

    /// An RPG dialog: "PARTY" with a pixel house and the count as its level.
    private var party: some View {
        HStack(alignment: .center, spacing: 12) {
            PixelHouse().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(Loc.t("PARTY", "ОТРЯД")).foregroundStyle(Ink.accent)
                    Text("×\(live)").foregroundStyle(Ink.strong)
                }
                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                Text(title.uppercased()).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Ink.text).lineLimit(1)
                states(dots: false, font: .system(size: 11, weight: .bold, design: .monospaced))
            }
        }
    }

    /// The rubber-duck pond: one duck per running agent.
    private var pond: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                Text("\(live)").font(.system(size: numberSize * 0.85, weight: .heavy, design: .rounded)).foregroundStyle(Ink.strong)
                VStack(alignment: .leading, spacing: 2) {
                    Text("// " + title).font(.system(size: size == .small ? 13 : 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Ink.strong).lineLimit(2).minimumScaleFactor(0.7)
                    states()
                }
            }
            if live > 0 {
                Text(String(repeating: "🦆", count: min(live, size == .small ? 6 : 10)) + (live > 10 ? " …" : ""))
                    .font(.system(size: 15))
            }
        }
    }
}

/// A tiny house in the palette of the pixel theme.
private struct PixelHouse: View {
    var body: some View {
        Canvas { ctx, size in
            let p = size.width / 11
            func px(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: Color) {
                ctx.fill(Path(CGRect(x: CGFloat(x) * p, y: CGFloat(y) * p, width: CGFloat(w) * p, height: CGFloat(h) * p)), with: .color(c))
            }
            let roof = Color(red: 0.95, green: 0.35, blue: 0.3), wall = Color(red: 0.98, green: 0.85, blue: 0.55)
            for row in 0..<4 { px(4 - row, row + 1, 3 + row * 2, 1, roof) }
            px(1, 5, 9, 5, wall)
            px(4, 7, 2, 3, Color(red: 0.45, green: 0.28, blue: 0.15))
            px(2, 6, 1, 1, Color(red: 0.4, green: 0.7, blue: 1)); px(7, 6, 2, 1, Color(red: 0.4, green: 0.7, blue: 1))
            px(0, 10, 11, 1, Color(red: 0.3, green: 0.75, blue: 0.35))
        }
    }
}

/// Claude and Codex limits at the bottom, drawn the theme's way: blocks, rulers, rings or plain bars.
struct WidgetLimits: View {
    @ObservedObject var usage: UsageModel
    var compact = false
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.theme) private var theme

    private struct Item: Identifiable {
        let id: String
        let label: String
        let percent: Double
        let reset: Date?
    }

    private var items: [Item] {
        usage.limits.compactMap { settings.displayedLimits($0) }.flatMap { limits in
            (compact ? Array(limits.windows.prefix(1)) : limits.windows).map {
                Item(id: "\(limits.vendor.rawValue).\($0.label)", label: "\(UsageViewText.vendor(limits.vendor)) \($0.label)",
                     percent: $0.usedPercent.isFinite ? min(100, max(0, $0.usedPercent)) : 0, reset: $0.resetsAt)
            }
        }
    }

    var body: some View {
        let items = items
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Rectangle().fill(Ink.rule).frame(height: theme.hardShadow ? 2 : 0.5).padding(.bottom, 4)
                switch theme.id {
                case .glass: columns(items)
                case .hologram, .synthwave: rings(items)
                default:
                    ForEach(items) { row($0) }
                }
                if let reset = items.compactMap(\.reset).min() {
                    Text(UsageViewText.reset(reset, now: usage.now)).font(.system(size: 10.5)).foregroundStyle(dim)
                }
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private func tone(_ percent: Double) -> AnyShapeStyle {
        switch UsageView.limitTone(percent, warningPercent: Double(settings.limits.warningPercent)) {
        case .grey: AnyShapeStyle(fill)
        case .amber: AnyShapeStyle(Ink.usageAmber)
        case .red: AnyShapeStyle(Ink.usageRed)
        }
    }

    /// The calm colour of a bar: the theme's working colour.
    private var fill: AnyShapeStyle {
        if let colors = theme.primaryGradient { return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)) }
        return AnyShapeStyle(Ink.working)
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 10) {
            Text(item.label).lineLimit(1).frame(width: compact ? 82 : 110, alignment: .leading)
            meter(item)
            Text(UsageViewText.percent(item.percent)).monospacedDigit().foregroundStyle(Ink.secondary).frame(width: 36, alignment: .trailing)
        }
        .font(.system(size: 11, weight: theme.hardShadow ? .bold : .regular))
    }

    @ViewBuilder private func meter(_ item: Item) -> some View {
        switch theme.id {
        case .terminal, .phosphor, .wasteland, .pixel, .console, .midnight:
            // Segments: block characters in a terminal, cells on an LCD, flaps on a board, hit points in a game.
            let count = theme.id == .pixel ? 10 : theme.id == .midnight ? 16 : theme.id == .console ? 12 : 8
            let lit = Int((item.percent / 100 * Double(count)).rounded())
            HStack(spacing: theme.id == .console ? 1 : 3) {
                ForEach(0..<count, id: \.self) { i in
                    Rectangle().fill(i < lit ? tone(item.percent) : AnyShapeStyle(Ink.faint))
                        .frame(height: theme.id == .pixel ? 8 : 10)
                        .clipShape(RoundedRectangle(cornerRadius: theme.id == .terminal || theme.id == .midnight ? 2 : 0))
                }
            }
        case .paper, .blueprint:
            // A ruler with ticks at every quarter.
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Ink.faint).frame(height: 6)
                    Rectangle().fill(tone(item.percent)).frame(width: g.size.width * item.percent / 100, height: 6)
                    ForEach(0..<5, id: \.self) { i in
                        Rectangle().fill(Ink.dim).frame(width: 0.5, height: 10).offset(x: g.size.width * CGFloat(i) / 4 - 0.25)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 12)
        case .brutal:
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black).offset(x: 2, y: 2)
                    Capsule().fill(Color(red: 0.98, green: 0.98, blue: 0.6))
                    Capsule().fill(item.percent >= Double(settings.limits.warningPercent) ? Color(red: 1, green: 0.31, blue: 0.66) : Color(red: 0.23, green: 0.63, blue: 1))
                        .frame(width: max(12, g.size.width * item.percent / 100))
                    Capsule().strokeBorder(Color.black, lineWidth: 2)
                }
            }
            .frame(height: 14)
        default:
            bar(item)
        }
    }

    private func bar(_ item: Item) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.faint)
                Capsule().fill(tone(item.percent)).frame(width: max(6, g.size.width * item.percent / 100))
            }
        }
        .frame(height: 7)
    }

    /// Ring gauges with the percent inside, the label beside each.
    private func rings(_ items: [Item]) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    ZStack {
                        Circle().stroke(Ink.faint, lineWidth: 4)
                        Circle().trim(from: 0, to: item.percent / 100)
                            .stroke(theme.id == .hologram ? AnyShapeStyle(AngularGradient(colors: Theme.holoColors, center: .center)) : tone(item.percent),
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: theme.id == .synthwave ? Color(red: 1, green: 0.3, blue: 0.75).opacity(0.7) : .clear, radius: 4)
                        Text(UsageViewText.percent(item.percent)).font(.system(size: 10, weight: .bold)).monospacedDigit()
                            .foregroundStyle(Ink.strong).minimumScaleFactor(0.7)
                    }
                    .frame(width: 38, height: 38)
                    Text(item.label).font(.system(size: 10.5)).lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Side by side, like the Weather widget's forecast: label and percent over a bar.
    private func columns(_ items: [Item]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.label).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 2)
                        Text(UsageViewText.percent(item.percent)).monospacedDigit().foregroundStyle(Ink.secondary)
                    }
                    .font(.system(size: 10.5))
                    bar(item)
                }
            }
        }
    }
}
