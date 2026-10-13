import NotchCore

extension AppSettings {
    var visibleRowParts: [RowPart] {
        RowDisplay.parts(rowParts, showModel: appearance.showModel,
                         showActivity: appearance.showActivity, showContext: appearance.showContext)
    }

    var wingDisplay: WingDisplayPrefs {
        var prefs = WingDisplayPrefs()
        prefs.markSize = appearance.markSize
        prefs.maxMarks = wing.maxMarks
        prefs.countsOnly = wing.content == .counts
        prefs.showProjectNames = wing.content == .projects
        prefs.groupByVendor = wing.grouping == .vendor
        prefs.separateSubagents = wing.separateSubagents
        return prefs
    }

    func projects(from agents: [Agent]) -> [ProjectNode] {
        let visible = agents.filter { rows.showFinished || $0.state.isLive }
        return Tree.build(visible, includeFinished: rows.showFinished)
    }
}
