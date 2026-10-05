import Foundation
import CryptoKit

enum DateScope: String, CaseIterable, Identifiable {
    case today = "今天", yesterday = "昨天", week = "近 7 天", month = "近 30 天", history = "历史累计"
    var id: String { rawValue }
    var days: Int { switch self { case .today, .yesterday, .week: return 7; case .month: return 30; case .history: return Int.max } }
    func interval(now: Date, calendar: Calendar) -> DateInterval {
        let midnight = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: midnight)!
        switch self {
        case .today: return DateInterval(start: midnight, end: tomorrow)
        case .yesterday: return DateInterval(start: calendar.date(byAdding: .day, value: -1, to: midnight)!, end: midnight)
        case .week: return DateInterval(start: calendar.date(byAdding: .day, value: -6, to: midnight)!, end: tomorrow)
        case .month: return DateInterval(start: calendar.date(byAdding: .day, value: -29, to: midnight)!, end: tomorrow)
        case .history: return DateInterval(start: .distantPast, end: tomorrow)
        }
    }
}

struct DailyUsage: Identifiable {
    var date: Date
    var usage = TokenUsage()
    var responses = 0
    var cost = CostEstimate()
    var id: Date { date }
    func costIntensity(peak: Decimal) -> Int {
        guard cost.totalUSD > 0, peak > 0 else { return 0 }
        return max(1, min(4, Int(ceil(NSDecimalNumber(decimal: cost.totalUSD / peak).doubleValue * 4))))
    }
    func intensity(peak: Int64) -> Int {
        guard usage.total > 0 else { return 0 }
        return max(1, Int(ceil(min(1, Double(usage.total) / Double(max(1, peak))) * 4)))
    }
}

enum WorkCategory: String, Codable, CaseIterable, Identifiable {
    case question, research, slides, document, spreadsheet, coding, image, mixed, background, unknown
    var id: String { rawValue }
    var title: String {
        switch self {
        case .question: return "问答与学习"
        case .research: return "研究与分析"
        case .slides: return "PPT 制作"
        case .document: return "Word 与写作"
        case .spreadsheet: return "表格与数据"
        case .coding: return "编程与调试"
        case .image: return "图片与设计"
        case .mixed: return "混合任务"
        case .background: return "后台检查"
        case .unknown: return "未分类"
        }
    }
    var symbol: String {
        switch self {
        case .question: return "bubble.left.and.text.bubble.right"
        case .research: return "magnifyingglass"
        case .slides: return "rectangle.on.rectangle"
        case .document: return "doc.text"
        case .spreadsheet: return "tablecells"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .mixed: return "square.stack.3d.up"
        case .background: return "checkmark.shield"
        case .unknown: return "ellipsis.circle"
        }
    }
}

struct TokenUsage: Codable, Equatable {
    var input: Int64 = 0
    var cached: Int64 = 0
    var output: Int64 = 0
    var reasoning: Int64 = 0
    var total: Int64 { input + output }
    init() {}
    init(_ object: [String: Any]) {
        func number(_ key: String) -> Int64 { max(0, (object[key] as? NSNumber)?.int64Value ?? 0) }
        input = number("input_tokens"); output = number("output_tokens")
        cached = min(input, number("cached_input_tokens"))
        reasoning = min(output, number("reasoning_output_tokens"))
    }
    static func + (a: Self, b: Self) -> Self {
        var result = Self(); result.input = a.input + b.input; result.output = a.output + b.output
        result.cached = a.cached + b.cached; result.reasoning = a.reasoning + b.reasoning
        return result
    }
    func delta(after old: Self?) -> Self {
        guard let old else { return self }
        // A decreasing cumulative counter starts a new accounting segment.
        if input < old.input || output < old.output { return self }
        var result = Self(); result.input = input - old.input; result.output = output - old.output
        result.cached = min(result.input, max(0, cached - old.cached))
        result.reasoning = min(result.output, max(0, reasoning - old.reasoning))
        return result
    }
}

struct UsageSample: Codable {
    var id: String
    var sessionID: String
    var turnID: String
    var rootTurnID: String
    var date: Date
    var model: String
    var usage: TokenUsage
    var hasRequestUsage = true
    var cost: CostEstimate { LedgerPricing.estimate(model: model, usage: usage, hasRequestUsage: hasRequestUsage) }
}

