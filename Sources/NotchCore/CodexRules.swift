import Foundation
import Darwin

/// User-wide execpolicy rules, loaded by Codex at startup; hook replies cannot persist them.
public enum CodexRules {
    /// Appends only to our file. The caller supplies a human-approved literal argv prefix.
    public static func add(prefix: [String], home: URL) throws {
        guard home.isFileURL, !prefix.isEmpty, prefix.allSatisfy({ !$0.isEmpty && !$0.contains("\0") }) else {
            throw POSIXError(.EINVAL)
        }
        let fm = FileManager.default
        var dir = home
        for component in [".codex", "rules"] {
            dir.appendPathComponent(component)
            if (try? fm.destinationOfSymbolicLink(atPath: dir.path)) != nil { throw POSIXError(.ELOOP) }
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let file = dir.appendingPathComponent("agents-notch.rules")
        let fd = open(file.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw posixError() }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw posixError() }
        defer { flock(fd, LOCK_UN) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw posixError() }
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else { throw POSIXError(.EINVAL) }
        guard fchmod(fd, 0o600) == 0 else { throw posixError() }
        let data = try handle.readToEnd() ?? Data()
        guard let old = String(data: data, encoding: .utf8) else { throw POSIXError(.EILSEQ) }
        let rule = "prefix_rule(pattern=[" + prefix.map(quote).joined(separator: ", ") + "], decision=\"allow\")"
        let lines = old.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let hasRule = lines.contains(rule), hasHeader = lines.contains(header)
        guard !hasRule || !hasHeader else { return }
        var addition = old.isEmpty || old.hasSuffix("\n") ? "" : "\n"
        if !hasHeader { addition += header + "\n" }
        if !hasRule { addition += rule + "\n" }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(addition.utf8))
        try handle.synchronize()
    }

    private static let header = "# Managed by Agents Notch"

    /// Starlark accepts literal Unicode and hex escapes, rather than JSON's control-character escapes.
    private static func quote(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 34: out += "\\\""
            case 92: out += "\\\\"
            case 10: out += "\\n"
            case 13: out += "\\r"
            case 9: out += "\\t"
            case 0...31, 127: out += String(format: "\\x%02x", scalar.value)
            default: out += String(scalar)
            }
        }
        return out + "\""
    }

    private static func posixError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
