import SwiftUI
import NotchCore

extension AgentState {
    var color: Color {
        switch self {
        case .working: Color(red: 0.19, green: 0.82, blue: 0.35)
        case .waiting: Color(red: 1, green: 0.69, blue: 0.12)
        case .error: Color(red: 1, green: 0.27, blue: 0.23)
        case .done: Color(white: 0.29)
        }
    }
}

/// Shape = vendor (circle Claude, square Codex), fill = model weight (ring for light models), colour = state.
struct MarkView: View {
    let mark: Mark
    var size: CGFloat = 6

    var body: some View {
        if mark.state == .waiting {
            SurfaceTimeline(every: 0.5) { date in
                shape.opacity(Int(date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0.25)
            }
        } else {
            shape
        }
    }

    private var shape: some View {
        let c = mark.state.color
        let line: CGFloat = size > 5 ? 1.5 : 1.2
        return Group {
            if mark.vendor == .claude {
                if mark.light { Circle().strokeBorder(c, lineWidth: line) } else { Circle().fill(c) }
            } else {
                let r = RoundedRectangle(cornerRadius: size > 5 ? 1.5 : 1)
                if mark.light { r.strokeBorder(c, lineWidth: line) } else { r.fill(c) }
            }
        }
        .frame(width: size, height: size)
    }
}

extension MarkView {
    init(_ a: Agent, size: CGFloat = 6, state: AgentState? = nil) {
        self.init(mark: Mark(vendor: a.vendor, light: a.isLight, state: state ?? a.state), size: size)
    }
}

/// Four bars: low, medium, high, xhigh/max.
struct EffortBars: View {
    let effort: Effort?
    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(i < (effort?.rawValue ?? 0) ? Ink.secondary : Ink.faint)
                    .frame(width: 2, height: CGFloat(3 + i * 2))
            }
        }
        .frame(height: 9, alignment: .bottom)
    }
}
