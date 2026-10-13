import Foundation

struct TokenAmounts {
    var input = 0
    var cached = 0
    var created = 0
    var output = 0
    var total: Int { input + cached + created + output }
    static func claude(_ u: Rec) -> Self {
        Self(input: UsageLog.count(u["input_tokens"]), cached: UsageLog.count(u["cache_read_input_tokens"]),
             created: UsageLog.count(u["cache_creation_input_tokens"]), output: UsageLog.count(u["output_tokens"]))
    }
    static func codex(_ u: Rec) -> Self {
        let input = UsageLog.count(u["input_tokens"]), cached = min(input, UsageLog.count(u["cached_input_tokens"]))
        let output = UsageLog.count(u["output_tokens"])
        // Some exports only provide total_tokens. Reasoning is already included in output.
        let total = UsageLog.count(u["total_tokens"])
        return Self(input: input + output == 0 ? total : input - cached, cached: cached, output: output)
    }
    func delta(from old: Self) -> Self {
        Self(input: max(0, input - old.input), cached: max(0, cached - old.cached),
             created: max(0, created - old.created), output: max(0, output - old.output))
    }
}

enum SpendPrices {
    // Estimates in USD per million tokens, NOT billing rates or subscription charges.
    // Order: input, cache read, cache creation, output. Keep all family estimates here.
    static let estimates: [(String, [Double])] = [
        ("opus", [5, 0.5, 6.25, 25]), ("sonnet", [3, 0.3, 3.75, 15]),
        ("haiku", [1, 0.1, 1.25, 5]), ("fable", [3, 0.3, 3.75, 15]),
        ("sol", [2.5, 0.25, 2.5, 15]), ("luna", [0.5, 0.05, 0.5, 3]),
        ("astra", [5, 0.5, 5, 30])
    ]
    static func usd(_ usage: TokenAmounts, model: String?) -> Double? {
        guard let model = model?.lowercased(), let rates = estimates.first(where: { model.contains($0.0) })?.1 else { return nil }
        return (Double(usage.input) * rates[0] + Double(usage.cached) * rates[1]
                + Double(usage.created) * rates[2] + Double(usage.output) * rates[3]) / 1_000_000
    }
}
