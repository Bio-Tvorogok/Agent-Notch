import Foundation

/// Re-merges concurrent edits; a busy file stays untouched after three attempts.
enum HookFileUpdate {
    static func apply(read: () throws -> String, merge: (String) throws -> String,
                      prepare: (String) throws -> Void = { _ in },
                      write: (String, String) throws -> Void) throws {
        var old = try read()
        for _ in 0..<3 {
            let next = try merge(old)
            if next != old { try prepare(old) }
            let current = try read()
            guard current == old else { old = current; continue }
            if next != old { try write(old, next) }
            return
        }
        throw POSIXError(.EBUSY)
    }
}
