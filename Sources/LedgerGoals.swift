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
    var completions: [CompletionRecord] = []
}

enum GoalTargetKind: String, Codable { case project, conversation, turn }
struct GoalTarget: Codable, Equatable {
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

enum AttributionMode: String, Codable { case selected, fromDate, entire }
struct AttributionRule: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var target: GoalTarget
    var goalID: String
    var mode: AttributionMode
    var turnIDs: Set<String> = []
    var start: Date?
    var end: Date?
    var savedAt = Date()
    var legacy = false
    func matches(_ task: LedgerTask) -> Bool {
        if mode == .selected { return turnIDs.contains(task.id) }
        let targetMatches = target.kind == .turn ? target.id == task.id : target.kind == .conversation ? target.id == task.sessionID : target.id == task.projectID
        guard targetMatches else { return false }
        return (start == nil || task.attributionStart >= start!) && (end == nil || task.attributionStart < end!)
    }
}
struct CompletionRecord: Codable, Equatable, Identifiable {
    let id: String
    let completedAt: Date
    let capturedAt: Date
    let turnIDs: Set<String>
    let usage: TokenUsage
    let cost: CostEstimate
    let coverage: AccountingCoverage
    let priceVersion: String
    let legacy: Bool
    init(id: String = UUID().uuidString, completedAt: Date, capturedAt: Date, turnIDs: Set<String>, usage: TokenUsage, cost: CostEstimate, coverage: AccountingCoverage, priceVersion: String, legacy: Bool = false) {
        self.id = id; self.completedAt = completedAt; self.capturedAt = capturedAt; self.turnIDs = turnIDs; self.usage = usage; self.cost = cost; self.coverage = coverage; self.priceVersion = priceVersion; self.legacy = legacy
    }
}
struct AttributionState {
    let rules: [AttributionRule]
    let bindings: [String: String]
}
struct AssignmentDraft: Identifiable {
    let id = UUID()
    var goalID: String
    var target: GoalTarget?
}
struct AttributionPreview {
    let tasks: [LedgerTask]
    let cost: CostEstimate
    let displaced: [String: Int]
}

