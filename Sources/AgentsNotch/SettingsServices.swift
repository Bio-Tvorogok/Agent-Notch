import AppKit
import SwiftUI
import NotchCore

/// Settings → Services: local programs that ship an Agent Notch manifest. The section knows nothing about any one service;
/// the manifest gives the form, the commands and the files, and the status file's shape gives the rows.
struct SettingsServices: View {
    @ObservedObject var model: ServicesModel

    var body: some View {
        Form {
            Section {
                if model.entries.count > 1 {
                    Picker(ServiceText.service, selection: $model.selected) {
                        ForEach(model.entries, id: \.id) { entry in Text(model.shown(entry.id)?.name ?? entry.id).tag(Optional(entry.id)) }
                    }
                }
                LabeledContent {
                    Button(ServiceText.add) { pickFolder() }
                } label: { SettingsLabel(ServiceText.addTitle, hint: ServiceText.addHint) }
            } footer: {
                if model.entries.isEmpty {
                    Text(ServiceText.empty).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let id = model.selected, model.entry(id) != nil {
                ServiceSections(model: model, id: id)
            }
        }
        .sheet(item: $model.pending) { pending in
            ServiceApprovalSheet(pending: pending, onApprove: { model.approve(pending.manifest) }, onCancel: { model.pending = nil })
        }
        .alert(ServiceText.failed, isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } })) {
            Button("OK") { model.problem = nil }
        } message: { Text(model.problem ?? "") }
        .onAppear { model.watch() }
        .onDisappear { model.unwatch() }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = ServiceText.choose
        panel.message = ServiceText.addHint
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.add(folder: url.path)
    }
}

/// Everything about the selected service, by the state of its manifest.
private struct ServiceSections: View {
    @ObservedObject var model: ServicesModel
    let id: String

