import Foundation

struct ShareContext {
    let kind: String
    let entityID: String?
    let query: String
    let category: String?
    let model: String?
    let start: Date
    let end: Date
    let timezone: String
    let coverage: AccountingCoverage
    let capturedAt: Date
    let completion: CompletionRecord?
}
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
    var capturedAt: Date = Date()
    var rangeStart: Date = Date()
    var rangeEnd: Date = Date()
    var heatmapMetric: String = "tokens"
    var context: ShareContext?
    static let downloadURL = "https://zhangligong0826.github.io/codex-ledger/"
    var primaryCost: CostEstimate { completionCost ?? cost }
    var primaryUsage: TokenUsage { context?.completion?.usage ?? usage }
    var primaryTurns: Int? { if let record = context?.completion { return record.legacy ? nil : record.turnIDs.count }; return turns }
    var monthlyUsage: TokenUsage { days.reduce(TokenUsage()) { $0 + $1.usage } }
    var monthlyCost: CostEstimate { days.reduce(CostEstimate()) { $0 + $1.cost } }
    var activeDays: Int { days.filter { $0.usage.total > 0 }.count }
}


extension ShareSnapshot {
    func dateLabel(_ date: Date, time: Bool = false) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        formatter.dateFormat = time ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    var calendarRange: String {
        let end = rangeEnd.addingTimeInterval(-1)
        if rangeStart < Date(timeIntervalSince1970: -2208988800) { return "≤ " + dateLabel(end) }
        let start = dateLabel(rangeStart), finish = dateLabel(end)
        return start == finish ? start : start + " — " + finish
    }
}
