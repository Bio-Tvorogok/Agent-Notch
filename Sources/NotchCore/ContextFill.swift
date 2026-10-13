import Foundation

public struct ContextUsage: Equatable, Sendable {
    public var usedTokens: Int
    public var windowTokens: Int
    public var percent: Double { Double(usedTokens) * 100 / Double(windowTokens) }
    public init(usedTokens: Int, windowTokens: Int) {
        self.usedTokens = usedTokens; self.windowTokens = windowTokens
    }
}

public enum ContextFill {
    /// Latest complete usage in a bounded tail; nil means the log gives no usable window.
    public static func read(path: String, vendor: Vendor) -> ContextUsage? {
        for record in UsageLog.tail(path).reversed() {
            if vendor == .claude {
                guard record["type"] as? String == "assistant", let message = record["message"] as? Rec,
                      let usage = message["usage"] as? Rec else { continue }
                let model = (message["model"] as? String ?? "").lowercased()
                let amount = TokenAmounts.claude(usage)
                if model == "<synthetic>" && amount.total == 0 { continue }
                // Claude logs a 1M-context model under its plain name, so more than 200k in use also means 1M.
                let large = model.contains("[1m]") || model.contains("1m") || model.contains("1000000") || amount.input + amount.cached + amount.created > 200_000
                return ContextUsage(usedTokens: amount.total, windowTokens: large ? 1_000_000 : 200_000)
            }
            guard let info = UsageLog.tokenInfo(record) else { continue }
            let window = UsageLog.count(info["model_context_window"])
            guard window > 0, let usage = info["last_token_usage"] as? Rec ?? info["total_token_usage"] as? Rec else { return nil }
            return ContextUsage(usedTokens: TokenAmounts.codex(usage).total, windowTokens: window)
        }
        return nil
    }
}
