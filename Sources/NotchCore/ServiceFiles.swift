import Darwin
import Foundation

/// Files a manifest names, read without trusting what they are: only regular files, opened without following a final
/// link and without blocking, from the descriptor that was checked. A FIFO or /dev/zero in place of a log neither hangs
/// nor floods the app, and nothing can be swapped in between the check and the read.
enum ServiceFiles {
    enum Failure: Error { case unreadable, notRegular, tooLarge }

    /// The whole file, if it is regular and at most `limit` bytes.
    static func contents(_ path: String, max limit: Int) throws -> Data {
        let (fd, info) = try open(path)
        defer { close(fd) }
        guard info.st_size <= off_t(limit) else { throw Failure.tooLarge }
        return try read(fd, from: 0, limit: limit)
    }

    /// The last `limit` bytes of a regular file, and whether the read started mid-file.
    static func tail(_ path: String, bytes limit: Int) throws -> (data: Data, cut: Bool) {
        let (fd, info) = try open(path)
        defer { close(fd) }
        let start = max(0, info.st_size - off_t(limit))
        return (try read(fd, from: start, limit: limit), start > 0)
    }

    private static func open(_ path: String) throws -> (Int32, stat) {
        let fd = Darwin.open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.unreadable }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            close(fd)
            throw Failure.notRegular
        }
        return (fd, info)
    }

    private static func read(_ fd: Int32, from offset: off_t, limit: Int) throws -> Data {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        var at = offset
        while data.count < limit {
            let n = pread(fd, &chunk, min(chunk.count, limit - data.count), at)
            if n < 0 { if errno == EINTR { continue }; throw Failure.unreadable }
            if n == 0 { break }
            data.append(chunk, count: n)
            at += off_t(n)
        }
        return data
    }

    /// Whether an extended ACL lets anyone write, append, delete or change ownership or permissions. The owner needs no
    /// such entry, so any is refused. Deny entries, such as the «everyone deny delete» macOS puts on home folders, are fine.
    static func aclGrantsWrite(_ path: String) -> Bool {
        guard let acl = acl_get_file(path, ACL_TYPE_EXTENDED) else { return false }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        let writes: [acl_perm_t] = [ACL_WRITE_DATA, ACL_APPEND_DATA, ACL_ADD_SUBDIRECTORY, ACL_DELETE_CHILD, ACL_DELETE,
                                    ACL_WRITE_SECURITY, ACL_CHANGE_OWNER]
        var entry: acl_entry_t?
        var which = ACL_FIRST_ENTRY.rawValue
        while acl_get_entry(acl, which, &entry) == 0, let current = entry {
            which = ACL_NEXT_ENTRY.rawValue
            var tag = ACL_UNDEFINED_TAG
            var perms: acl_permset_t?
            if acl_get_tag_type(current, &tag) == 0, tag == ACL_EXTENDED_ALLOW,
               acl_get_permset(current, &perms) == 0, let perms,
               writes.contains(where: { acl_get_perm_np(perms, $0) == 1 }) { return true }
        }
        return false
    }
}
