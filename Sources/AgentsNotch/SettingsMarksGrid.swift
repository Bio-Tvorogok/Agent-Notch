import SwiftUI
import NotchCore

/// Synthetic marks cover every style, state, vendor and model weight, on both backgrounds.
struct SettingsMarksGrid: View {
    private let states: [AgentState] = [.working, .waiting, .error, .done]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(SettingsText.marks).font(.title2.bold()).padding(.horizontal, 20)
            grid(dark: false)
            grid(dark: true)
            Text(SettingsText.regular + " / " + SettingsText.light).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20)
        }
        .padding(.vertical, 22).frame(width: 940).background(Color(white: 0.94))
    }

    private func grid(dark: Bool) -> some View {
        VStack(spacing: 12) {
            HStack {
                Spacer().frame(width: 150)
                ForEach([Vendor.claude, .codex], id: \.rawValue) { vendor in
                    Text(vendor == .claude ? SettingsText.claude : SettingsText.codex).font(.headline).frame(width: 336)
                }
            }
            HStack(spacing: 0) {
                Spacer().frame(width: 150)
                ForEach(0..<2, id: \.self) { _ in
                    ForEach(states, id: \.rawValue) { state in
                        Text(stateName(state)).font(.caption).frame(width: 84)
                    }
                }
            }
            ForEach(MarkStyle.allCases, id: \.self) { style in
                HStack(spacing: 0) {
                    Text(SettingsText.name(style.rawValue)).font(.subheadline).frame(width: 150, alignment: .leading)
                    ForEach([Vendor.claude, .codex], id: \.rawValue) { vendor in
                        ForEach(states, id: \.rawValue) { state in
                            HStack(spacing: 8) {
                                StatusMark(vendor: vendor, state: state, isLight: false, style: style, size: 28)
                                StatusMark(vendor: vendor, state: state, isLight: true, style: style, size: 28)
                            }.frame(width: 84, height: 44)
                        }
                    }
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity)
        .background(dark ? Color.black : Color.white, in: RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, dark ? .dark : .light)
        .padding(.horizontal, 20)
    }

    private func stateName(_ state: AgentState) -> String {
        switch state {
        case .working: SettingsText.name("working")
        case .waiting: SettingsText.name("waiting")
        case .error: SettingsText.name("error")
        case .done: SettingsText.name("done")
        }
    }
}
