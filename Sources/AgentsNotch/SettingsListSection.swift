import SwiftUI
import NotchCore

struct SettingsListSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                SettingsChoice(title: SettingsText.sorting, value: $settings.rows.sort)
                Toggle(SettingsText.groupProjects, isOn: $settings.rows.groupByProject).toggleStyle(.switch)
                SettingsChoice(title: SettingsText.tree, hint: SettingsText.treeHelp, value: $settings.rows.subagentTree,
                               only: [.auto, .expanded, .collapsed, .hidden])
                SettingsChoice(title: SettingsText.titleSource, value: $settings.rows.titleSource)
            }
            Section {
                Toggle(SettingsText.showFinished, isOn: $settings.rows.showFinished).toggleStyle(.switch)
                Picker(SettingsText.finished, selection: $settings.appearance.finishedMinutes) {
                    ForEach(DisplayPreset.finishedChoices, id: \.self) { Text(SettingsText.minutes($0)).tag($0) }
                }.disabled(!settings.rows.showFinished)
            }
            Section(SettingsText.vendors) {
                Toggle(SettingsText.claude, isOn: $settings.behavior.claude).toggleStyle(.switch)
                Toggle(SettingsText.codex, isOn: $settings.behavior.codex).toggleStyle(.switch)
            }
            Section(SettingsText.wing) {
                SettingsChoice(title: SettingsText.wingContent, value: $settings.wing.content)
                Stepper(value: $settings.wing.maxMarks, in: 1...20) {
                    SettingsLabel(SettingsText.maxMarks + ": \(settings.wing.maxMarks)", hint: SettingsText.maxMarksHelp)
                }
                SettingsChoice(title: SettingsText.grouping, value: $settings.wing.grouping)
                Toggle(SettingsText.separate, isOn: $settings.wing.separateSubagents).toggleStyle(.switch)
            }
        }
    }
}

struct SettingsLimits: View {
    @ObservedObject var settings: AppSettings
    var body: some View {
        Form {
            Section {
                Picker(SettingsText.chips, selection: $settings.appearance.limitChips) {
                    ForEach(LimitChipMode.allCases, id: \.self) { Text(SettingsText.name($0.rawValue)).tag($0) }
                }.pickerStyle(.segmented)
                LabeledContent(SettingsText.warning) {
                    HStack {
                        Slider(value: Binding(get: { Double(settings.limits.warningPercent) },
                                              set: { settings.limits.warningPercent = Int($0.rounded()) }), in: 1...100).frame(width: 180)
                        Text("\(settings.limits.warningPercent) %").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Section(SettingsText.windows) {
                ForEach(LimitWindow.allCases, id: \.self) { window in
                    Toggle(SettingsText.name(window.rawValue), isOn: Binding(
                        get: { settings.limits.windows.contains(window) },
                        set: { on in
                            settings.limits.windows.removeAll { $0 == window }
                            if on { settings.limits.windows.append(window) }
                        })).toggleStyle(.switch)
                }
            }
            Section(SettingsText.limitVendors) {
                Toggle(SettingsText.claude, isOn: $settings.limits.claude).toggleStyle(.switch)
                Toggle(SettingsText.codex, isOn: $settings.limits.codex).toggleStyle(.switch)
            }
        }
    }
}
