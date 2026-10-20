import SwiftUI
import NotchCore

/// «Дом на рабочем столе»: the agents' house as the desktop wallpaper.
struct SettingsHouse: View {
    @ObservedObject var settings: AppSettings
    @State private var projects: [String] = []

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.roomWallpaper) { SettingsLabel(HouseText.show, hint: HouseText.showHelp) }.toggleStyle(.switch)
                Picker(selection: $settings.room.layout) {
                    ForEach(RoomPrefs.Layout.allCases, id: \.self) { Text(HouseText.layout($0)).tag($0) }
                } label: { SettingsLabel(HouseText.layoutTitle, hint: HouseText.layoutHelp) }
                Picker(selection: $settings.room.frameRate) {
                    ForEach(RoomPrefs.FrameRate.allCases, id: \.self) { Text(HouseText.frameRate($0)).tag($0) }
                } label: { SettingsLabel(HouseText.frameRateTitle, hint: HouseText.frameRateHelp) }
                Picker(selection: $settings.room.screens) {
                    ForEach(RoomPrefs.Screens.allCases, id: \.self) { Text(HouseText.screens($0)).tag($0) }
                } label: { SettingsLabel(HouseText.screensTitle, hint: HouseText.screensHelp) }
            }
            Section {
                if projects.isEmpty { Text(HouseText.noProjects).foregroundStyle(.secondary) }
                ForEach(projects, id: \.self) { project in
                    Picker(project, selection: theme(for: project)) {
                        Text(HouseText.auto(RoomTheme.auto(for: project))).tag("")
                        Divider()
                        ForEach(RoomTheme.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    }
                }
            } header: {
                SettingsLabel(HouseText.rooms, hint: HouseText.roomsHelp)
            }
        }
        .onAppear {
            // Projects on screen now, and the ones that already have a room chosen.
            projects = Array(Set(RoomProjects.shared.current + settings.room.themes.keys))
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }

    private func theme(for project: String) -> Binding<String> {
        Binding(get: { settings.room.themes[project].flatMap { RoomTheme(rawValue: $0)?.rawValue } ?? "" },
                set: { settings.room.themes[project] = $0.isEmpty ? nil : $0 })
    }
}

enum HouseText {
    static var section: String { Loc.t("Desktop house", "Дом на рабочем столе") }
    static var show: String { Loc.t("Agents' house on the desktop", "Дом агентов на рабочем столе") }
    static var showHelp: String { Loc.t("Every project is a room, every agent walks around in it", "Каждый проект — комната, каждый агент ходит по ней") }
    static var layoutTitle: String { Loc.t("Layout", "Расположение") }
    static var layoutHelp: String { Loc.t("How the project rooms stand around the shared ones", "Как комнаты проектов стоят вокруг общих") }
    static func layout(_ l: RoomPrefs.Layout) -> String {
        switch l {
        case .islands: Loc.t("Islands", "Острова")
        case .steps: Loc.t("Steps", "Ступеньки")
        case .towers: Loc.t("Towers", "Башни")
        }
    }
    static var frameRateTitle: String { Loc.t("Frame rate", "Частота кадров") }
    static var frameRateHelp: String { Loc.t("Auto: 60 on power, 30 on battery", "Авто: 60 от сети, 30 от батареи") }
    static func frameRate(_ f: RoomPrefs.FrameRate) -> String {
        switch f {
        case .auto: Loc.t("Auto", "Авто")
        case .fps30: Loc.t("30 fps", "30 кадров")
        case .fps60: Loc.t("60 fps", "60 кадров")
        }
    }
    static var screensTitle: String { Loc.t("Screens", "Экраны") }
    static var screensHelp: String { Loc.t("Other screens show the same sky with floating islands", "На других экранах — то же небо с летающими островами") }
    static func screens(_ s: RoomPrefs.Screens) -> String {
        switch s {
        case .main: Loc.t("Main screen only", "Только основной экран")
        case .all: Loc.t("All screens", "Все экраны")
        }
    }
    static var rooms: String { Loc.t("Project rooms", "Комнаты проектов") }
    static var roomsHelp: String { Loc.t("Auto keeps a project's room when others come and go", "«Авто» не меняет комнату, когда появляются другие проекты") }
    static var noProjects: String { Loc.t("Projects appear here once their agents show up in the notch.", "Проекты появятся здесь, когда их агенты будут в чёлке.") }
    static func auto(_ theme: RoomTheme) -> String { Loc.t("Auto (\(theme.title))", "Авто (\(theme.title))") }
}