// Reconcile counters over their recorded intervals; never silently choose one whole-file format.
enum UsageReconciler {
    static func reconcile(legacy: [UsageSample], modern: [UsageSample], intervals: [String: Date]) -> (samples: [UsageSample], warnings: [String]) {
        guard !modern.isEmpty else { return (legacy, []) }
        var residuals: [UsageSample] = [], warnings: [String] = []
        for old in legacy {
            let start = intervals[old.id] ?? .distantPast
            let covered = modern.filter { $0.date > start && $0.date <= old.date }
            let used = covered.reduce(TokenUsage()) { $0 + $1.usage }
            guard used.input <= old.usage.input, used.output <= old.usage.output else {
                warnings.append("新旧日志计数无法对齐，用量可能不完整。")
                continue
            }
            var remaining = old
            remaining.usage = TokenUsage()
            remaining.usage.input = old.usage.input - used.input
            remaining.usage.output = old.usage.output - used.output
            remaining.usage.cached = min(remaining.usage.input, max(0, old.usage.cached - used.cached))
            remaining.usage.reasoning = min(remaining.usage.output, max(0, old.usage.reasoning - used.reasoning))
            remaining.hasRequestUsage = old.hasRequestUsage && covered.isEmpty
            if remaining.usage.total > 0 { residuals.append(remaining) }
        }
        // Delayed duplicate emissions lack a response ID on the old counter. Keep
        // modern records and disclose ambiguous coverage instead of double-counting.
        for turn in Set(legacy.map(\.turnID)).intersection(Set(modern.map(\.turnID))) {
            let a = legacy.filter { $0.turnID == turn }.reduce(TokenUsage()) { $0 + $1.usage }
            let b = modern.filter { $0.turnID == turn }.reduce(TokenUsage()) { $0 + $1.usage }
            if a.input == b.input && a.output == b.output && residuals.contains(where: { $0.turnID == turn }) {
                residuals.removeAll { $0.turnID == turn }
                warnings.append("新旧日志计数无法对齐，用量可能不完整。")
            }
        }
        return ((modern + residuals).sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }, Array(Set(warnings)).sorted())
    }
}

struct TurnInfo: Codable {
    var id: String
    var sessionID: String
    var rootTurnID: String
    var prompt: String = ""
    var model: String = "未知模型"
    var start: Date
    var finished = false
    var artifacts: [String] = []
    var evidence: String = ""
    var inheritedCategory: WorkCategory = .unknown
    var workingDirectory = ""
}

struct ParsedLog: Codable {
    var path: String
    var size: UInt64
    var modified: Date
    var sessionID = ""
    var parentID: String?
    var internalAgent = false
    var turns: [String: TurnInfo] = [:]
    var samples: [UsageSample] = []
    var malformed = 0
    var integrityWarnings: [String] = []
    var usesResponseRecords = false
    var workingDirectory = ""
    var firstPrompt = ""
}

struct LedgerTask: Identifiable {
    var id: String
    var sessionID: String
    var title: String
    var category: WorkCategory
    var reason: String
    var usage: TokenUsage
    var date: Date
    var models: [String]
    var artifacts: [String]
    var finished: Bool
    var responses: Int
    var subagentResponses: Int
    var workingDirectory = ""
    var projectID = ProjectIdentity.unknown.id
    var projectName = ProjectIdentity.unknown.name
    var projectPath = ""
    var lastActivity = Date.distantPast
    var modelUsage: [ModelUsage] = []
    var cost: CostEstimate {
        modelUsage.isEmpty ? CostEstimate(unpricedTokens: usage.total) : modelUsage.reduce(CostEstimate()) { $0 + $1.cost }
    }
}

struct LedgerSnapshot {
    var tasks: [LedgerTask] = []
    var modelUsage: [ModelUsage] = []
    var projects: [ProjectUsage] = []
    var conversations: [ConversationUsage] = []
    var files = 0
    var malformed = 0
    var warnings: [String] = []
    var refreshedAt = Date()
    var sourcePath = ""
    var timezone = TimeZone.current.identifier
    var isComplete: Bool { warnings.isEmpty && malformed == 0 }
    var usage: TokenUsage { tasks.reduce(TokenUsage()) { $0 + $1.usage } }
    var cost: CostEstimate { LedgerPricing.total(tasks) }
}

struct ModelUsage: Identifiable {
    var id: String { model }
    var model: String
    var usage = TokenUsage()
    var responses = 0
    var taskIDs = Set<String>()
    var cost = CostEstimate()
    init(model: String, usage: TokenUsage = TokenUsage(), responses: Int = 0, taskIDs: Set<String> = [], cost: CostEstimate? = nil) {
        self.model = model; self.usage = usage; self.responses = responses; self.taskIDs = taskIDs
        self.cost = cost ?? CostEstimate(unpricedTokens: usage.total)
    }
}

struct CSVContext {
    let complete: Bool
    let warnings: [String]
    let capturedAt: Date
    let start: Date
    let end: Date
    let timezone: String
    var headers: [String] { ["记录完整性", "读取提示", "统计时刻", "区间开始", "区间结束（不含）", "时区"] }
    func values(translate: (String) -> String) -> [String] {
        [translate(complete ? "完整" : "记录不完整"), warnings.map(translate).joined(separator: "; "), capturedAt.formatted(.iso8601), start.formatted(.iso8601), end.formatted(.iso8601), timezone]
    }
}

