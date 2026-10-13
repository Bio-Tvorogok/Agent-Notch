import AppKit
import NotchCore

/// Flags: `--fixture <scene>` shows a made-up scene instead of the real logs, `--cramped` forces the one-summary wing,
/// `--open-list` opens the list on start, `--snapshot <dir>` writes PNGs of every scene and quits,
/// `--install-hooks` / `--uninstall-hooks` edit the Claude Code and Codex hook files and quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var notch: NotchController?
    var watcher: MenuWatcher?
    var keys: HotKeys?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot-themes"), i + 1 < args.count {
            exit(Snapshot.runThemes(into: args[i + 1]) ? 0 : 1)
        }
        if let i = args.firstIndex(of: "--snapshot-card"), i + 1 < args.count {
            exit(Snapshot.runCard(to: args[i + 1]) ? 0 : 1)
        }
        if let i = args.firstIndex(of: "--snapshot-usage"), i + 1 < args.count {
            exit(Snapshot.runUsage(to: args[i + 1]) ? 0 : 1)
        }
        if let i = args.firstIndex(of: "--snapshot-settings"), i + 1 < args.count {
            exit(Snapshot.runSettings(to: args[i + 1]) ? 0 : 1)
        }
        if let i = args.firstIndex(of: "--snapshot-marks"), i + 1 < args.count {
            exit(Snapshot.runMarks(to: args[i + 1]) ? 0 : 1)
        }
        if let i = args.firstIndex(of: "--snapshot-live"), i + 1 < args.count {
            Task { await Snapshot.runLive(to: args[i + 1]); NSApp.terminate(nil) }
            return
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.run(into: args[i + 1])
            NSApp.terminate(nil)
            return
        }
        if args.contains("--install-hooks") || args.contains("--uninstall-hooks") {
            exit(Self.editHooks(install: args.contains("--install-hooks")))
        }
        let inst = HookInstaller()
        if inst.isInstalled(.claude) || inst.isInstalled(.codex) { try? inst.placeHelper(from: AppActions.bundledHelper, app: AppActions.appExecutable) }
        if let i = args.firstIndex(of: "--fixture"), i + 1 < args.count, let scene = Fixtures.agents(args[i + 1]) {
            store.useFixture(scene, asks: Fixtures.asks(args[i + 1]))
        } else {
            store.start()
        }
        store.forceCramped = args.contains("--cramped")
        KeepAwakeModel.shared.startMonitoring()
        let notch = NotchController(store: store)
        self.notch = notch
        store.onNewAsk = { [weak notch] in
            if AppSettings.shared.behavior.openOnRequest { notch?.showList() }
        }
        // A hotkey that cannot answer yet opens the list, so the request gets seen first.
        let answer: @MainActor (HookDecision) -> Void = { [weak self, weak notch] d in
            guard let self, !self.store.hooks.pending.isEmpty, !self.store.decideByHotkey(d) else { return }
            notch?.showList()
        }
        keys = HotKeys(allow: { answer(.allow) }, deny: { answer(.deny) }, list: { [weak notch] in notch?.toggleList() })
        watcher = MenuWatcher(store: store) { [weak notch] in notch?.fullWingLeft }
        if args.contains("--open-list") { notch.showList() }
    }

    private static func editHooks(install: Bool) -> Int32 {
        let inst = HookInstaller()
        do {
            if install { try inst.placeHelper(from: AppActions.bundledHelper, app: AppActions.appExecutable) }
            for v in [Vendor.claude, .codex] {
                try install ? inst.install(v) : inst.uninstall(v)
                print("\(v.rawValue): \(inst.isInstalled(v) ? "installed" : "removed") in \(inst.file(v).path)")
            }
            if install { print(AppActions.codexTrustNote) }
            return 0
        } catch {
            print("hooks: \(error.localizedDescription)")
            return 1
        }
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
