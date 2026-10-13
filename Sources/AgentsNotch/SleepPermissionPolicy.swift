import Darwin
import Foundation

/// A root-owned rule for this UID and exactly two invocations of Apple's pmset.
struct SleepPermissionPolicy {
    static let ruleLines = "NF && ($0 !~ /^[[:space:]]*#([^0-9]|$)/ || $0 ~ /^[[:space:]]*#include(dir)?[[:space:]]/) { print }"
    let uid: uid_t
    private let directory = "/private/etc/sudoers.d"

    init(uid: uid_t) throws {
        guard uid != 0 else { throw KeepAwakeFailure.authorization("Cannot configure a passwordless rule for root.") }
        self.uid = uid
    }

    var path: String { directory + "/agent-notch-keep-awake-\(uid)" }
    var rule: String {
        "# Agent Notch keep-awake permission\n#\(uid) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1\n"
    }

    var installed: Bool {
        var folder = stat(), file = stat()
        return lstat(directory, &folder) == 0 && folder.st_mode & S_IFMT == S_IFDIR && folder.st_uid == 0 &&
            folder.st_mode & 0o022 == 0 && lstat(path, &file) == 0 && Self.isManagedFile(file)
    }

    static func isManagedFile(_ file: stat) -> Bool {
        file.st_mode & S_IFMT == S_IFREG && file.st_uid == 0 && file.st_gid == 0 && file.st_mode & 0o022 == 0
    }

    func script(install: Bool) -> String {
        // The UID is numeric. Policy bytes are embedded here, never read from a user-writable staging file.
        let checks = """
        set -eu
        umask 077
        fail() { /bin/echo "Agent Notch: $1" >&2; exit 1; }
        d='\(directory)'
        f='\(path)'
        /usr/sbin/visudo -c >/dev/null
        /usr/bin/grep -Eq '^[[:space:]]*[@#]includedir[[:space:]]+(/private)?/etc/sudoers[.]d([[:space:]]|$)' /private/etc/sudoers || fail 'sudoers.d is not enabled in the system sudoers configuration.'
        [ ! -L "$d" ] || fail 'The sudoers directory is a symbolic link.'
        if [ ! -e "$d" ]; then /usr/bin/install -d -o root -g wheel -m 0755 "$d"; fi
        [ -d "$d" ] && [ "$(/usr/bin/stat -f %u "$d")" = 0 ] || fail 'The sudoers directory is not owned by root.'
        case "$(/usr/bin/stat -f %Lp "$d")" in 755|750|700|555|550|500) ;; *) fail 'The sudoers directory has unsafe permissions.' ;; esac
        [ ! -L "$f" ] || fail 'The permission file is a symbolic link.'
        candidate=$(/usr/bin/mktemp "$d/.agent-notch-rule.XXXXXX")
        backup=$(/usr/bin/mktemp "$d/.agent-notch-backup.XXXXXX")
        actual=$(/usr/bin/mktemp "$d/.agent-notch-actual.XXXXXX")
        expected=$(/usr/bin/mktemp "$d/.agent-notch-expected.XXXXXX")
        trap '/bin/rm -f "$candidate" "$backup" "$actual" "$expected"' EXIT
        /usr/bin/printf '%s' '\(rule)' > "$candidate"
        /usr/sbin/visudo -cf "$candidate" >/dev/null
        had_file=0
        if [ -e "$f" ]; then
            [ -f "$f" ] && [ "$(/usr/bin/stat -f %u "$f")" = 0 ] || fail 'The permission file is not a root-owned regular file.'
            /usr/bin/awk '\(Self.ruleLines)' "$candidate" > "$expected"
            /usr/bin/awk '\(Self.ruleLines)' "$f" > "$actual"
            /usr/bin/cmp -s "$expected" "$actual" || fail 'The existing permission file belongs to another configuration.'
            /bin/cp -p "$f" "$backup"
            had_file=1
        fi
        """
        let change = install ? """
        /usr/sbin/chown root:wheel "$candidate"
        /bin/chmod 0440 "$candidate"
        /bin/mv -f "$candidate" "$f"
        """ : """
        if [ "$had_file" = 0 ]; then exit 0; fi
        /bin/rm "$f"
        """
        let verification = """
        if ! /usr/sbin/visudo -c >/dev/null; then
            if [ "$had_file" = 1 ]; then /bin/mv -f "$backup" "$f"; else /bin/rm -f "$f"; fi
            fail 'Validation failed; the previous permission was restored.'
        fi
        """
        return checks + "\n" + change + "\n" + verification
    }
}
