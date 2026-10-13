import Foundation

extension HookReply {
    /// Keeps the helper's final stdout choice testable.
    public static func helperStdout(event: HookEvent?, name: String, decision: HookDecision) -> String? {
        if let event { return stdout(event: event, decision: decision) }
        if case .allowAlways = decision { return nil }
        return stdout(event: name, decision: decision)
    }

    /// Revalidates the displayed rule against the request before granting a standing Claude approval.
    public static func stdout(event: HookEvent, decision: HookDecision, rule: AlwaysRule.Suggestion?) -> String? {
        guard decision == .allow, let rule else { return stdout(event: event.name, tool: event.tool, decision: decision) }
        guard event.vendor == .claude, AlwaysRule.suggest(for: event) == rule else { return nil }
        var permission: [String: Any] = ["toolName": rule.toolName]
        if let content = rule.ruleContent { permission["ruleContent"] = content }
        let update: [String: Any] = ["type": "addRules", "rules": [permission],
                                     "behavior": "allow", "destination": "localSettings"]
        let json: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest",
            "decision": ["behavior": "allow", "updatedPermissions": [update]]]]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