// Explicit local attribution, independent of inferred work categories. Each
// deduplicated turn belongs to at most one goal, even when rules overlap.
struct GoalBook: Codable {
    var version = 2
    var goals: [LedgerGoal] = []
    var bindings: [String: String] = [:]
    var rules: [AttributionRule] = []
    static let unassigned = "__unassigned__"
    func owner(_ task: LedgerTask) -> String? {
        for target in [GoalTarget(kind: .turn, id: task.id), GoalTarget(kind: .conversation, id: task.sessionID), GoalTarget(kind: .project, id: task.projectID)] {
            if let rule = rules.enumerated().filter({ ($0.element.mode == .selected ? GoalTargetKind.turn : $0.element.target.kind) == target.kind && $0.element.matches(task) }).max(by: { a, b in a.element.savedAt == b.element.savedAt ? a.offset < b.offset : a.element.savedAt < b.element.savedAt })?.element {
                return goals.contains { $0.id == rule.goalID } ? rule.goalID : nil
            }
            if let value = bindings[target.key] {
                return goals.contains { $0.id == value } ? value : nil
            }
        }
        return nil
    }
    mutating func assign(_ target: GoalTarget, to goalID: String?) {
        bindings[target.key] = goalID ?? Self.unassigned
    }
    func preview(_ rule: AttributionRule, tasks: [LedgerTask]) -> AttributionPreview {
        var simulated = self; simulated.apply(rule)
        let desired = rule.goalID == Self.unassigned ? nil : rule.goalID
        let selected = tasks.filter { rule.matches($0) && simulated.owner($0) == desired && owner($0) != desired }
        let displaced = Dictionary(grouping: selected.filter { owner($0) != nil && owner($0) != rule.goalID }, by: { owner($0)! }).mapValues(\.count)
        return AttributionPreview(tasks: selected, cost: LedgerPricing.total(selected), displaced: displaced)
    }
    mutating func apply(_ rule: AttributionRule) { rules.append(rule) }
    mutating func complete(_ id: String, tasks: [LedgerTask], now: Date, capturedAt: Date, coverage: AccountingCoverage) {
        guard coverage.canComplete, let index = goals.firstIndex(where: { $0.id == id }) else { return }
        let selected = tasks.filter { owner($0) == id }
        let record = CompletionRecord(completedAt: now, capturedAt: capturedAt, turnIDs: Set(selected.map(\.id)), usage: selected.reduce(TokenUsage()) { $0 + $1.usage }, cost: LedgerPricing.total(selected), coverage: coverage, priceVersion: LedgerPricing.version)
        goals[index].completions.append(record)
        goals[index].completedAt = now; goals[index].completionCost = record.cost; goals[index].completionUsage = record.usage; goals[index].completionPriceDate = LedgerPricing.verifiedDate
        for i in rules.indices where rules[i].goalID == id && !rules[i].legacy && rules[i].mode != .selected && rules[i].end == nil { rules[i].end = now }
    }
    mutating func reopen(_ id: String) {
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        goals[index].completedAt = nil; goals[index].completionCost = nil; goals[index].completionUsage = nil; goals[index].completionPriceDate = nil
    }
    mutating func remove(_ id: String) {
        goals.removeAll { $0.id == id }; rules.removeAll { $0.goalID == id }
        bindings = bindings.filter { $0.value != id }
    }
    static func decode(_ data: Data) throws -> Self {
        var book = try JSONDecoder().decode(Self.self, from: data)
        guard [1, 2].contains(book.version), Set(book.goals.map(\.id)).count == book.goals.count, book.goals.allSatisfy({ !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 160 && ($0.budgetUSD ?? 0) >= 0 && ($0.completedAt == nil || ($0.completionCost != nil && $0.completionUsage != nil)) }) else { throw CocoaError(.fileReadCorruptFile) }
        if book.version == 1 {
            book.version = 2
            for i in book.goals.indices {
                let g = book.goals[i]
                if let at = g.completedAt, let cost = g.completionCost, let usage = g.completionUsage {
                    book.goals[i].completions = [CompletionRecord(completedAt: at, capturedAt: at, turnIDs: [], usage: usage, cost: cost, coverage: AccountingCoverage(status: .complete), priceVersion: g.completionPriceDate ?? "", legacy: true)]
                }
            }
        }
        for goal in book.goals where goal.completedAt != nil && !goal.completions.isEmpty {
            guard goal.completions.last?.cost == goal.completionCost, goal.completions.last?.usage == goal.completionUsage else { throw CocoaError(.fileReadCorruptFile) }
        }
        guard Set(book.rules.map(\.id)).count == book.rules.count,
              book.rules.allSatisfy({ !$0.id.isEmpty && !$0.target.id.isEmpty && ($0.goalID == Self.unassigned || book.goals.map(\.id).contains($0.goalID)) && ($0.start == nil || $0.end == nil || $0.start! <= $0.end!) && ($0.mode != .fromDate || $0.start != nil) }),
              book.goals.allSatisfy({ goal in Set(goal.completions.map(\.id)).count == goal.completions.count && goal.completions.allSatisfy { record in
                  !record.id.isEmpty && record.usage.input >= 0 && record.usage.output >= 0 && record.usage.cached >= 0 && record.usage.cached <= record.usage.input && record.usage.reasoning >= 0 && record.usage.reasoning <= record.usage.output && record.usage.input <= Int64.max - record.usage.output && record.coverage.canComplete
              } }) else { throw CocoaError(.fileReadCorruptFile) }
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
    let tasks: [LedgerTask]
    let lifetimeTasks: [LedgerTask]
    var id: String { goal.id }
    let usage: TokenUsage
    let cost: CostEstimate
    let lifetimeUsage: TokenUsage
    let lifetimeCost: CostEstimate
    let lastActivity: Date?
    init(goal: LedgerGoal, tasks: [LedgerTask], lifetimeTasks: [LedgerTask]) {
        self.goal = goal; self.tasks = tasks; self.lifetimeTasks = lifetimeTasks
        usage = tasks.reduce(TokenUsage()) { $0 + $1.usage }; cost = LedgerPricing.total(tasks)
        lifetimeUsage = lifetimeTasks.reduce(TokenUsage()) { $0 + $1.usage }; lifetimeCost = LedgerPricing.total(lifetimeTasks)
        lastActivity = lifetimeTasks.map(\.lastActivity).max()
    }
}
extension LedgerCSV {
    static func renderGoals(_ goals: [GoalUsage], scope: String, lifetimeReady: Bool, translate: (String) -> String = { $0 }, context: CSVContext? = nil, coverageByGoal: [String: AccountingCoverage] = [:]) -> String {
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
            let coverage = coverageByGoal[entry.id] ?? AccountingCoverage(status: lifetimeReady ? .complete : .loading)
            let completion = entry.goal.completedAt == nil ? nil : entry.goal.completions.last
            values += [translate(coverage.canComplete ? "完整" : coverage.status == .loading ? "正在整理日志…" : "记录不完整"), coverage.reasons.map(translate).joined(separator: "; "), completion?.id ?? "", completion?.capturedAt.formatted(.iso8601) ?? "", completion?.priceVersion ?? "", completion.map { $0.legacy ? translate("旧记录未保存归属明细") : $0.turnIDs.sorted().joined(separator: "; ") } ?? ""]
            values += context?.values(translate: translate) ?? []
            rows.append(values.map(field).joined(separator: ","))
        }
        header += ["预算USD", "预算差额USD", "累计记录完整性", "累计读取提示", "完成记录ID", "完成统计时刻", "完成价格版本", "完成时归属明细"] + (context?.headers ?? [])
        let translatedHeader = header.map(translate).map(field).joined(separator: ",")
        return "\u{feff}" + ([translatedHeader] + rows).joined(separator: "\r\n")
    }
}

