import Foundation
import Darwin

// Only the privileged OS boundary is replaced. No test changes this Mac's power settings.
@MainActor
final class TestSleepSystem: KeepAwakeSystem {
    var state = false
    var cannotRead = false
    var ignoresWrite = false
    var writeError: Error?
    var writes: [Bool] = []
    var pending: CheckedContinuation<Void, Never>?
    var holdsWrite = false
    var permissionInstalled = false
    var effectivePermission = true
    var ignoresPermissionWrite = false
    var permissionError: Error?
    var staleReadsAfterWrite = 0
    private var staleReadsLeft = 0
    private var pendingState: Bool?

    func configurePasswordless(_ enabled: Bool) async throws {
        if let permissionError { throw permissionError }
        if !ignoresPermissionWrite { permissionInstalled = enabled }
    }

    func verifyPasswordless() async throws -> Bool { effectivePermission }

    func read() throws -> Bool {
        if cannotRead { throw KeepAwakeFailure.unavailable }
        if let pendingState {
            if staleReadsLeft > 0 { staleReadsLeft -= 1 }
            else { state = pendingState; self.pendingState = nil }
        }
        return state
    }

    func set(_ enabled: Bool) async throws -> Bool {
        writes.append(enabled)
        if holdsWrite { await withCheckedContinuation { pending = $0 } }
        if let writeError { throw writeError }
        if !ignoresWrite {
            if staleReadsAfterWrite > 0 {
                pendingState = enabled
                staleReadsLeft = staleReadsAfterWrite
            } else { state = enabled }
        }
        return permissionInstalled && effectivePermission
    }
}

@MainActor
final class TestSleepCommands: SleepCommandRunning {
    var commands: [(String, [String])] = []
    var results: [SleepCommandResult] = []

    func run(_ executable: String, arguments: [String]) async throws -> SleepCommandResult {
        commands.append((executable, arguments))
        guard !results.isEmpty else { fatalError("unexpected command") }
        return results.removeFirst()
    }
}