    var body: some View {
        switch model.manifests[id] {
        case let .ok(manifest):
            ServiceStatusSection(model: model, manifest: manifest)
            if manifest.command("check-pc") != nil { ServiceCheckSection(model: model, manifest: manifest) }
            if !manifest.customCommands.isEmpty { ServiceCommandsSection(model: model, manifest: manifest) }
            if !manifest.fields.isEmpty {
                Section {
                    ForEach(manifest.fields, id: \.key) { field in
                        if model.visible(manifest.id, field) { ServiceFieldRow(model: model, manifest: manifest, field: field) }
                    }
                } header: { Text(ServiceText.settings) } footer: {
                    Text(ServiceText.formHelp).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !manifest.logs.isEmpty { ServiceLogsSection(model: model, manifest: manifest) }
            ServiceOptionsSection(model: model, id: id, name: manifest.name)
        case let .changed(manifest):
            Section(manifest.name) {
                Label(ServiceText.changedTitle(manifest.name), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(ServiceText.changedHelp).font(.caption).foregroundStyle(.secondary)
                Button(ServiceText.review) { model.review(id) }
            }
            ServiceOptionsSection(model: model, id: id, name: manifest.name)
        case let .failed(message):
            Section(id) {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(model.entry(id)?.folder ?? "").font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            ServiceOptionsSection(model: model, id: id, name: id)
        case nil:
            EmptyView()
        }
    }
}

private struct ServiceStatusSection: View {
    @ObservedObject var model: ServicesModel
    let manifest: ServiceManifest

    var body: some View {
        let id = manifest.id
        let running = model.running[id] ?? false
        let status = model.status[id]
        Section {
            HStack(spacing: 8) {
                Circle().fill(running ? Color.green : Color.secondary.opacity(0.5)).frame(width: 9, height: 9)
                Text(running ? ServiceText.running : ServiceText.stopped).fontWeight(.medium)
                if running, let started = status?.startedAt {
                    Text("\(ServiceText.since) \(started.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                }
                Spacer()
                if let busy = model.busy[id], !busy.isEmpty {
                    ProgressView().controlSize(.small)
                    Text(busy.sorted().map { manifest.command($0).map(ServiceText.command) ?? $0 }.joined(separator: ", "))
                        .foregroundStyle(.secondary).font(.caption)
                }
            }
            HStack(spacing: 8) {
                ForEach(["start", "stop", "restart", "status"], id: \.self) { name in
                    if let command = manifest.command(name) {
                        Button(ServiceText.command(command)) { model.run(id, name) }
                            .disabled(model.inFlight(id, name) || ServicesModel.lifecycle.contains(name) && model.lifecycleBusy(id)
                                      || name == "start" && running || name == "stop" && !running
                                      || ServicesModel.needsComplete(command) && !model.problems(id, for: command).isEmpty)
                    }
                }
                Spacer()
            }
            if running, let status {
                ForEach(status.rows, id: \.key) { row in
                    LabeledContent(ServiceText.row(row.key)) { ServiceRowValue(value: row.value) }
                }
            }
            if let error = model.lastError[id] {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ServiceText.lastError).font(.caption).foregroundStyle(.secondary)
                    Text(error).font(.caption.monospaced()).foregroundStyle(.red)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let output = model.outputs[id] {
                VStack(alignment: .leading, spacing: 4) {
                    Text(manifest.command(output.command).map(ServiceText.command) ?? output.command).font(.caption).foregroundStyle(.secondary)
                    Text(output.text).font(.system(size: 11, design: .monospaced)).foregroundStyle(output.ok ? Color.primary : Color.red)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        .padding(8).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        } header: { Text(manifest.name) } footer: {
            if let description = manifest.description {
                Text(description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ServiceRowValue: View {
    let value: ServiceStatus.Value

    var body: some View {
        switch value {
        case let .online(online, servers):
            VStack(alignment: .trailing, spacing: 2) {
                mark(online, online ? ServiceText.online : ServiceText.offline)
                ForEach(Array(servers.enumerated()), id: \.offset) { _, server in
                    Text(server.answers == false ? "\(server.name) · \(ServiceText.noAnswer)" : server.name)
                        .font(.caption).foregroundStyle(server.answers == false ? Color.orange : Color.secondary)
                }
            }
        case let .place(enabled, at):
            if !enabled { Text(ServiceText.voiceOff).foregroundStyle(.secondary) }
            else if let at { mark(true, at) }
            else { Text(ServiceText.outOfVoice).foregroundStyle(.secondary) }
        case let .provider(provider, alive):
            HStack(spacing: 6) {
                Text(provider)
                if let alive { mark(alive, alive ? ServiceText.alive : ServiceText.notAlive) }
            }
        case let .check(ok, url):
            VStack(alignment: .trailing, spacing: 2) {
                if let ok { mark(ok, ok ? ServiceText.ok : ServiceText.notOk) } else { Text(ServiceText.unknown).foregroundStyle(.secondary) }
                if let url { Text(url).font(.caption.monospaced()).foregroundStyle(.secondary) }
            }
        }
    }

    private func mark(_ ok: Bool, _ text: String) -> some View {
        Label { Text(text) } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? Color.green : Color.red)
        }
    }
}

private struct ServiceCheckSection: View {
    @ObservedObject var model: ServicesModel
    let manifest: ServiceManifest

    var body: some View {
        let id = manifest.id
        let command = manifest.command("check-pc")!
        Section(ServiceText.check) {
            HStack {
                Button(ServiceText.command(command)) { model.run(id, "check-pc") }.disabled(model.inFlight(id, "check-pc"))
                if model.inFlight(id, "check-pc") { ProgressView().controlSize(.small) }
                Spacer()
            }
            if let check = model.checks[id] {
                VStack(alignment: .leading, spacing: 3) {
                    Label { Text(check.ok ? ServiceText.checkOk : ServiceText.checkFailed).fontWeight(.medium) } icon: {
                        Image(systemName: check.ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(check.ok ? Color.green : Color.red)
                    }
                    let timings = [check.healthMs.map(ServiceText.health), check.latencyMs.map(ServiceText.latency)].compactMap { $0 }
                    if !timings.isEmpty { Text(timings.joined(separator: " · ")).foregroundStyle(.secondary) }
                    if let url = check.url { Text(url).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    if let error = check.error {
                        Text(error).font(.caption.monospaced()).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// The service's own commands, such as signing in: one button each, with its timeout, exit code and masked output.
private struct ServiceCommandsSection: View {
    @ObservedObject var model: ServicesModel
    let manifest: ServiceManifest

    var body: some View {
        let id = manifest.id
        Section(ServiceText.otherCommands) {
            ForEach(manifest.customCommands, id: \.name) { command in
                HStack(spacing: 8) {
                    Button(ServiceText.command(command)) { model.run(id, command.name) }
                        .disabled(model.inFlight(id, command.name)
                                  || ServicesModel.needsComplete(command) && !model.problems(id, for: command).isEmpty)
                        .help(ServiceText.commandLine(command.run))
                    if model.inFlight(id, command.name) { ProgressView().controlSize(.small) }
                    Spacer()
                    Text(command.name).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ServiceFieldRow: View {
    @ObservedObject var model: ServicesModel
    let manifest: ServiceManifest
    let field: ServiceManifest.Field
    @State private var draft = ""
    @State private var replacing = false

    var body: some View {
        let id = manifest.id
        VStack(alignment: .leading, spacing: 4) {
            switch field.kind {
            case .string:
                TextField(text: Binding(get: { model.entry(id)?.values[field.key] ?? "" }, set: { model.setValue(id, field, $0) }),
                          prompt: Text(field.placeholder ?? field.defaultValue ?? "")) { Text(field.label) }
            case .secret:
                if model.filledSecrets[id]?.contains(field.key) == true && !replacing {
                    LabeledContent(field.label) {
                        HStack {
                            Label(ServiceText.savedSecret, systemImage: "key.fill").foregroundStyle(.secondary).fixedSize()
                            Button(ServiceText.replace) { replacing = true }
                            Button(ServiceText.delete) { model.setSecret(id, field.key, nil) }
                        }.controlSize(.small)
                    }
                } else {
                    LabeledContent(field.label) {
                        HStack {
                            SecureField(field.label, text: $draft, prompt: Text(field.placeholder ?? ServiceText.pasteSecret)).labelsHidden()
                                .frame(minWidth: 180, maxWidth: 260).onSubmit(saveSecret)
                            Button(ServiceText.save, action: saveSecret).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            case .select:
                if field.options?.command != nil { ServiceChoicePicker(model: model, manifest: manifest, field: field) }
                else {
                    Picker(field.label, selection: Binding(get: { model.value(id, field) }, set: { model.setValue(id, field, $0) })) {
                        ForEach(field.options?.values ?? [], id: \.value) { choice in Text(choice.label).tag(choice.value) }
                    }
                }
            }
            if let help = field.help { Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            // A command-backed select says «not signed in» in the picker itself.
            if let problem = model.problems(id)[field.key], problem != .choice || field.options?.command == nil {
                Text(ServiceText.problem(problem)).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func saveSecret() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        model.setSecret(manifest.id, field.key, value)
        draft = ""
        replacing = false
    }
}

/// A select whose choices a command prints, such as the CLIs a service can use as its brain.
private struct ServiceChoicePicker: View {
    @ObservedObject var model: ServicesModel
    let manifest: ServiceManifest
    let field: ServiceManifest.Field

    var body: some View {
        let id = manifest.id
        let state = model.choices[id]?[field.key]
        let current = model.value(id, field)
        let options: [ServiceOption] = if case let .loaded(list) = state { list } else { [] }
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Picker(field.label, selection: Binding(get: { current }, set: { value in
                    if let option = options.first(where: { $0.value == value && $0.enabled }) { model.choose(id, field, option) }
                })) {
                    if !options.contains(where: { $0.value == current }) { Text(current.isEmpty ? "—" : current).tag(current) }
                    ForEach(options) { option in
                        Text(option.enabled ? option.label : "\(option.label) — \(ServiceText.notSignedIn)").tag(option.value).disabled(!option.enabled)
                    }
                }
                if state == .loading { ProgressView().controlSize(.small) }
                Button(ServiceText.refresh) { model.loadChoices(id, field) }.disabled(state == .loading)
            }
            if let chosen = options.first(where: { $0.value == current }), chosen.enabled {
                let detail = [chosen.detail, chosen.version].compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            if case let .failed(message) = state { Text(message).font(.caption).foregroundStyle(.orange) }
            if case .loaded = state, !options.contains(where: \.enabled) {
                Text(ServiceText.noChoice).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if case .loaded = state {
                ForEach(options.filter { !$0.enabled }) { option in
                    if let name = field.options?.loginCommand[option.value], let command = manifest.command(name) {
                        // A manifest command signs in: a button instead of instructions.
                        HStack(spacing: 8) {
                            Text("\(option.label) — \(ServiceText.notSignedIn)").font(.caption).foregroundStyle(.secondary)
                            Button(ServiceText.signInButton) { model.run(id, name) }.controlSize(.small)
                                .disabled(model.inFlight(id, name)).help(ServiceText.commandLine(command.run))
                            if model.inFlight(id, name) { ProgressView().controlSize(.small) }
                        }
                    } else {
                        Text(option.login.map { ServiceText.login(option.label, $0, (manifest.root as NSString).abbreviatingWithTildeInPath) }
                             ?? ServiceText.signIn(option.label))
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onAppear { if state == nil { model.loadChoices(id, field) } }
    }
}

private struct ServiceLogsSection: View {
    @ObservedObject var model: ServicesModel
    let manifest: ServiceManifest

    var body: some View {
        let id = manifest.id
        let lines = model.logs[id] ?? []
        Section {
            HStack {
                if manifest.logs.count > 1 {
                    Picker("", selection: Binding(get: { model.logName[id] ?? manifest.logs[0].name },
                                                  set: { model.logName[id] = $0; model.refreshLogs() })) {
                        ForEach(manifest.logs, id: \.name) { log in Text(log.name).tag(log.name) }
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                Spacer()
                Button(ServiceText.reveal) { model.revealLog(id) }
            }
            ScrollView {
                Text(lines.isEmpty ? ServiceText.noLog : lines.joined(separator: "\n"))
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(lines.isEmpty ? Color.secondary : Color.primary)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            .defaultScrollAnchor(.bottom)
            .frame(height: 170)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        } header: { Text(ServiceText.logs) } footer: {
            Text(ServiceText.masked).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ServiceOptionsSection: View {
    @ObservedObject var model: ServicesModel
    let id: String
    let name: String
    @State private var confirmRemove = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { model.entry(id)?.launchWithApp ?? false }, set: { model.setLaunchWithApp(id, $0) })) {
                SettingsLabel(ServiceText.launchWithApp, hint: ServiceText.launchHelp)
            }.toggleStyle(.switch)
            LabeledContent {
                Button(ServiceText.remove, role: .destructive) { confirmRemove = true }
            } label: {
                Text(((model.entry(id)?.folder ?? "") as NSString).abbreviatingWithTildeInPath)
                    .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .confirmationDialog(ServiceText.removeConfirm(name), isPresented: $confirmRemove, titleVisibility: .visible) {
            Button(ServiceText.removeButton, role: .destructive) { model.remove(id) }
            Button(SettingsText.cancel, role: .cancel) {}
        } message: { Text(ServiceText.removeHelp) }
    }
}

/// What a manifest would run, shown before the service is added or after its manifest changed.
struct ServiceApprovalSheet: View {
    let pending: ServicesModel.Pending
    let onApprove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        let manifest = pending.manifest
        VStack(alignment: .leading, spacing: 12) {
            Text(pending.changed ? ServiceText.changedTitle(manifest.name) : ServiceText.addService(manifest.name)).font(.headline)
            ScrollView {
                details(manifest).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 560)
            Text(ServiceText.approveHelp).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(SettingsText.cancel, role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(pending.changed ? ServiceText.approveChanged : ServiceText.approve, action: onApprove)
            }
        }
        .padding(20).frame(width: 600)
    }

    @ViewBuilder private func details(_ manifest: ServiceManifest) -> some View {
        let now = manifest.commandSummary
        VStack(alignment: .leading, spacing: 12) {
            if let description = manifest.description { Text(description).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if pending.changed { Text(ServiceText.changedHelp).foregroundStyle(.orange) }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow { Text(ServiceText.idLabel).foregroundStyle(.secondary); Text(manifest.id).font(.caption.monospaced()) }
                GridRow { Text(ServiceText.folder).foregroundStyle(.secondary); Text(Self.short(manifest.root)).font(.caption.monospaced()).textSelection(.enabled) }
                GridRow { Text(ServiceText.runsIn).foregroundStyle(.secondary); Text(Self.short(manifest.cwd)).font(.caption.monospaced()).textSelection(.enabled) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(ServiceText.commands).font(.subheadline.weight(.semibold))
                ForEach(manifest.commands, id: \.name) { command in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(command.name).font(.caption.weight(.medium)).frame(width: 74, alignment: .leading)
                            Text(ServiceText.commandLine(command.run)).font(.caption.monospaced()).textSelection(.enabled)
                            if let previous = pending.previous {
                                if previous[command.name] == nil { badge(ServiceText.added) }
                                else if previous[command.name] != now[command.name] { badge(ServiceText.changedMark) }
                            }
                        }
                        // A link or a «..» inside the folder runs something else than the name says: show what.
                        if command.executable != manifest.cwd + "/" + command.run[0] {
                            Text("→ " + command.executable.dropFirst(manifest.root.count + 1))
                                .font(.caption2.monospaced()).foregroundStyle(.secondary).padding(.leading, 82)
                        }
                        if let label = command.label {
                            Text(ServiceText.buttonLabel(label)).font(.caption2).foregroundStyle(.secondary).padding(.leading, 82)
                        }
                        if command.config, let fd = manifest.configFD {
                            Text(ServiceText.getsSettings(fd, needs: command.needs)).font(.caption2).foregroundStyle(.secondary)
                                .padding(.leading, 82).fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(Self.signIns(manifest, command.name), id: \.self) { line in
                            Text(line).font(.caption2).foregroundStyle(.secondary).padding(.leading, 82)
                        }
                    }
                }
                ForEach((pending.previous ?? [:]).keys.filter { now[$0] == nil }.sorted(), id: \.self) { name in
                    HStack(spacing: 8) {
                        Text(name).font(.caption.weight(.medium)).strikethrough().frame(width: 74, alignment: .leading)
                        badge(ServiceText.removed)
                    }
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            if manifest.status != nil || !manifest.logs.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ServiceText.reads).font(.subheadline.weight(.semibold))
                    ForEach([manifest.status].compactMap { $0 } + manifest.logs.map(\.path), id: \.self) { path in
                        Text(Self.short(path)).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            Text(ServiceText.fields(manifest.fields.count, secrets: manifest.fields.filter { $0.kind == .secret }.count)).font(.caption)
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 1).background(Color.orange, in: Capsule())
    }

    static func short(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

    /// Which choices a command signs in to, so the «Sign in» buttons it will stand behind are on the sheet too.
    static func signIns(_ manifest: ServiceManifest, _ name: String) -> [String] {
        manifest.fields.flatMap { field in
            (field.options?.loginCommand ?? [:]).filter { $0.value == name }.keys.sorted().map { ServiceText.signsIn($0, field.label) }
        }
    }
}
