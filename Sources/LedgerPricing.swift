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
    private struct Catalog: Decodable {
        struct Rate: Decodable { let input: String; let cached: String; let output: String; let longContext: Bool }
        let version: Int; let verifiedDate: String; let sourceURL: String; let longContextThreshold: Int64
        let models: [String: Rate]
    }
    private static let catalog: Catalog? = {
        let candidates = [Bundle.main.url(forResource: "prices", withExtension: "json"),
                          URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Common/prices.json")]
        for url in candidates.compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Catalog.self, from: data), value.version == 1 { return value }
        }
        return nil
    }()
    static var verifiedDate: String { catalog?.verifiedDate ?? "Unknown" }
    static var sourceURL: URL { URL(string: catalog?.sourceURL ?? "https://developers.openai.com/api/docs/pricing")! }
    static var longContextThreshold: Int64 { catalog?.longContextThreshold ?? 272_000 }
    static let prices: [String: ModelPrice] = (catalog?.models ?? [:]).mapValues {
        ModelPrice($0.input, $0.cached, $0.output, longContext: $0.longContext)
    }
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


extension KeyedDecodingContainer {
    func preciseDecimal(forKey key: Key) throws -> Decimal {
        if let text = try? decode(String.self, forKey: key) {
            guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN else { throw CocoaError(.fileReadCorruptFile) }
            return value
        }
        return try decode(Decimal.self, forKey: key)
    }
}

extension CostEstimate {
    private enum CodingKeys: String, CodingKey { case inputUSD, cachedUSD, outputUSD, pricedTokens, unpricedTokens, unverifiedContextTokens }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputUSD = try c.preciseDecimal(forKey: .inputUSD); cachedUSD = try c.preciseDecimal(forKey: .cachedUSD); outputUSD = try c.preciseDecimal(forKey: .outputUSD)
        pricedTokens = try c.decode(Int64.self, forKey: .pricedTokens); unpricedTokens = try c.decode(Int64.self, forKey: .unpricedTokens); unverifiedContextTokens = try c.decode(Int64.self, forKey: .unverifiedContextTokens)
        guard inputUSD >= 0, cachedUSD >= 0, outputUSD >= 0, pricedTokens >= 0, unpricedTokens >= 0, unverifiedContextTokens >= 0 else { throw CocoaError(.fileReadCorruptFile) }
    }
}