@main
struct KeepAwakeChecks {
    @MainActor static func main() async {
        var failures = 0
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures += 1; print("FAIL: " + message) }
        }

        let system = TestSleepSystem()
        system.state = true
        let model = KeepAwakeModel(system: system)
        expect(model.enabled == true, "startup must read the OS, including a previously enabled mode")
        await model.setEnabled(false)
        expect(model.enabled == false && system.writes == [false] && model.error == nil,
               "switching off must write and read back the real system state")
        await model.setEnabled(true)
        expect(model.enabled == true && system.writes == [false, true] && !model.busy,
               "switching on must write and confirm the real system state")

        let delayedSystem = TestSleepSystem()
        delayedSystem.staleReadsAfterWrite = 3
        let delayedModel = KeepAwakeModel(system: delayedSystem)
        await delayedModel.setEnabled(true)
        expect(delayedModel.enabled == true && delayedModel.error == nil && !delayedModel.busy && delayedSystem.writes == [true],
               "a successful write must wait for delayed OS readback without an error or a second command")

        system.writeError = KeepAwakeFailure.cancelled
        await model.setEnabled(false)
        expect(model.enabled == true && model.error == nil && !model.busy,
               "cancelling authentication must leave an enabled switch on without an error alert")
        system.state = false
        model.refresh()
        await model.setEnabled(true)
        expect(model.enabled == false && model.error == nil,
               "cancelling authentication must leave a disabled switch off")

        system.writeError = nil
        system.ignoresWrite = true
        await model.setEnabled(true)
        expect(model.enabled == false && model.error != nil,
               "a successful command that did not apply must never light up the switch")

        system.ignoresWrite = false
        system.cannotRead = true
        model.refresh()
        let count = system.writes.count
        await model.setEnabled(true)
        expect(model.enabled == nil && system.writes.count == count,
               "an unreadable OS state must be unknown and must block changes")

        system.cannotRead = false
        system.state = true
        model.refresh()
        expect(model.enabled == true, "external changes must be reflected on refresh")
        system.writeError = KeepAwakeFailure.authorization("denied")
        await model.setEnabled(false)
        expect(model.enabled == true && model.error != nil && !model.busy,
               "authorization failures must retain the actual state and expose the error")

        system.writeError = nil
        system.holdsWrite = true
        let change = Task { await model.setEnabled(false) }
        while system.pending == nil { await Task.yield() }
        expect(model.busy && model.enabled == true, "the switch must retain confirmed state while awaiting authentication")
        let beforeDuplicate = system.writes.count
        await model.setEnabled(false)
        expect(system.writes.count == beforeDuplicate, "a second click must not create another administrator prompt")
        system.cannotRead = true
        system.pending?.resume()
        await change.value
        expect(model.enabled == nil && model.error != nil && !model.busy,
               "failure to verify after a write must show unknown state rather than success")

        system.cannotRead = false
        system.holdsWrite = false
        model.refresh()
        await model.configurePasswordless(true)
        expect(model.passwordless == true && model.permissionInstalled && system.state == false && model.permissionError == nil,
               "permission setup must read back permission status without changing sleep mode")
        system.permissionError = KeepAwakeFailure.cancelled
        await model.configurePasswordless(false)
        expect(model.permissionInstalled && model.permissionError == nil && !model.busy,
               "cancelled permission removal must retain the installed permission")
        system.permissionError = nil
        system.ignoresPermissionWrite = true
        await model.configurePasswordless(false)
        expect(model.permissionInstalled && model.permissionError != nil,
               "permission removal must not be reported as successful unless the OS confirms it")
        system.ignoresPermissionWrite = false
        await model.configurePasswordless(false)
        expect(!model.permissionInstalled && model.permissionError == nil,
               "permission removal must return the setting to password-required mode")

        system.effectivePermission = false
        await model.configurePasswordless(true)
        expect(model.permissionInstalled && model.passwordless == false && model.permissionError != nil,
               "a PASSWD override must not be reported as effective passwordless access")
        await model.configurePasswordless(false)
        expect(!model.permissionInstalled && model.permissionError == nil,
               "an installed but ineffective permission must remain removable")

        let commands = TestSleepCommands()
        commands.results = [SleepCommandResult(status: 0, output: "")]
        let mac = MacSleepSystem(commands: commands, permissionInstalled: { false })
        _ = try! await mac.set(true)
        expect(commands.commands.count == 1 && commands.commands[0].0 == "/usr/bin/sudo" &&
               commands.commands[0].1 == ["-k", "-n", "--", "/usr/bin/pmset", "disablesleep", "1"],
               "passwordless switching must use only the exact sleep command and ignore cached credentials")
        commands.commands = []
        commands.results = [SleepCommandResult(status: 1, output: "password required"),
                            SleepCommandResult(status: 0, output: "")]
        _ = try! await mac.set(false)
        expect(commands.commands.count == 2 && commands.commands[1].0 == "/usr/bin/osascript" &&
               commands.commands[1].1 == ["-e", "do shell script \"/usr/bin/pmset disablesleep 0\" with administrator privileges"],
               "without passwordless rights the switch must still support the native administrator prompt")

        commands.commands = []
        commands.results = [SleepCommandResult(status: 1, output: "password required")]
        let overridden = MacSleepSystem(commands: commands, permissionInstalled: { true })
        do { _ = try await overridden.set(true); expect(false, "an ineffective managed permission must fail visibly") }
        catch {
            expect(commands.commands.count == 1, "an ineffective managed rule must not silently fall back to another password prompt")
        }

        var metadata = stat()
        metadata.st_mode = mode_t(S_IFREG) | 0o440
        metadata.st_uid = 0
        metadata.st_gid = 0
        metadata.st_size = 128
        expect(SleepPermissionPolicy.isManagedFile(metadata), "a managed rule must remain discoverable for removal")
        metadata.st_size = 256
        expect(SleepPermissionPolicy.isManagedFile(metadata), "appending a comment must not hide a managed permission")
        metadata.st_mode = mode_t(S_IFLNK) | 0o440
        expect(!SleepPermissionPolicy.isManagedFile(metadata), "a symbolic link must never count as a managed permission")
        metadata.st_mode = mode_t(S_IFREG) | 0o666
        expect(!SleepPermissionPolicy.isManagedFile(metadata), "a writable policy must never be trusted")

        do {
            _ = try SleepPermissionPolicy(uid: 0)
            expect(false, "a root user must not receive a persistent passwordless rule")
        } catch {}
        let policy = try! SleepPermissionPolicy(uid: 501)
        expect(policy.rule == "# Agent Notch keep-awake permission\n#501 ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1\n",
               "the emitted sudoers policy must grant exactly two arguments for one user, with no wildcards")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("agent-notch-rule-\(UUID().uuidString)")
        do {
            try policy.rule.write(to: file, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: file) }
            let validation = try await SleepProcessCommands().run("/usr/sbin/visudo", arguments: ["-cf", file.path])
            expect(validation.status == 0, "the exact generated policy must pass the real sudoers parser")
            try (policy.rule + "\n# Added by the administrator\n").write(to: file, atomically: true, encoding: .utf8)
            let normalized = try await SleepProcessCommands().run("/usr/bin/awk", arguments: [SleepPermissionPolicy.ruleLines, file.path])
            expect(normalized.status == 0 && normalized.output == "#501 ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1",
                   "removal comparison must ignore comments while preserving the numeric UID grant")
            try (policy.rule + "#include /private/etc/another-policy\n#includedir /private/etc/another-directory\n").write(to: file, atomically: true, encoding: .utf8)
            let directives = try await SleepProcessCommands().run("/usr/bin/awk", arguments: [SleepPermissionPolicy.ruleLines, file.path])
            expect(directives.status == 0 && directives.output == "#501 ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1\n#include /private/etc/another-policy\n#includedir /private/etc/another-directory",
                   "active sudoers include directives must survive comparison so another policy is never silently removed")
            for install in [false, true] {
                let syntax = try await SleepProcessCommands().run("/bin/sh", arguments: ["-n", "-c", policy.script(install: install)])
                expect(syntax.status == 0, "the generated install/removal script must pass the real shell parser")
            }
        } catch { expect(false, "could not validate generated sudoers policy: \(error)") }

        print(failures == 0 ? "OK keep-awake checks" : "\(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
