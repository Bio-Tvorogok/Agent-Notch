import NotchCore

extension AppSettings {
    var listFilter: ListFilter {
        ListFilter(claude: behavior.claude, codex: behavior.codex, hiddenProjects: behavior.hiddenProjects)
    }

    /// Rendering registers the store before a user can hide a pending request.
    func visibleAgents(_ agents: [Agent], store: Store) -> [Agent] {
        visibilityObservers[ObjectIdentifier(store)] = { [weak store] in store?.visibilityChanged() }
        return listFilter.apply(agents, keeping: Set(store.hooks.pending.map(\.event.agentKey)))
    }

    func listSections(_ projects: [ProjectNode]) -> [ProjectNode] {
        ListFilter.sections(projects, grouped: rows.groupByProject, order: rows.sort)
    }
}

extension Store {
    func passHiddenRequests() {
        let names = ProjectNames()
        let passed = settings.listFilter.requestsToPass(hooks.pending, project: names.name(for:), answerFromNotch: settings.answerFromNotch,
                                                             agents: agents)
        for ask in passed { decide(ask, .pass) }
    }
}
