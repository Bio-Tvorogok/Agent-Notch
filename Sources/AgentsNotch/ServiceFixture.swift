import Foundation
import NotchCore

/// A made-up service for snapshots: Tests/Fixtures/Services/chedrik.json in a temporary folder with a stub program,
/// and a status file and log in a temporary home. Secrets stay in memory; nothing reaches the Keychain or real preferences.
@MainActor
struct ServiceFixture {
    let model: ServicesModel
    let manifest: ServiceManifest
    private let folder: URL

    static let providers = #"""
    [{"id":"claude","name":"Claude Code","path":"/Users/me/.local/bin/claude","version":"2.1.311 (Claude Code)","loggedIn":true,"method":"claude.ai (max)"},
     {"id":"codex","name":"Codex","path":"/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex","version":"codex-cli 0.163.0","loggedIn":false,"login":"ops/gosha codex-login"}]
    """#

    /// Made up; assembled at run time so secret scanners do not take it for a real token.
    static let fakeToken = ["MTA4NzQ1Njc4OTAxMjM0NTY3OA", "GaBcDe", "abcdefghijklmnopqrstuvwxyz0123"].joined(separator: ".")

    /// nil when run outside the repository, where the fixture manifest is missing.
    init?(defaults: UserDefaults, running: Bool = true) {
        let files = FileManager.default
        folder = files.temporaryDirectory.appendingPathComponent("notch-snapshot-service-" + UUID().uuidString)
        let root = folder.appendingPathComponent("gosha"), home = folder.appendingPathComponent("home")
        let data = home.appendingPathComponent(".chedrik")
        do {
            for dir in [root.appendingPathComponent("ops"), data.appendingPathComponent("run"), data.appendingPathComponent("logs")] {
                try files.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            for dir in [folder, root, root.appendingPathComponent("ops")] { chmod(dir.path, 0o755) }
            let manifestFile = root.appendingPathComponent("ops/agent-notch.json")
            try files.copyItem(at: URL(fileURLWithPath: "Tests/Fixtures/Services/chedrik.json"), to: manifestFile)
            chmod(manifestFile.path, 0o644)
            let program = root.appendingPathComponent("ops/gosha")
            try "#!/bin/sh\nexit 0\n".write(to: program, atomically: true, encoding: .utf8)
            chmod(program.path, 0o755)
            let stamp = ISO8601DateFormatter().string(from: Date())
            let status = running ? """
            {"pid":\(getpid()),"startedAt":"\(stamp)","updatedAt":"\(stamp)",
             "discord":{"online":true,"servers":[{"id":"1","name":"AqulaSoft","answers":true},{"id":"2","name":"Lab","answers":false}]},
             "voice":{"enabled":true,"in":{"channelId":"9","channelName":"public","guildId":"1","guildName":"AqulaSoft"}},
             "brain":{"provider":"claude","alive":true},
             "tts":{"ok":true,"url":"http://192.168.1.130:3900"},"stt":{"ok":true,"url":"http://127.0.0.1:8178"},"lastError":null}
            """ : """
            {"pid":999999,"startedAt":"2026-10-30T10:00:00Z","updatedAt":"2026-10-30T11:20:00Z",
             "discord":{"online":false,"servers":[]},"voice":{"enabled":true,"in":null},"brain":{"provider":"claude","alive":false},
             "tts":{"ok":false,"url":"http://192.168.1.130:3900"},"stt":{"ok":null,"url":"http://127.0.0.1:8178"},
             "lastError":"VoiceStudio: connect ECONNREFUSED 192.168.1.130:3900 (api_key=vs-live-123456)"}
            """
            try status.write(to: data.appendingPathComponent("run/status.json"), atomically: true, encoding: .utf8)
            let log = [
                "2026-10-30 10:00:01 discord: logged in as Гоша#4242 with \(Self.fakeToken)",
                "2026-10-30 10:00:02 voice: joined public (AqulaSoft)",
                "2026-10-30 10:00:03 tts: VoiceStudio http://192.168.1.130:3900 answers in 64 ms",
                "2026-10-30 10:00:04 stt: whisper-server http://127.0.0.1:8178 ready",
                "2026-10-30 10:02:10 brain: claude.ai (max) session started",
            ]
            try (log.joined(separator: "\n") + "\n").write(to: data.appendingPathComponent("logs/chedrik.log"), atomically: true, encoding: .utf8)
        } catch { return nil }

        let model = ServicesModel(defaults: defaults, secrets: MemorySecretStore(), home: home.path)
        model.add(folder: root.path)
        guard let pending = model.pending else { return nil }
        model.approve(pending.manifest)
        manifest = pending.manifest
        let id = manifest.id
        for (key, value) in ["OWNER_DISCORD_ID": "301234567890123456", "VOICE_CHANNEL_ID": "1101234567890123456",
                             "VOICESTUDIO_URL": "http://192.168.1.130:3900"] {
            if let field = manifest.field(key) { model.setValue(id, field, value) }
        }
        model.setSecret(id, "DISCORD_BOT_TOKEN", Self.fakeToken)
        if let brain = manifest.field("BRAIN_PROVIDER"), let options = brain.options {
            var choices = ServiceOption.parse(Data(Self.providers.utf8), options: options) ?? []
            if !running { choices = choices.map { ServiceOption(value: $0.value, label: $0.label, enabled: false, login: $0.login) } }
            model.seed(id, choices: [brain.key: choices])
            if running, let claude = choices.first { model.choose(id, brain, claude) }
        }
        model.seed(id, check: running
            ? ServiceCheck(ok: true, url: "http://192.168.1.130:3900", healthMs: 64, latencyMs: 5100)
            : ServiceCheck(ok: false, url: "http://192.168.1.130:3900", error: "VoiceStudio does not answer: connect ECONNREFUSED"))
        model.refresh()
        self.model = model
    }

    func remove() { try? FileManager.default.removeItem(at: folder) }
}
