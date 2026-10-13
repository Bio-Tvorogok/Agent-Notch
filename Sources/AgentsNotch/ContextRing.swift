import SwiftUI
import NotchCore

struct ContextRing: View {
    @ObservedObject var usage: UsageModel
    let agent: Agent

    var body: some View {
        HStack(spacing: 0) {
            if let value = usage.contexts[agent.id] {
                ZStack {
                    Circle().stroke(Ink.faint, lineWidth: 2)
                    Circle().trim(from: 0, to: UsageView.fraction(value.percent))
                        .stroke(UsageView.contextTone(value.percent).usageColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 12, height: 12)
                .help(UsageViewText.context(value))
                .accessibilityLabel(UsageViewText.context(value))
            }
        }
    }
}

extension UsageTone {
    var usageColor: AnyShapeStyle {
        switch self {
        case .grey: AnyShapeStyle(dim)
        case .amber: AnyShapeStyle(Ink.usageAmber)
        case .red: AnyShapeStyle(Ink.usageRed)
        }
    }
}
