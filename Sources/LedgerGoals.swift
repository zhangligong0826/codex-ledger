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
        var header: [String] = ["目标", "目标ID", "目标状态", "创建时间", "完成时间", "统计范围", "任务轮次", "对话数", "项目数", "总tokens"]
        header += LedgerPricing.csvHeaders
        header.append("累计总tokens")
        header += LedgerPricing.csvHeaders.map { "累计" + $0 }
        header.append("完成时总tokens")
        header += LedgerPricing.csvHeaders.map { "完成时" + $0 }
        var rows: [String] = []
        for entry in goals {
            let state = translate(entry.goal.completedAt == nil ? "进行中" : "已完成")
            let created = entry.goal.createdAt.formatted(.iso8601)
            let completed = entry.goal.completedAt?.formatted(.iso8601) ?? ""
            let chats = String(Set(entry.tasks.map(\.sessionID)).count)
            let projects = String(Set(entry.tasks.map(\.projectID)).count)
            var values: [String] = [entry.goal.name, entry.id, state, created, completed, scope]
            values += [String(entry.tasks.count), chats, projects, String(entry.usage.total)]
            values += LedgerPricing.csvValues(entry.cost)
            values.append(lifetimeReady ? String(entry.lifetimeUsage.total) : "")
            let emptyPrices: [String] = LedgerPricing.csvHeaders.map { _ in "" }
            values += lifetimeReady ? LedgerPricing.csvValues(entry.lifetimeCost) : emptyPrices
            values.append(entry.goal.completionUsage.map { String($0.total) } ?? "")
            var completionPrices: [String] = entry.goal.completionCost.map { LedgerPricing.csvValues($0) } ?? emptyPrices
            completionPrices[4] = entry.goal.completionPriceDate ?? ""
            values += completionPrices
            rows.append(values.map(field).joined(separator: ","))
        }
        let translatedHeader = header.map(translate).map(field).joined(separator: ",")
        return "\u{feff}" + ([translatedHeader] + rows).joined(separator: "\r\n")
    }
}
