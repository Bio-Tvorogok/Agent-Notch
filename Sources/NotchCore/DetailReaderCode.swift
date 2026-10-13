import Foundation

extension DetailState {
    static func sessionKey(_ value: Any?) -> String? {
        if let n = value as? Int { return String(n) }
        return value as? String
    }

    /// Read literal tool arguments without executing code from a session log.
    mutating func codeCalls(_ code: String, id: String?, at: Any?) {
        guard let re = try? NSRegularExpression(pattern: #"tools\.(exec_command|shell|apply_patch|update_plan|write_stdin)\s*\("#) else { return }
        let matches = re.matches(in: code, range: NSRange(code.startIndex..., in: code))
        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: code),
                  let range = Range(match.range, in: code) else { continue }
            let name = String(code[nameRange])
            let raw = Self.literalArgument(String(code[range.upperBound...]))
            let args = Self.args(Self.jsonKeys(raw))
            fileCallId = matches.count == 1 ? id : nil
            switch name {
            case "exec_command", "shell":
                let quoted = raw.firstMatch(#"(?:cmd|command)"?\s*:\s*("(?:[^"\\]|\\.)*")"#)
                let cmd = args["cmd"] as? String ?? args["command"] as? String
                    ?? quoted.flatMap(Self.stringLiteral)
                command(matches.count == 1 ? id : nil, cmd, at)
            case "write_stdin":
                let key = Self.sessionKey(args["session_id"])
                    ?? raw.firstMatch(#"session_id"?\s*:\s*(\d+)"#)
                if let key, let i = sessions[key], let id { commandIds[id] = i }
            case "apply_patch":
                if let text = Self.stringLiteral(raw) { patch(text) }
            case "update_plan":
                if let plan = args["plan"] as? [Rec] {
                    detail.plan = plan.compactMap {
                        guard let text = $0["step"] as? String else { return nil }
                        return PlanItem(text: text, status: PlanStatus(logValue: $0["status"] as? String))
                    }
                }
            default: break
            }
        }
    }

    static func jsonKeys(_ raw: String) -> String {
        let chars = Array(raw)
        var result = "", i = 0
        var quote: Character?
        var escaped = false
        while i < chars.count {
            let c = chars[i]
            if let q = quote {
                result.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == q { quote = nil }
                i += 1; continue
            }
            if c == "\"" || c == "'" || c == "`" { quote = c; result.append(c); i += 1; continue }
            if c.isLetter || c == "_" {
                let start = i
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") { i += 1 }
                let token = String(chars[start..<i])
                var next = i
                while next < chars.count && chars[next].isWhitespace { next += 1 }
                result += next < chars.count && chars[next] == ":" ? "\"\(token)\"" : token
            } else { result.append(c); i += 1 }
        }
        return result
    }

    static func stringLiteral(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else { return nil }
        return value
    }

    static func literalArgument(_ code: String) -> String {
        var quote: Character?
        var escaped = false
        var depth = 0
        var result = ""
        for c in code {
            if let q = quote {
                result.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == q { quote = nil }
                continue
            }
            if c == "\"" || c == "'" || c == "`" { quote = c }
            if c == "(" || c == "[" || c == "{" { depth += 1 }
            if c == ")" {
                if depth == 0 { break }
                depth -= 1
            }
            if c == "]" || c == "}" { depth -= 1 }
            result.append(c)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
