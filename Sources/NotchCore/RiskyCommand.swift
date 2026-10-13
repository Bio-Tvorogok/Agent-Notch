import Foundation

/// Git global options do not change whether its subcommand needs a click, and text inside them is scanned too.
enum RiskyCommand {
    private static let patterns = [#"\brm\b[^|;&]*\s-(-recursive|[a-z]*r)"#, #"\bsudo\b"#, #"git\s+push\b.*(--force|\s-f\b|\s\+\S)"#,
                        #"git\s+reset\s+--hard"#, #"git\s+clean\s+-[a-z]*f"#, #"\bdrop\s+(table|database)\b"#,
                        #"(curl|wget)[^|]*\|\s*(ba|z)?sh"#, #"\$\(\s*(curl|wget)"#, #"\bfind\b.*\s-delete\b"#,
                        #"\bmkfs\b"#, #"\bdd\s+if="#, #"chmod\s+-r\s+777"#, #"\btruncate\b"#, #">\s*/dev/(disk|sd)"#]

    static func contains(_ command: String) -> Bool {
        let lower = command.lowercased()
        return [lower, normalizeGit(lower)].contains { text in
            patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
        }
    }

    private static func normalizeGit(_ command: String) -> String {
        let value = #"(?:"(?:\\.|[^"\\])*"|'[^']*'|\\.|[^\s;&|'"\\])+"#
        let short = "(?:-C|-c)\\s*" + value
        let longNames = "(?:git-dir|work-tree|namespace|config-env|super-prefix|attr-source|exec-path)"
        let long = "--" + longNames + "(?:=|\\s+)" + value
        let flag = #"(?:--(?:no-pager|paginate|bare|no-replace-objects|literal-pathspecs|glob-pathspecs|noglob-pathspecs|icase-pathspecs|no-optional-locks|no-lazy-fetch|no-advice)|-[pP])"#
        let pattern = #"\bgit\s+(?:(?:"# + short + "|" + long + "|" + flag + #")\s+)+"#
        return command.replacingOccurrences(of: pattern, with: "git ", options: [.regularExpression, .caseInsensitive])
    }
}