struct GoalArchive: Codable {
    var format = "codex-ledger-goals"
    var version = 2
    var exportedAt: Date
    var book: GoalBook
    static func encode(_ book: GoalBook, now: Date = Date()) throws -> Data {
        _ = try GoalBook.decode(JSONEncoder().encode(book))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.formatOptions = [.withInternetDateTime]
            let seconds = floor(date.timeIntervalSince1970)
            let base = String(formatter.string(from: Date(timeIntervalSince1970: seconds)).dropLast())
            let nanoseconds = Int(((date.timeIntervalSince1970 - seconds) * 1_000_000_000).rounded(.down))
            var container = encoder.singleValueContainer(); try container.encode(base + String(format: ".%09dZ", nanoseconds))
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
        for i in goals.indices {
            if var records = goals[i]["completions"] as? [[String: Any]] {
                for j in records.indices {
                    let cost = book.goals[i].completions[j].cost
                    var price = records[j]["cost"] as! [String: Any]
                    price["inputUSD"] = LedgerPricing.decimalString(cost.inputUSD); price["cachedUSD"] = LedgerPricing.decimalString(cost.cachedUSD); price["outputUSD"] = LedgerPricing.decimalString(cost.outputUSD)
                    records[j]["cost"] = price
                }
                goals[i]["completions"] = records
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
            if let dot = text.firstIndex(of: "."), text.hasSuffix("Z") {
                let fractional = String(text[text.index(after: dot)..<text.index(before: text.endIndex)])
                formatter.formatOptions = [.withInternetDateTime]
                if let base = formatter.date(from: String(text[..<dot]) + "Z"), fractional.allSatisfy(\.isNumber), let value = Double("0." + fractional) { return base.addingTimeInterval(value) }
            }
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw CocoaError(.fileReadCorruptFile) }; return date
        }
        let archive = try decoder.decode(Self.self, from: data)
        guard archive.format == "codex-ledger-goals", [1, 2].contains(archive.version) else { throw CocoaError(.fileReadCorruptFile) }
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
        let fm = FileManager.default; try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let original = try? GoalBook.decode(data)
        let contents = try original.map { try GoalArchive.encode($0) } ?? data
        let suffix = original == nil ? ".recovery.bin" : ".backup.json"
        let url = directory.appendingPathComponent(prefix + "-" + UUID().uuidString + suffix)
        try contents.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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
    private enum CodingKeys: String, CodingKey { case id, name, createdAt, completedAt, completionCost, completionUsage, completionPriceDate, budgetUSD, completions }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name); createdAt = try c.decode(Date.self, forKey: .createdAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt); completionCost = try c.decodeIfPresent(CostEstimate.self, forKey: .completionCost)
        completionUsage = try c.decodeIfPresent(TokenUsage.self, forKey: .completionUsage); completionPriceDate = try c.decodeIfPresent(String.self, forKey: .completionPriceDate)
        completions = try c.decodeIfPresent([CompletionRecord].self, forKey: .completions) ?? []
        if c.contains(.budgetUSD), try !c.decodeNil(forKey: .budgetUSD) { budgetUSD = try c.preciseDecimal(forKey: .budgetUSD) } else { budgetUSD = nil }
        if let usage = completionUsage { guard usage.input >= 0, usage.output >= 0, usage.cached >= 0, usage.cached <= usage.input, usage.reasoning >= 0, usage.reasoning <= usage.output, usage.input <= Int64.max - usage.output else { throw CocoaError(.fileReadCorruptFile) } }
    }
}

// v1 bindings remain explicit legacy continuous rules; never silently freeze them.
extension GoalBook {
    enum CodingKeys: String, CodingKey { case version, goals, bindings, rules }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        goals = try c.decodeIfPresent([LedgerGoal].self, forKey: .goals) ?? []
        bindings = try c.decodeIfPresent([String: String].self, forKey: .bindings) ?? [:]
        rules = try c.decodeIfPresent([AttributionRule].self, forKey: .rules) ?? []
    }
}
