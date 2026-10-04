import Foundation
import CryptoKit

struct LedgerGoal: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var createdAt = Date()
    var completedAt: Date?
    var completionCost: CostEstimate?
    var completionUsage: TokenUsage?
    var budgetUSD: Decimal?
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
    var budget: String = ""
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
        guard book.version == 1, Set(book.goals.map(\.id)).count == book.goals.count, book.goals.allSatisfy({ !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 160 && ($0.budgetUSD ?? 0) >= 0 && ($0.completedAt == nil || ($0.completionCost != nil && $0.completionUsage != nil)) }) else { throw CocoaError(.fileReadCorruptFile) }
        return book
    }
    func summaries(current: [LedgerTask], lifetime: [LedgerTask]) -> [GoalUsage] {
        let currentGroups = Dictionary(grouping: current, by: { owner($0) ?? Self.unassigned })
        let lifetimeGroups = Dictionary(grouping: lifetime, by: { owner($0) ?? Self.unassigned })
        return goals.map { GoalUsage(goal: $0, tasks: currentGroups[$0.id] ?? [], lifetimeTasks: lifetimeGroups[$0.id] ?? []) }
            .sorted { a, b in
                if (a.goal.completedAt == nil) != (b.goal.completedAt == nil) { return a.goal.completedAt == nil }
                let aCost = a.goal.completionCost ?? a.lifetimeCost, bCost = b.goal.completionCost ?? b.lifetimeCost
                if aCost.totalUSD != bCost.totalUSD { return aCost.totalUSD > bCost.totalUSD }
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
    static func renderGoals(_ goals: [GoalUsage], scope: String, lifetimeReady: Bool, translate: (String) -> String = { $0 }, context: CSVContext? = nil) -> String {
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
            values.append(entry.goal.budgetUSD.map(LedgerPricing.decimalString) ?? "")
            let reference = entry.goal.completionCost ?? entry.lifetimeCost
            values.append(entry.goal.budgetUSD.flatMap { budget in reference.unpricedTokens == 0 && (entry.goal.completionCost != nil || lifetimeReady) ? LedgerPricing.decimalString(budget - reference.totalUSD) : nil } ?? "")
            values += context?.values(translate: translate) ?? []
            rows.append(values.map(field).joined(separator: ","))
        }
        header += ["预算USD", "预算差额USD"] + (context?.headers ?? [])
        let translatedHeader = header.map(translate).map(field).joined(separator: ",")
        return "\u{feff}" + ([translatedHeader] + rows).joined(separator: "\r\n")
    }
}

struct GoalArchive: Codable {
    var format = "codex-ledger-goals"
    var version = 1
    var exportedAt: Date
    var book: GoalBook
    static func encode(_ book: GoalBook, now: Date = Date()) throws -> Data {
        _ = try GoalBook.decode(JSONEncoder().encode(book))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer(); try container.encode(formatter.string(from: date))
        }
        let data = try encoder.encode(Self(exportedAt: now, book: book))
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var content = json["book"] as! [String: Any], goals = content["goals"] as! [[String: Any]]
        for index in goals.indices {
            if let budget = book.goals[index].budgetUSD { goals[index]["budgetUSD"] = LedgerPricing.decimalString(budget) }
            if let cost = book.goals[index].completionCost {
                var prices = goals[index]["completionCost"] as! [String: Any]
                prices["inputUSD"] = LedgerPricing.decimalString(cost.inputUSD); prices["cachedUSD"] = LedgerPricing.decimalString(cost.cachedUSD); prices["outputUSD"] = LedgerPricing.decimalString(cost.outputUSD)
                goals[index]["completionCost"] = prices
            }
        }
        content["goals"] = goals; json["book"] = content
        return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    }
    static func decode(_ data: Data) throws -> GoalBook {
        guard data.count <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw CocoaError(.fileReadCorruptFile) }; return date
        }
        let archive = try decoder.decode(Self.self, from: data)
        guard archive.format == "codex-ledger-goals", archive.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return try GoalBook.decode(JSONEncoder().encode(archive.book))
    }
}


enum GoalRecovery {
    static var directory: URL {
        if let root = ProcessInfo.processInfo.environment["CODEX_LEDGER_BACKUP_DIR"] { return URL(fileURLWithPath: root) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CodexLedger/Backups")
    }
    static func save(_ data: Data, source: String) throws {
        let prefix = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        let fm = FileManager.default; try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = try? GoalBook.decode(data)
        let contents = try original.map { try GoalArchive.encode($0) } ?? data
        let suffix = original == nil ? ".recovery.bin" : ".backup.json"
        let url = directory.appendingPathComponent(prefix + "-" + UUID().uuidString + suffix)
        try contents.write(to: url, options: .atomic)
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.lastPathComponent.hasPrefix(prefix + "-") && $0.pathExtension == "json" }
            .sorted { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
        for old in files.dropFirst(20) { try fm.removeItem(at: old) }
    }
}


enum GoalBudget {
    static func parse(_ text: String) -> Decimal? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: "^[0-9]+(?:\\.[0-9]{1,8})?$", options: .regularExpression) != nil,
              let amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), !amount.isNaN, amount >= 0 else { return nil }
        return amount
    }
    static func label(_ goal: LedgerGoal, cost: CostEstimate, complete: Bool = true) -> String? {
        guard let budget = goal.budgetUSD else { return nil }
        let prefix = L("预算") + " " + LedgerPricing.money(budget) + " USD"
        guard complete else { return prefix + " · " + L("记录不完整") }
        guard cost.unpricedTokens == 0 else { return prefix + " · " + L("含未计价用量") }
        let difference = budget - cost.totalUSD
        return prefix + " · " + L(difference >= 0 ? "估算剩余" : "估算超出") + " " + LedgerPricing.money(difference >= 0 ? difference : -difference)
    }
}


extension LedgerGoal {
    private enum CodingKeys: String, CodingKey { case id, name, createdAt, completedAt, completionCost, completionUsage, completionPriceDate, budgetUSD }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name); createdAt = try c.decode(Date.self, forKey: .createdAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt); completionCost = try c.decodeIfPresent(CostEstimate.self, forKey: .completionCost)
        completionUsage = try c.decodeIfPresent(TokenUsage.self, forKey: .completionUsage); completionPriceDate = try c.decodeIfPresent(String.self, forKey: .completionPriceDate)
        if c.contains(.budgetUSD), try !c.decodeNil(forKey: .budgetUSD) { budgetUSD = try c.preciseDecimal(forKey: .budgetUSD) } else { budgetUSD = nil }
        if let usage = completionUsage { guard usage.input >= 0, usage.output >= 0, usage.cached >= 0, usage.cached <= usage.input, usage.reasoning >= 0, usage.reasoning <= usage.output, usage.input <= Int64.max - usage.output else { throw CocoaError(.fileReadCorruptFile) } }
    }
}
