import SwiftUI
import NotchCore

struct ContextRing: View {
    @ObservedObject var usage: UsageModel
    let agent: Agent

    var body: some View {
        HStack(spacing: 0) {
            if let value = usage.contexts[agent.id] {
                ZStack {
                    Circle().stroke(Color(white: 0.23), lineWidth: 2)
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
    var usageColor: Color {
        switch self {
        case .grey: dim
        case .amber: Color(red: 0.94, green: 0.69, blue: 0.24)
        case .red: Color(red: 0.96, green: 0.35, blue: 0.32)
        }
    }
}