enum LedgerCSV {
    static func field(_ value: String) -> String {
        var text = value
        if let first = text.first, text.range(of: "^[+-]?[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) == nil, ["=", "+", "-", "@", "\t", "\r"].contains(String(first)) { text = "'" + text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    static func render(_ tasks: [LedgerTask], goalNames: [String: String]? = nil, translate: (String) -> String = { $0 }, context: CSVContext? = nil) -> String {
        let header = ["时间", "任务", "分类", "输入tokens", "缓存输入tokens", "输出tokens", "推理输出tokens", "总tokens", "模型", "关联文件", "聊天ID", "分类依据", "项目", "项目路径", "工作目录"] + LedgerPricing.csvHeaders
        let goalHeaders = goalNames == nil ? [] : ["目标"]
        var rows = [(header + goalHeaders + (context?.headers ?? [])).map(translate).joined(separator: ",")]
        rows += tasks.map { task -> String in
            let usage = task.usage
            let project = task.projectName == ProjectIdentity.unknown.name ? translate(task.projectName) : task.projectName
            let values: [String] = [task.date.formatted(.iso8601), task.title, translate(task.category.title), String(usage.input), String(usage.cached), String(usage.output), String(usage.reasoning), String(usage.total), task.models.map(translate).joined(separator: "; "), task.artifacts.joined(separator: "; "), task.sessionID, translate(task.reason), project, task.projectPath, task.workingDirectory]
            let goals = goalNames.map { [$0[task.id] ?? translate("未归入目标")] } ?? []
            return (values + LedgerPricing.csvValues(task.cost) + goals + (context?.values(translate: translate) ?? [])).map(field).joined(separator: ",")
        }
        return "\u{feff}" + rows.joined(separator: "\r\n")
    }
    static func renderModels(_ models: [ModelUsage], translate: (String) -> String = { $0 }, context: CSVContext? = nil) -> String {
        let header = ["模型", "调用次数", "相关任务数", "输入tokens", "缓存输入tokens", "输出tokens", "推理输出tokens", "总tokens"] + LedgerPricing.csvHeaders
        var rows = [(header + (context?.headers ?? [])).map(translate).joined(separator: ",")]
        rows += models.map { model in
            let values = [translate(model.model), String(model.responses), String(model.taskIDs.count), String(model.usage.input), String(model.usage.cached), String(model.usage.output), String(model.usage.reasoning), String(model.usage.total)]
            return (values + LedgerPricing.csvValues(model.cost) + (context?.values(translate: translate) ?? [])).map(field).joined(separator: ",")
        }
        return "\u{feff}" + rows.joined(separator: "\r\n")
    }
}

enum TaskClassifier {
    static func associatedFile(_ path: String) -> Bool {
        let infrastructure = ["/.codex/plugins/", "/.codex/skills/", "/.agents/skills/"]
        return !infrastructure.contains(where: path.contains) && !(path.contains("/Documents/Codex/") && path.contains("/work/"))
    }
    static func cleanPrompt(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (value.hasPrefix("# Selected text:") || value.hasPrefix("# Response annotations:") || value.hasPrefix("# Files mentioned by the user:")), let request = value.range(of: "## My request:") {
            var comments: [String] = []
            if let start = value.range(of: "<response-annotations>"), let end = value.range(of: "</response-annotations>") {
                let json = String(value[start.upperBound..<end.lowerBound])
                if let data = json.data(using: .utf8), let items = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                    comments = items.compactMap { $0["annotation"] as? String }
                }
            }
            value = (comments + [String(value[request.upperBound...])]).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
        }
        if value.contains("<heartbeat>"), let start = value.range(of: "<instructions>"), let end = value.range(of: "</instructions>", range: start.upperBound..<value.endIndex) {
            value = "定时任务：" + String(value[start.upperBound..<end.lowerBound])
        }
        // These blocks describe the client, not the human's requested work.
        for tag in ["environment_context", "external_codex_apps_open_page", "external_context", "system_reminder", "image"] {
            if let regex = try? NSRegularExpression(pattern: "<" + tag + "(?:\\s[^>]*)?>[\\s\\S]*?</" + tag + ">") {
                value = regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "")
            }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func classify(prompt: String, evidence: String = "", artifacts: [String] = [], inherited: WorkCategory = .unknown, internalAgent: Bool = false) -> (WorkCategory, String) {
        if internalAgent { return (.background, "Codex 内部检查或子代理记录") }
        let p = cleanPrompt(prompt).lowercased()
        let intent = contains(p, ["帮我", "给我", "制作", "设计", "生成", "创建", "完成", "开发", "实现", "写一", "做一", "做个", "做ppt", "修改", "改成", "编辑", "重写", "转成", "导出", "排版", "build ", "create ", "make ", "generate ", "implement ", "fix ", "write ", "design ", "convert "])
        let explicitProduction = contains(p, ["帮我制作", "帮我生成", "帮我写", "帮我完成", "帮我开发", "帮我实现", "帮我创建", "build ", "create ", "implement ", "generate "])
        let conceptual = contains(p, ["有什么想法", "有现成", "是什么", "有什么区别", "怎么用", "如何", "怎么样", "为什么", "解释", "讲解", "举例", "给我举", "是否", "what is", "how do", "explain "])
        if conceptual && !explicitProduction { return (.question, "提示词以询问、解释或方案讨论为主") }
        // Referenced datasets and source documents do not turn a question into production.
        let requestedDocument = contains(p, ["ppt", "powerpoint", "幻灯片", "演示文稿", "word", "docx", "文档", "写作", "写文章", "撰写", "文章初稿", "excel", "xlsx", "表格", "csv"])
        let extensions = Set(artifacts.map { URL(fileURLWithPath: $0).pathExtension.lowercased() })
        var outputs: [WorkCategory] = []
        if !extensions.isDisjoint(with: ["pptx", "ppt"]) { outputs.append(.slides) }
        if !extensions.isDisjoint(with: ["docx", "doc"]) { outputs.append(.document) }
        if !extensions.isDisjoint(with: ["xlsx", "xls", "csv", "tsv"]) { outputs.append(.spreadsheet) }
        if !extensions.isDisjoint(with: ["png", "jpg", "jpeg", "webp", "svg"]) && outputs.isEmpty && contains(p, ["图片", "画", "海报", "image", "logo"]) { outputs.append(.image) }
        if p.isEmpty {
            if outputs.count > 1 { return (.mixed, "关联了多种文档产物") }
            if let output = outputs.first { return (output, "依据关联的本地文件") }
        }
        if intent && contains(p, ["mac应用", "mac 应用", "macos", "插件", "app", "网站", "程序", "开发", "重构"]) { return (.coding, "提示词包含开发、修复或实现要求") }
        var targets: [WorkCategory] = []
        if contains(p, ["ppt", "powerpoint", "幻灯片", "演示文稿", "slide deck", "presentation"]) { targets.append(.slides) }
        if contains(p, ["word", "docx", "文档", "写作", "稿件", "公文", "写文章", "撰写", "改写文章", "重写文章", "写一篇"]) { targets.append(.document) }
        if contains(p, ["excel", "xlsx", "csv", "表格", "电子表", "数据清洗"]) { targets.append(.spreadsheet) }
        if targets.count > 1 && intent { return (.mixed, "提示词请求多种产物，尚未确认最终文件") }
        if let target = targets.first, intent { return (target, outputs.contains(target) ? "依据提示词中的产物要求和关联文件" : "依据提示词中的产物要求，文件尚未确认") }
        if intent && requestedDocument, outputs.count == 1, let output = outputs.first { return (output, "依据产物要求和关联的本地文件") }
        if contains(p, ["研究", "调研", "研报", "论文", "文献", "财报", "投资", "分析", "research", "analyze", "analysis"]) { return (.research, "提示词以研究或分析为主") }
        if contains(p, ["画一", "绘制", "生成图片", "海报", "logo", "插画", "image generation", "draw "]) { return (.image, "提示词请求视觉创作") }
        if contains(p, ["代码", "报错", "脚本", "bug", "debug", "编程", "swift", "python", "typescript"]) { return (.coding, "提示词涉及代码或调试") }
        if p.count < 25 && contains(p, ["继续", "好的", "可以", "接着", "continue", "yes", "go ahead"]), inherited != .unknown { return (inherited, "沿用同一聊天上一轮的工作类型") }
        if p.isEmpty { return (.unknown, "日志未记录可识别的用户请求") }
        return (.question, "一般问答；可在任务详情中修正")
    }
    static func contains(_ text: String, _ values: [String]) -> Bool { values.contains { text.contains($0) } }
}

final class LogParser {
    private let fractional = ISO8601DateFormatter()
    private let whole = ISO8601DateFormatter()
    init() { fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds] }
    func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return fractional.date(from: string) ?? whole.date(from: string)
    }
    func parse(url: URL, size: UInt64 = 0, modified: Date = Date(), cutoff: Date = .distantPast) throws -> ParsedLog {
        var result = ParsedLog(path: url.path, size: size, modified: modified)
        var currentTurn = "initial", rootTurn = "initial", currentModel = "未知模型"
        var currentDirectory = ""
        var lastPrompt = "", previousCategory: WorkCategory = .unknown
        var legacy: [UsageSample] = [], cumulative: TokenUsage?
        var intervals: [String: Date] = [:], counterDate = Date.distantPast
        var legacySeen = Set<String>(), responsesSeen = Set<String>()
        var structured: [UsageSample] = []
        var isBeforeAgentStart = false
        var agentStartOrdinal: Int?
        func ensureTurn(_ stamp: Date) {
            if result.turns[currentTurn] == nil {
                result.turns[currentTurn] = TurnInfo(id: currentTurn, sessionID: result.sessionID, rootTurnID: rootTurn, model: currentModel, start: stamp, inheritedCategory: previousCategory)
                result.turns[currentTurn]?.workingDirectory = currentDirectory
            }
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var pending = Data()
        func consume(_ line: Data) {
            guard !line.isEmpty else { return }
            guard let r = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let type = r["type"] as? String, let p = r["payload"] as? [String: Any] else {
                result.malformed += 1; return
            }
            // Most records are tool output or status messages. Validate their JSON,
            // but only parse an ISO timestamp when an accounting branch needs it.
            var cachedStamp: Date?
            var stamp: Date {
                if let cachedStamp { return cachedStamp }
                let value = date(r["timestamp"]) ?? modified; cachedStamp = value; return value
            }
            if type == "session_meta" {
                result.sessionID = (p["id"] as? String) ?? (p["session_id"] as? String) ?? url.deletingPathExtension().lastPathComponent
                currentDirectory = p["cwd"] as? String ?? ""
                result.workingDirectory = currentDirectory
                result.parentID = p["parent_thread_id"] as? String ?? p["forked_from_id"] as? String
                result.internalAgent = (p["source"] as? [String: Any])?["subagent"] != nil || (p["thread_source"] as? String == "guardian_review")
                agentStartOrdinal = (p["subagent_history_start_ordinal"] as? NSNumber)?.intValue
                isBeforeAgentStart = agentStartOrdinal != nil
                return
            }
            if let start = agentStartOrdinal, let ordinal = (r["ordinal"] as? NSNumber)?.intValue { isBeforeAgentStart = ordinal < start }
            if type == "event_msg", p["type"] as? String == "task_started" {
                if let info = result.turns[currentTurn] {
                    previousCategory = TaskClassifier.classify(prompt: info.prompt, artifacts: info.artifacts, inherited: info.inheritedCategory).0
                }
                currentTurn = p["turn_id"] as? String ?? "turn-\(stamp.timeIntervalSince1970)"
                rootTurn = p["root_turn_id"] as? String ?? currentTurn
                lastPrompt = ""; ensureTurn(stamp)
                return
            }
            if type == "turn_context" {
                currentTurn = p["turn_id"] as? String ?? currentTurn
                rootTurn = p["root_turn_id"] as? String ?? currentTurn
                currentModel = p["model"] as? String ?? currentModel
                currentDirectory = p["cwd"] as? String ?? currentDirectory
                ensureTurn(stamp)
                result.turns[currentTurn]?.model = currentModel
                result.turns[currentTurn]?.workingDirectory = currentDirectory
                if result.turns[currentTurn]?.prompt.isEmpty == true { result.turns[currentTurn]?.prompt = lastPrompt }
                return
            }
            if type == "response_item", p["type"] as? String == "message", p["role"] as? String == "user" {
                let text = (p["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
                let clean = TaskClassifier.cleanPrompt(text)
                if !clean.isEmpty {
                    if result.firstPrompt.isEmpty && !isBeforeAgentStart { result.firstPrompt = String(clean.prefix(200)) }
                    lastPrompt = String(clean.prefix(1000)); ensureTurn(stamp)
                    if result.turns[currentTurn]?.prompt.isEmpty == true { result.turns[currentTurn]?.prompt = lastPrompt }
                }
                return
            }
            if type == "event_msg", p["type"] as? String == "user_message", let text = p["message"] as? String {
                let clean = TaskClassifier.cleanPrompt(text)
                if !clean.isEmpty && result.firstPrompt.isEmpty && !isBeforeAgentStart { result.firstPrompt = String(clean.prefix(200)) }
                if !clean.isEmpty { lastPrompt = String(clean.prefix(1000)); ensureTurn(stamp); result.turns[currentTurn]?.prompt = lastPrompt }
                return
            }
            if type == "token_usage_record", let usage = p["usage"] as? [String: Any] {
                // Inherited records in a fork belong to their original thread.
                guard !isBeforeAgentStart else { return }
                if let owner = p["thread_id"] as? String, !result.sessionID.isEmpty, owner != result.sessionID { return }
                let response = p["response_id"] as? String ?? "\(result.sessionID):record:\(r["ordinal"] ?? stamp.timeIntervalSince1970)"
                guard responsesSeen.insert(response).inserted else { return }
                let turn = p["turn_id"] as? String ?? currentTurn
                let root = p["root_turn_id"] as? String ?? rootTurn
                if result.turns[turn] == nil { result.turns[turn] = TurnInfo(id: turn, sessionID: result.sessionID, rootTurnID: root, prompt: lastPrompt, model: currentModel, start: stamp, inheritedCategory: previousCategory, workingDirectory: currentDirectory) }
                structured.append(UsageSample(id: response, sessionID: result.sessionID, turnID: turn, rootTurnID: root, date: stamp, model: p["model"] as? String ?? currentModel, usage: TokenUsage(usage)))
                result.usesResponseRecords = true
                return
            }
            if type == "event_msg", p["type"] as? String == "token_count", let info = p["info"] as? [String: Any], let total = info["total_token_usage"] as? [String: Any] {
                let now = TokenUsage(total), delta = now.delta(after: cumulative)
                cumulative = now
                let intervalStart = counterDate; counterDate = stamp
                // Repeated quota-only snapshots do not represent new inference.
                guard delta.total > 0, !isBeforeAgentStart else { return }
                let signature = "\(result.sessionID):\(currentTurn):\(stamp.timeIntervalSince1970):\(now.input):\(now.output)"
                guard legacySeen.insert(signature).inserted else { return }
                ensureTurn(stamp)
                let last = (info["last_token_usage"] as? [String: Any]).map(TokenUsage.init)
                intervals[signature] = intervalStart
                legacy.append(UsageSample(id: signature, sessionID: result.sessionID, turnID: currentTurn, rootTurnID: rootTurn, date: stamp, model: currentModel, usage: delta, hasRequestUsage: last == delta))
                return
            }
            if type == "event_msg", p["type"] as? String == "task_complete" {
                let turn = p["turn_id"] as? String ?? currentTurn
                result.turns[turn]?.finished = true
                collectArtifacts(p["last_agent_message"] as? String ?? "", turn: turn, result: &result)
                return
            }
            if type == "response_item", ["function_call", "custom_tool_call"].contains(p["type"] as? String ?? "") {
                ensureTurn(stamp)
                let input = p["arguments"] as? String ?? p["input"] as? String ?? ""
                let name = p["name"] as? String ?? ""
                if result.turns[currentTurn]!.evidence.count < 1200 { result.turns[currentTurn]?.evidence += " " + name }
                collectArtifacts(String(input.prefix(100000)), turn: currentTurn, result: &result)
                return
            }
            if type == "response_item", p["type"] as? String == "message", p["role"] as? String == "assistant" {
                let text = (p["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
                collectArtifacts(String(text.prefix(100000)), turn: currentTurn, result: &result)
            }
        }
        while let chunk = try handle.read(upToCount: 512 * 1024), !chunk.isEmpty {
            pending.append(chunk)
            var start = pending.startIndex
            while let end = pending[start...].firstIndex(of: 10) {
                // Foundation's temporary JSON objects must not accumulate until an
                // entire multi-gigabyte scan returns to the run loop.
                autoreleasepool { consume(Data(pending[start..<end])) }
                start = pending.index(after: end)
            }
            if start > pending.startIndex { pending = Data(pending[start...]) }
        }
        // A trailing partial line is expected while Codex is writing. Retry next scan.
        autoreleasepool {
            if !pending.isEmpty, (try? JSONSerialization.jsonObject(with: pending)) != nil { consume(pending) }
        }
        let reconciliation = UsageReconciler.reconcile(legacy: legacy, modern: structured, intervals: intervals)
        result.samples = reconciliation.samples.filter { $0.date >= cutoff }
        result.integrityWarnings = reconciliation.warnings
        if result.sessionID.isEmpty {
            result.sessionID = "log:" + url.deletingPathExtension().lastPathComponent
            for key in result.turns.keys { result.turns[key]?.sessionID = result.sessionID }
            for index in result.samples.indices { result.samples[index].sessionID = result.sessionID }
        }
        let referenced = Set(result.samples.map(\.turnID))
        result.turns = result.turns.filter { referenced.contains($0.key) }
        return result
    }
    private static let artifactRegex = try! NSRegularExpression(pattern: #"/(?:Users|Volumes|private/tmp|tmp)/[^\n<>\"`\)\]\{\}]*?\.(?:pptx|docx|xlsx|csv|tsv|pdf|png|jpg|jpeg|webp|svg|md|html|swift|py|js|ts|app|zip|icns)(?=[\s\"'`<>\)\],;]|$)"#, options: [.caseInsensitive])
    private func collectArtifacts(_ text: String, turn: String, result: inout ParsedLog) {
        guard result.turns[turn] != nil, result.turns[turn]!.artifacts.count < 30 else { return }
        for match in Self.artifactRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let path = String(text[range])
            if !result.turns[turn]!.artifacts.contains(path) { result.turns[turn]?.artifacts.append(path) }
        }
    }
}

// Mutable parser/cache state is used only by the caller's serial scan queue.
// snapshot() uses its arguments and immutable values and never reads that state.
final class LedgerScanner: @unchecked Sendable {
    private var cache: [String: ParsedLog] = [:]
    private var cacheRoot = ""
    private struct Stamp: Equatable { let size: UInt64; let modified: Date }
    private var manifest: [String: Stamp]?
    private var previousWarnings: [String] = []
    private var previousCutoff: Date?
    private var revision = 0
    private let cacheDirectory: URL?
    private struct CacheEntry: Codable {
        // Bump this whenever parsing/attribution semantics change. Prices are not cached.
        var version = 1
        let root: String
        let digest: String
        let payload: Data
    }
    private(set) var parsedFileCount = 0
    private(set) var diskCacheHits = 0
    private(set) var memoryCacheHits = 0
    private let parser = LogParser()
    let calendar: Calendar
    init(timezone: TimeZone = .current, cacheDirectory: URL? = nil) {
        var c = Calendar(identifier: .gregorian); c.timeZone = timezone; calendar = c
        self.cacheDirectory = cacheDirectory
    }
    static var applicationCacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("local.codexledger.app/usage-v1", isDirectory: true)
    }
    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func cacheURL(path: String) -> URL? {
        cacheDirectory?.appendingPathComponent(hash(Data(cacheRoot.utf8)), isDirectory: true).appendingPathComponent(hash(Data(path.utf8)) + ".plist")
    }
    private func restore(path: String, size: UInt64, modified: Date) -> ParsedLog? {
        guard let url = cacheURL(path: path),
              let bytes = try? Data(contentsOf: url, options: .mappedIfSafe),
              let entry = try? PropertyListDecoder().decode(CacheEntry.self, from: bytes), entry.version == 1, entry.root == cacheRoot,
              hash(entry.payload) == entry.digest,
              let log = try? PropertyListDecoder().decode(ParsedLog.self, from: entry.payload),
              log.path == path, log.size == size, log.modified == modified else { return nil }
        return log
    }
    private func persist(_ log: ParsedLog) {
        guard let url = cacheURL(path: log.path) else { return }
        // This index is disposable, local and private; a write failure never blocks accounting.
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if let cacheDirectory { try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cacheDirectory.path) }
            let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
            let payload = try encoder.encode(log)
            try encoder.encode(CacheEntry(root: cacheRoot, digest: hash(payload), payload: payload)).write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { /* Fall back to the source logs on the next launch. */ }
    }
    func scan(root: URL, now: Date = Date(), days: Int? = 7, overrides: [String: String] = [:], progress: ((Int, Int) -> Void)? = nil) -> (logs: [ParsedLog], warnings: [String], revision: Int) {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        if cacheRoot != root.path { cache = [:]; manifest = nil; cacheRoot = root.path }
        parsedFileCount = 0; diskCacheHits = 0; memoryCacheHits = 0
        let cutoff = days.map { calendar.date(byAdding: .day, value: -(max(1, $0) - 1), to: calendar.startOfDay(for: now))! } ?? .distantPast
        let fm = FileManager.default
        var found = false, warnings: [String] = [], logs: [ParsedLog] = []
        var paths = Set<String>()
        var candidates: [(URL, UInt64, Date)] = []
        for directory in ["sessions", "archived_sessions"] {
            let source = root.appendingPathComponent(directory)
            guard fm.fileExists(atPath: source.path) else { continue }
            found = true
            guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles], errorHandler: { url, error in
                warnings.append("读取失败：\(url.lastPathComponent) · \(error.localizedDescription)"); return true
            }) else { warnings.append("无法读取 \(source.path)"); continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                do {
                    let attrs = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
                    guard attrs.isRegularFile == true else { continue }
                    let modified = attrs.contentModificationDate ?? .distantPast
                    paths.insert(url.path)
                    guard modified >= cutoff else { continue }
                    let size = UInt64(max(0, attrs.fileSize ?? 0))
                    candidates.append((url, size, modified))
                } catch { warnings.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
            }
        }
        progress?(0, candidates.count)
        for (index, entry) in candidates.enumerated() {
            let (url, size, modified) = entry
            do {
                let log: ParsedLog
                if let old = cache[url.path], old.size == size, old.modified == modified { log = old; memoryCacheHits += 1 }
                else if let old = restore(path: url.path, size: size, modified: modified) { log = old; cache[url.path] = old; diskCacheHits += 1 }
                else {
                    // Cache the complete file once. Date filtering must never discard older
                    // responses when switching ranges or computing a goal's lifetime.
                    log = try parser.parse(url: url, size: size, modified: modified); parsedFileCount += 1
                    let after = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                    if after.contentModificationDate == modified && UInt64(max(0, after.fileSize ?? 0)) == size {
                        cache[url.path] = log; persist(log)
                    } else { cache.removeValue(forKey: url.path) }
                }
                var selected = log
                if cutoff != .distantPast {
                    selected.samples = log.samples.filter { $0.date >= cutoff }
                    let turns = Set(selected.samples.map(\.turnID))
                    selected.turns = log.turns.filter { turns.contains($0.key) }
                }
                logs.append(selected)
            } catch { warnings.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
            progress?(index + 1, candidates.count)
        }
        cache = cache.filter { paths.contains($0.key) }
        if !found { warnings.append("没有找到 sessions 或 archived_sessions。请在设置中选择 Codex 数据目录。") }
        let next = Dictionary(uniqueKeysWithValues: logs.map { ($0.path, Stamp(size: $0.size, modified: $0.modified)) })
        let normalizedWarnings = Array(Set(warnings)).sorted()
        if manifest != next || previousWarnings != normalizedWarnings || previousCutoff != cutoff {
            revision += 1; manifest = next; previousWarnings = normalizedWarnings; previousCutoff = cutoff
        }
        return (logs, normalizedWarnings, revision)
    }
    func snapshot(logs: [ParsedLog], start: Date, end: Date, root: String = "", overrides: [String: String] = [:], warnings: [String] = []) -> LedgerSnapshot {
        let parseWarnings = logs.flatMap(\.integrityWarnings)
        let malformed = logs.reduce(0) { $0 + $1.malformed }
        let coverageWarnings = warnings + parseWarnings + (malformed > 0 ? ["部分完整日志行损坏，用量可能不完整。"] : [])
        var result = LedgerSnapshot(files: logs.count, malformed: malformed, warnings: Array(Set(coverageWarnings)).sorted(), sourcePath: root)
        var groups: [String: [UsageSample]] = [:]
        var infos: [String: TurnInfo] = [:], internalSessions = Set<String>()
        for log in logs {
            if log.internalAgent { internalSessions.insert(log.sessionID) }
            for info in log.turns.values { infos[log.sessionID + ":" + info.id] = info }
        }
        // Child responses with a matching root turn are attributed to the user's task.
        let roots = Dictionary(infos.values.filter { !internalSessions.contains($0.sessionID) }.map { ($0.id, $0.sessionID + ":" + $0.id) }, uniquingKeysWith: { a, _ in a })
        var subagentIDs = Set<String>()
        var models: [String: ModelUsage] = [:]
        forEachUniqueSample(logs: logs, start: start, end: end) { sample in
            var key = sample.sessionID + ":" + sample.turnID
            if internalSessions.contains(sample.sessionID), let rootKey = roots[sample.rootTurnID] { key = rootKey; subagentIDs.insert(sample.id) }
            groups[key, default: []].append(sample)
            var model = models[sample.model] ?? ModelUsage(model: sample.model)
            model.usage = model.usage + sample.usage; model.responses += 1; model.taskIDs.insert(key)
            model.cost = model.cost + sample.cost
            models[sample.model] = model
        }
        for (key, samples) in groups {
            guard let first = samples.min(by: { $0.date < $1.date }) else { continue }
            let info = infos[key]
            let artifacts = (info?.artifacts ?? []).filter { TaskClassifier.associatedFile($0) && FileManager.default.fileExists(atPath: $0) }
            let auto = TaskClassifier.classify(prompt: info?.prompt ?? "", evidence: info?.evidence ?? "", artifacts: artifacts, inherited: info?.inheritedCategory ?? .unknown, internalAgent: internalSessions.contains(info?.sessionID ?? first.sessionID))
            let override = overrides[key].flatMap(WorkCategory.init(rawValue:))
            let title = info?.prompt.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var task = LedgerTask(id: key, sessionID: info?.sessionID ?? first.sessionID, title: title.isEmpty ? (auto.0 == .background ? "Codex 后台检查" : "未记录用户请求") : String(title.prefix(200)), category: override ?? auto.0, reason: override == nil ? auto.1 : "你手动设置的分类", usage: samples.reduce(TokenUsage()) { $0 + $1.usage }, date: first.date, models: Array(Set(samples.map(\.model))).sorted(), artifacts: artifacts, finished: info?.finished ?? false, responses: samples.count, subagentResponses: samples.filter { subagentIDs.contains($0.id) }.count, workingDirectory: info?.workingDirectory ?? "", lastActivity: samples.map(\.date).max() ?? first.date)
            task.modelUsage = Dictionary(grouping: samples, by: \.model).map { name, calls in
                ModelUsage(model: name, usage: calls.reduce(TokenUsage()) { $0 + $1.usage }, responses: calls.count, taskIDs: [key], cost: calls.reduce(CostEstimate()) { $0 + $1.cost })
            }.sorted { $0.usage.total > $1.usage.total }
            result.tasks.append(task)
        }
        result.tasks.sort { $0.usage.total > $1.usage.total }
        result.modelUsage = models.values.sorted { $0.usage.total > $1.usage.total }
        return result
    }
    func attributionKeys(logs: [ParsedLog]) -> [String: String] {
        let internals = Set(logs.filter(\.internalAgent).map(\.sessionID))
        var roots: [String: String] = [:]
        for log in logs where !internals.contains(log.sessionID) {
            for info in log.turns.values where roots[info.id] == nil { roots[info.id] = log.sessionID + ":" + info.id }
        }
        var owners: [String: String] = [:]
        for log in logs where internals.contains(log.sessionID) {
            for sample in log.samples {
                if let root = roots[sample.rootTurnID] { owners[sample.sessionID + ":" + sample.turnID] = root }
            }
        }
        return owners
    }
    // The heatmap and ledger use the same response deduplication and date boundaries.
    private func forEachUniqueSample(logs: [ParsedLog], start: Date, end: Date, body: (UsageSample) -> Void) {
        var seen = Set<String>()
        for log in logs.sorted(by: { $0.path < $1.path }) {
            for sample in log.samples where sample.date >= start && sample.date < end {
                if seen.insert(sample.id).inserted { body(sample) }
            }
        }
    }
    func dailyUsage(logs: [ParsedLog], now: Date = Date(), calendar: Calendar? = nil, taskIDs: Set<String>? = nil, models: Set<String>? = nil) -> [DailyUsage] {
        let calendar = calendar ?? self.calendar
        let range = DateScope.month.interval(now: now, calendar: calendar)
        var days = (0..<30).map { DailyUsage(date: calendar.date(byAdding: .day, value: $0, to: range.start)!) }
        let indexes = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($0.element.date, $0.offset) })
        let owners = attributionKeys(logs: logs)
        forEachUniqueSample(logs: logs, start: range.start, end: range.end) { sample in
            let key = owners[sample.sessionID + ":" + sample.turnID] ?? (sample.sessionID + ":" + sample.turnID)
            if let taskIDs, !taskIDs.contains(key) { return }
            if let models, !models.contains(sample.model) { return }
            guard let index = indexes[calendar.startOfDay(for: sample.date)] else { return }
            days[index].usage = days[index].usage + sample.usage
            days[index].responses += 1
            days[index].cost = days[index].cost + sample.cost
        }
        return days
    }
}

func compactTokens(_ number: Int64) -> String {
    if number >= 1_000_000_000 { return String(format: "%.2fB", Double(number) / 1_000_000_000) }
    if number >= 1_000_000 { return String(format: "%.2fM", Double(number) / 1_000_000) }
    if number >= 1000 { return String(format: "%.1fK", Double(number) / 1000) }
    return String(number)
}

func exactTokens(_ number: Int64) -> String { number.formatted(.number.grouping(.automatic)) }
