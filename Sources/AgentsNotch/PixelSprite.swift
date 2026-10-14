import SwiftUI
import NotchCore

/// Equal frames share their drawing even when the animation clock advances.
struct PixelSprite: View, Equatable {
    let vendor: Vendor
    let state: AgentState
    let isLight: Bool
    let size: CGFloat
    let hop: Bool
    private var claude: Bool { vendor == .claude }

    var body: some View {
        let heart = claude ? [".oo.oo.", "ohffffo", "offfffo", "offfffo", ".offfo.", "..ofo..", "...o..."]
                           : ["..ooo..", ".ohffo.", "ohffffo", "offfffo", ".offfo.", "..ofo..", "...o..."]
        let fill: Color = switch state {
        case .working: claude ? Color(red: 1, green: 0.3, blue: 0.4) : Color(red: 0.3, green: 0.85, blue: 1)
        case .waiting: Color(red: 1, green: 0.82, blue: 0.1)
        case .error: Color(red: 0.6, green: 0.6, blue: 0.6)
        case .done: Color(red: 0.3, green: 0.32, blue: 0.5)
        }
        // Working sprites hop one pixel; an error cracks the sprite with a dark line.
        return Canvas { ctx, sz in
            let cell = sz.width / 7
            for (y, row) in heart.enumerated() {
                for (x, ch) in row.enumerated() {
                    let color: Color? = switch ch {
                    case "o": Color(red: 0.05, green: 0.04, blue: 0.15)
                    case "f": isLight ? nil : fill
                    case "h": .white
                    default: nil
                    }
                    guard var c = color else { continue }
                    if state == .error && x == y { c = .black }
                    ctx.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell - (hop ? cell : 0), width: cell, height: cell)), with: .color(c))
                }
            }
            if isLight {
                // Light models: only the outline, lit in the state colour.
                for (y, row) in heart.enumerated() {
                    for (x, ch) in row.enumerated() where ch == "o" {
                        ctx.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell - (hop ? cell : 0), width: cell, height: cell)), with: .color(fill))
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}
