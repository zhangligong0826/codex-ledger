import Foundation

// Money stays Decimal until display. Pricing is applied to each deduplicated
// response, before a turn or model is aggregated; totals are never repriced.
struct CostEstimate: Equatable, Codable {
    var inputUSD = Decimal.zero
    var cachedUSD = Decimal.zero
    var outputUSD = Decimal.zero
    var pricedTokens: Int64 = 0
    var unpricedTokens: Int64 = 0
    var unverifiedContextTokens: Int64 = 0
    var totalUSD: Decimal { inputUSD + cachedUSD + outputUSD }
    var hasEstimate: Bool { pricedTokens > 0 || unpricedTokens == 0 }
    static func + (a: Self, b: Self) -> Self {
        Self(inputUSD: a.inputUSD + b.inputUSD, cachedUSD: a.cachedUSD + b.cachedUSD,
             outputUSD: a.outputUSD + b.outputUSD, pricedTokens: a.pricedTokens + b.pricedTokens,
             unpricedTokens: a.unpricedTokens + b.unpricedTokens,
             unverifiedContextTokens: a.unverifiedContextTokens + b.unverifiedContextTokens)
    }
}

struct ModelPrice {
    let input: Decimal
    let cached: Decimal
    let output: Decimal
    let longContext: Bool
    init(_ input: String, _ cached: String, _ output: String, longContext: Bool = false) {
        self.input = Decimal(string: input, locale: Locale(identifier: "en_US_POSIX"))!
        self.cached = Decimal(string: cached, locale: Locale(identifier: "en_US_POSIX"))!
        self.output = Decimal(string: output, locale: Locale(identifier: "en_US_POSIX"))!
        self.longContext = longContext
    }
}

enum LedgerPricing {
    static let verifiedDate = "2026-10-04"
    static let sourceURL = URL(string: "https://developers.openai.com/api/docs/pricing")!
    static let longContextThreshold: Int64 = 272_000
    // Official Standard USD prices per million tokens, verified on the date above.
    // Exact names only. Internal models and undocumented aliases stay unpriced.
    static let prices: [String: ModelPrice] = [
        "gpt-6-astra": ModelPrice("10", "1", "50", longContext: true),
        "gpt-6.1-sol": ModelPrice("2", "0.1", "10", longContext: true),
        "gpt-6-sol": ModelPrice("2", "0.2", "10", longContext: true),
        "gpt-6-luna": ModelPrice("0.1", "0.01", "0.5", longContext: true),
        "gpt-5.6-sol": ModelPrice("4", "0.4", "20", longContext: true),
        "gpt-5.6-terra": ModelPrice("2", "0.2", "12", longContext: true),
        "gpt-5.6-luna": ModelPrice("0.2", "0.02", "1.2", longContext: true),
        "gpt-5.5": ModelPrice("5", "0.5", "30", longContext: true),
        "gpt-5.5-2026-04-23": ModelPrice("5", "0.5", "30", longContext: true),
        "gpt-5.4": ModelPrice("2.5", "0.25", "15", longContext: true),
        "gpt-5.4-mini": ModelPrice("0.75", "0.075", "4.5"),
        "gpt-5.4-nano": ModelPrice("0.2", "0.02", "1.25"),
        "gpt-5.3-codex": ModelPrice("1.75", "0.175", "14"),
        "gpt-5.2": ModelPrice("1.75", "0.175", "14"),
        "gpt-5.1": ModelPrice("1.25", "0.125", "10"),
        "gpt-5": ModelPrice("1.25", "0.125", "10"),
        "gpt-5-mini": ModelPrice("0.25", "0.025", "2"),
        "gpt-5-nano": ModelPrice("0.05", "0.005", "0.4"),
        "gpt-4.1": ModelPrice("2", "0.5", "8"),
        "gpt-4.1-mini": ModelPrice("0.4", "0.1", "1.6"),
        "gpt-4.1-nano": ModelPrice("0.1", "0.025", "0.4"),
        "gpt-4o": ModelPrice("2.5", "1.25", "10"),
        "gpt-4o-mini": ModelPrice("0.15", "0.075", "0.6"),
        "o3": ModelPrice("2", "0.5", "8"),
        "o4-mini": ModelPrice("1.1", "0.275", "4.4")
    ]
    static func estimate(model: String, usage: TokenUsage, hasRequestUsage: Bool = true) -> CostEstimate {
        guard let price = prices[model] else { return CostEstimate(unpricedTokens: usage.total) }
        let isLong = hasRequestUsage && price.longContext && usage.input > longContextThreshold
        let inputMultiplier = Decimal(isLong ? 2 : 1)
        let outputMultiplier = isLong ? Decimal(string: "1.5")! : Decimal(1)
        let cached = min(max(0, usage.cached), usage.input)
        let million = Decimal(1_000_000)
        return CostEstimate(inputUSD: Decimal(usage.input - cached) * price.input * inputMultiplier / million,
                            cachedUSD: Decimal(cached) * price.cached * inputMultiplier / million,
                            outputUSD: Decimal(usage.output) * price.output * outputMultiplier / million,
                            pricedTokens: usage.total,
                            unverifiedContextTokens: !hasRequestUsage && price.longContext ? usage.total : 0)
    }
    static func total(_ tasks: [LedgerTask]) -> CostEstimate {
        tasks.reduce(CostEstimate()) { $0 + $1.cost }
    }
    static func decimalString(_ value: Decimal) -> String {
        var value = value
        return NSDecimalString(&value, Locale(identifier: "en_US_POSIX"))
    }
    static func money(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency; formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        if value > 0 && value < Decimal(string: "0.01")! { return "<$0.01" }
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "$" + decimalString(value)
    }
    static func display(_ cost: CostEstimate) -> String {
        cost.hasEstimate ? money(cost.totalUSD) + (cost.unpricedTokens > 0 ? " *" : "") : L("单价未知")
    }
    static let explanation = "按已核对的标准 API 单价估算美元金额，不是订阅账单或实际扣款。缓存输入单独计价，推理已包含在输出中。长上下文按每次响应判断；旧日志无法确认上下文时使用短上下文单价。未包含缓存写入溢价、Fast 等服务档位差异、工具费及税费。历史用量也使用此价格快照。"
    static let csvHeaders = ["预估API花费USD", "已计价tokens", "未计价tokens", "上下文未确认tokens", "价格核对日期", "价格口径"]
    static func csvValues(_ cost: CostEstimate) -> [String] {
        [cost.hasEstimate ? decimalString(cost.totalUSD) : "", String(cost.pricedTokens), String(cost.unpricedTokens),
         String(cost.unverifiedContextTokens), verifiedDate, "Standard API estimate · USD"]
    }
}
