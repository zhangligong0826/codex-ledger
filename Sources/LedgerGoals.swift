import Foundation

struct LedgerGoal: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var createdAt = Date()
    var completedAt: Date?
    var completionCost: CostEstimate?
    var completionUsage: TokenUsage?
    var completionPriceDate: String?
}

enum GoalTargetKind: String, Codable { case project, conversation, turn }
struct GoalTarget: Equatable {
    var kind: GoalTargetKind
    var id: String
    var key: String { kind.rawValue + ":" + id }
}
struct GoalEditorDraft: Identifiable {
    var id = UUID()
    var name: String
    var goalID: String?
    var target: GoalTarget?
}

// Explicit local attribution, independent of inferred work categories. Each
// deduplicated turn belongs to at most one goal, even when rules overlap.
struct GoalBook: Codable {
    var version = 1
    var goals: [LedgerGoal] = []
    var bindings: [String: String] = [:]
    static let unassigned = "__unassigned__"
    func owner(_ task: LedgerTask) -> String? {
        for target in [GoalTarget(kind: .turn, id: task.id), GoalTarget(kind: .conversation, id: task.sessionID), GoalTarget(kind: .project, id: task.projectID)] {
            if let value = bindings[target.key] {
                return goals.contains { $0.id == value } ? value : nil
            }
        }
        return nil
    }
    mutating func assign(_ target: GoalTarget, to goalID: String?) {
        bindings[target.key] = goalID ?? Self.unassigned
    }
    mutating func remove(_ id: String) {
        goals.removeAll { $0.id == id }
        bindings = bindings.filter { $0.value != id }
    }
    static func decode(_ data: Data) throws -> Self {
        let book = try JSONDecoder().decode(Self.self, from: data)
        guard book.version == 1, Set(book.goals.map(\.id)).count == book.goals.count else { throw CocoaError(.fileReadCorruptFile) }
        return book
    }
    func summaries(current: [LedgerTask], lifetime: [LedgerTask]) -> [GoalUsage] {
        let currentGroups = Dictionary(grouping: current, by: { owner($0) ?? Self.unassigned })
        let lifetimeGroups = Dictionary(grouping: lifetime, by: { owner($0) ?? Self.unassigned })
        return goals.map { GoalUsage(goal: $0, tasks: currentGroups[$0.id] ?? [], lifetimeTasks: lifetimeGroups[$0.id] ?? []) }
            .sorted { a, b in
                if (a.goal.completedAt == nil) != (b.goal.completedAt == nil) { return a.goal.completedAt == nil }
                if a.lifetimeCost.totalUSD != b.lifetimeCost.totalUSD { return a.lifetimeCost.totalUSD > b.lifetimeCost.totalUSD }
                return a.goal.id < b.goal.id
            }
    }
}
struct GoalUsage: Identifiable {
    var goal: LedgerGoal
    var tasks: [LedgerTask]
    var lifetimeTasks: [LedgerTask]
    var id: String { goal.id }
    var usage: TokenUsage { tasks.reduce(TokenUsage()) { $0 + $1.usage } }
    var cost: CostEstimate { LedgerPricing.total(tasks) }
    var lifetimeUsage: TokenUsage { lifetimeTasks.reduce(TokenUsage()) { $0 + $1.usage } }
    var lifetimeCost: CostEstimate { LedgerPricing.total(lifetimeTasks) }
    var lastActivity: Date? { lifetimeTasks.map(\.lastActivity).max() }
}
extension LedgerCSV {
    static func renderGoals(_ goals: [GoalUsage], scope: String, lifetimeReady: Bool, translate: (String) -> String = { $0 }) -> String {
        let header = ["目标", "目标ID", "目标状态", "创建时间", "完成时间", "统计范围", "任务轮次", "对话数", "项目数", "总tokens"] + LedgerPricing.csvHeaders + ["累计总tokens"] + LedgerPricing.csvHeaders.map { "累计" + $0 } + ["完成时总tokens"] + LedgerPricing.csvHeaders.map { "完成时" + $0 }
        let rows = goals.map { entry -> String in
            let values = [entry.goal.name, entry.id, translate(entry.goal.completedAt == nil ? "进行中" : "已完成"), entry.goal.createdAt.formatted(.iso8601), entry.goal.completedAt?.formatted(.iso8601) ?? "", scope, String(entry.tasks.count), String(Set(entry.tasks.map(\.sessionID)).count), String(Set(entry.tasks.map(\.projectID)).count), String(entry.usage.total)] + LedgerPricing.csvValues(entry.cost) + [lifetimeReady ? String(entry.lifetimeUsage.total) : ""] + (lifetimeReady ? LedgerPricing.csvValues(entry.lifetimeCost) : LedgerPricing.csvHeaders.map { _ in "" })
            var completionValues = entry.goal.completionCost.map { LedgerPricing.csvValues($0) } ?? LedgerPricing.csvHeaders.map { _ in "" }
            completionValues[4] = entry.goal.completionPriceDate ?? ""
            let completed = [entry.goal.completionUsage.map { String($0.total) } ?? ""] + completionValues
            return (values + completed).map(field).joined(separator: ",")
        }
        return "\u{feff}" + ([header.map(translate).map(field).joined(separator: ",")] + rows).joined(separator: "\r\n")
    }
}
