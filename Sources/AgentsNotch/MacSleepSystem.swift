import Foundation
import IOKit

struct MacSleepSystem: KeepAwakeSystem {
    private let commands: any SleepCommandRunning
    private let permission = try? SleepPermissionPolicy(uid: getuid())
    private let hasManagedPermission: () -> Bool

    init(commands: (any SleepCommandRunning)? = nil, permissionInstalled: (() -> Bool)? = nil) {
        self.commands = commands ?? SleepProcessCommands()
        hasManagedPermission = permissionInstalled ?? { (try? SleepPermissionPolicy(uid: getuid()))?.installed == true }
    }

    var permissionInstalled: Bool { hasManagedPermission() }

    func read() throws -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else { throw KeepAwakeFailure.unavailable }
        defer { IOObjectRelease(root) }
        guard let value = IORegistryEntryCreateCFProperty(root, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              CFGetTypeID(value) == CFBooleanGetTypeID(), let enabled = value as? Bool else {
            throw KeepAwakeFailure.unavailable
        }
        return enabled
    }

    func set(_ enabled: Bool) async throws -> Bool {
        let value = enabled ? "1" : "0"
        // -k ignores cached authorization; -n never prompts or reads a password.
        let result = try await commands.run("/usr/bin/sudo", arguments: ["-k", "-n", "--", "/usr/bin/pmset", "disablesleep", value])
        if result.status == 0 { return true }
        if permissionInstalled { throw KeepAwakeFailure.passwordlessDenied(result.output) }
        try await authorize("/usr/bin/pmset disablesleep " + value)
        return false
    }

    func verifyPasswordless() async throws -> Bool {
        // Verify effective access with the current value; this preserves the existing sleep mode.
        let value = try read() ? "1" : "0"
        let result = try await commands.run("/usr/bin/sudo", arguments: ["-k", "-n", "--", "/usr/bin/pmset", "disablesleep", value])
        return result.status == 0
    }

    func configurePasswordless(_ enabled: Bool) async throws {
        guard let permission else { throw KeepAwakeFailure.unavailable }
        try await authorize(permission.script(install: enabled))
    }

    private func authorize(_ shell: String) async throws {
        let literal = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(literal)\" with administrator privileges"
        let result = try await commands.run("/usr/bin/osascript", arguments: ["-e", script])
        guard result.status == 0 else {
            throw result.output.contains("(-128)") ? KeepAwakeFailure.cancelled : KeepAwakeFailure.authorization(result.output)
        }
    }
}
