import Foundation

// A value snapshot: renderers never read a live store or reprice aggregate tokens.
struct ShareSnapshot {
    let kind: String
    let privateTitle: String
    let range: String
    let timezone: String
    let usage: TokenUsage
    let cost: CostEstimate
    let turns: Int
    let conversations: Int
    let models: Int
    let days: [DailyUsage]
    let completionCost: CostEstimate?
    let completionDate: Date?
    let completionPriceDate: String?
    let filtered: Bool
    let warning: Bool
    let priceDate: String
    static let downloadURL = "https://zhangligong0826.github.io/codex-ledger/"
    var monthlyUsage: TokenUsage { days.reduce(TokenUsage()) { $0 + $1.usage } }
    var monthlyCost: CostEstimate { days.reduce(CostEstimate()) { $0 + $1.cost } }
    var activeDays: Int { days.filter { $0.usage.total > 0 }.count }
}
