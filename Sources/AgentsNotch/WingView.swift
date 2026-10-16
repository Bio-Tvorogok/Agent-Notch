import SwiftUI
import NotchCore

struct WingView: View {
    let layout: WingLayout
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 0) {
            if layout.groups.isEmpty {
                Circle().fill(Color(white: 0.25)).frame(width: 4, height: 4)
            }
            ForEach(Array(layout.groups.enumerated()), id: \.offset) { i, group in
                if i > 0 { Rectangle().fill(Color(white: 0.17)).frame(width: 1, height: 10).padding(.horizontal, 7) }
                content(group)
            }
        }
        .padding(.leading, 11).padding(.trailing, 9)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private func content(_ group: WingGroup) -> some View {
        let metrics = settings.wingDisplay
        switch group {
        case let .detailed(label, sessions):
            HStack(spacing: metrics.sessionGap) {
                if let label { WingLabel(text: label, width: metrics.labelWidth(label)) }
                ForEach(Array(sessions.enumerated()), id: \.offset) { _, marks in
                    HStack(spacing: metrics.childGap) {
                        ForEach(Array(marks.enumerated()), id: \.offset) { i, mark in
                            WingStatusMark(mark: mark, small: i > 0)
                        }
                    }
                }
            }
        case let .counters(label, claude, codex, exceptions):
            HStack(spacing: metrics.sessionGap) {
                if let label { WingLabel(text: label, width: metrics.labelWidth(label)) }
                WingCounter(vendor: .claude, count: claude)
                WingCounter(vendor: .codex, count: codex)
                ForEach(Array(exceptions.enumerated()), id: \.offset) { _, mark in WingStatusMark(mark: mark) }
            }
        }
    }
}

private struct WingLabel: View {
    let text: String
    let width: CGFloat
    var body: some View {
        Text(String(text.prefix(12))).font(.system(size: 9, weight: .medium)).foregroundStyle(Color(white: 0.39))
            .lineLimit(1).truncationMode(.tail).frame(width: width, alignment: .leading)
    }
}

private struct WingCounter: View {
    let vendor: Vendor
    let count: Int
    var body: some View {
        if count > 0 {
            HStack(spacing: 2) {
                WingStatusMark(mark: Mark(vendor: vendor, light: false, state: .working))
                Text("\(count)").font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundStyle(Color(white: 0.91))
            }
        }
    }
}

private struct WingStatusMark: View {
    let mark: Mark
    var small = false
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        let size = small ? settings.wingDisplay.childSize : settings.appearance.markSize.points
        ResolvedVendorMark(vendor: mark.vendor, state: mark.state, isLight: mark.light, size: size, onDark: true)
    }
}
