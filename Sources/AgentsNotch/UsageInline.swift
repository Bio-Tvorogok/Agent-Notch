import SwiftUI
import NotchCore

private enum UsageInlineText {
    static let spend = "Расход сегодня · условная цена"
    static let partial = "Ещё читаем журналы"
    static let empty = "Расходов пока нет"
    static let unknown = "цена неизвестна"
    static func amount(_ usd: Double?) -> String {
        usd.map { String(format: "$%.2f", $0) } ?? unknown
    }
}

struct UsageInline: View {
    @ObservedObject var usage: UsageModel
    @ObservedObject var settings: AppSettings = .shared
    var body: some View {
        if let vendor = usage.selectedVendor, let raw = usage.limits.first(where: { $0.vendor == vendor }),
           let limits = settings.displayedLimits(raw) {
            VStack(alignment: .leading, spacing: 6) {
                Text(UsageViewText.vendor(vendor)).fontWeight(.semibold)
                ForEach(Array(limits.windows.enumerated()), id: \.offset) { _, window in
                    Text(UsageViewText.window(window, now: usage.now))
                        .foregroundStyle(UsageView.limitTone(window.usedPercent, warningPercent: Double(settings.limits.warningPercent)).usageColor)
                }
                if limits.windows.isEmpty { Text(UsageViewText.stale).foregroundStyle(dim) }
                Text(UsageInlineText.spend).foregroundStyle(dim)
                ForEach(Array(usage.spend.enumerated()), id: \.offset) { _, project in
                    HStack {
                        Text(project.project).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(UsageInlineText.amount(project.usd)).foregroundStyle(dim)
                    }
                }
                if !usage.spendComplete || usage.spend.contains(where: \.isPartial) {
                    Text(UsageInlineText.partial).foregroundStyle(dim)
                } else if usage.spend.isEmpty { Text(UsageInlineText.empty).foregroundStyle(dim) }
            }
            .font(.system(size: 11))
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.14)))
            .padding(.horizontal, 12).padding(.bottom, 6)
        }
    }
}
