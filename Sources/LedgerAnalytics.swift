import Foundation
import SQLite3

struct ProjectIdentity: Equatable {
    var id: String
    var name: String
    var path: String
    static let unknown = Self(id: "unidentified-project", name: "未识别项目", path: "")
}

// Used exclusively by the serial analytics queue. Repository discovery is file-only:
// invoking macOS's /usr/bin/git shim can prompt users to install developer tools.
final class ProjectResolver: @unchecked Sendable {
    private var cache: [String: (Date, ProjectIdentity)] = [:]
    func resolve(_ directory: String) -> ProjectIdentity {
        guard directory.hasPrefix("/") else { return .unknown }
        let url = URL(fileURLWithPath: directory).standardizedFileURL.resolvingSymlinksInPath()
        if let (date, value) = cache[url.path], Date().timeIntervalSince(date) < 300 { return value }
        var value = ProjectIdentity(id: "directory:" + url.path, name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent, path: url.path)
        var ancestor = url
        while ancestor.path != "/" {
            if FileManager.default.fileExists(atPath: ancestor.appendingPathComponent(".git").path) {
                if let commonURL = commonDirectory(at: ancestor) {
                    let projectURL = commonURL.lastPathComponent == ".git" ? commonURL.deletingLastPathComponent() : ancestor
                    value = ProjectIdentity(id: "git:" + commonURL.path, name: projectURL.lastPathComponent, path: projectURL.path)
                }
                break
            }
            ancestor.deleteLastPathComponent()
        }
        cache[url.path] = (Date(), value)
        return value
    }
    private func commonDirectory(at root: URL) -> URL? {
        let fm = FileManager.default, marker = root.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: marker.path, isDirectory: &isDirectory) else { return nil }
        let gitDirectory: URL
        if isDirectory.boolValue {
            gitDirectory = marker.standardizedFileURL.resolvingSymlinksInPath()
        } else {
            guard let line = metadataLine(marker), line.hasPrefix("gitdir: ") else { return nil }
            let path = String(line.dropFirst(8))
            guard !path.isEmpty else { return nil }
            gitDirectory = resolvePath(path, relativeTo: root)
        }
        let commonMarker = gitDirectory.appendingPathComponent("commondir")
        let common: URL
        if fm.fileExists(atPath: commonMarker.path) {
            guard let path = metadataLine(commonMarker), !path.isEmpty else { return nil }
            common = resolvePath(path, relativeTo: gitDirectory)
        } else {
            common = gitDirectory
        }
        guard fm.fileExists(atPath: gitDirectory.appendingPathComponent("HEAD").path),
              fm.fileExists(atPath: common.appendingPathComponent("objects").path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fm.fileExists(atPath: common.appendingPathComponent("refs").path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return common
    }
    private func resolvePath(_ path: String, relativeTo base: URL) -> URL {
        (path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path))
            .standardizedFileURL.resolvingSymlinksInPath()
    }
    private func metadataLine(_ file: URL) -> String? {
        // Read only small regular pointer files, never repository config or hooks.
        let file = file.resolvingSymlinksInPath()
        guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 16_385), data.count <= 16_384,
              let text = String(data: data, encoding: .utf8) else { return nil }
        let line = text.trimmingCharacters(in: .newlines)
        guard !line.contains("\n"), !line.contains("\r"), !line.contains("\0") else { return nil }
        return line
    }
}

struct ConversationUsage: Identifiable {
    var id: String
    var title: String
    var tasks: [LedgerTask]
    // This is the full conversation's project set, even in a project-scoped view.
    var projectIDs: Set<String>
    var usage: TokenUsage { tasks.reduce(TokenUsage()) { $0 + $1.usage } }
    var cost: CostEstimate { LedgerPricing.total(tasks) }
    var lastActivity: Date { tasks.map(\.lastActivity).max() ?? .distantPast }
    var responses: Int { tasks.reduce(0) { $0 + $1.responses } }
    var models: [String] { Array(Set(tasks.flatMap(\.models))).sorted() }
    var spansProjects: Bool { projectIDs.count > 1 }
    var modelUsage: [ModelUsage] { LedgerAnalytics.models(tasks) }
    var categoryTotals: [(WorkCategory, Int64, Int)] { LedgerAnalytics.categories(tasks) }
}

struct ProjectUsage: Identifiable {
    var identity: ProjectIdentity
    var tasks: [LedgerTask]
    var conversations: [ConversationUsage]
    var id: String { identity.id }
    var name: String { identity.name }
    var path: String { identity.path }
    var usage: TokenUsage { tasks.reduce(TokenUsage()) { $0 + $1.usage } }
    var cost: CostEstimate { LedgerPricing.total(tasks) }
    var lastActivity: Date { tasks.map(\.lastActivity).max() ?? .distantPast }
    var models: [String] { Array(Set(tasks.flatMap(\.models))).sorted() }
    var categoryTotals: [(WorkCategory, Int64, Int)] { LedgerAnalytics.categories(tasks) }
}

enum ConversationMetadata {
    // Schema discovery makes this enrichment optional across Codex database versions.
    static func titles(root: URL) -> [String: String] {
        let fm = FileManager.default
        for folder in [root, root.appendingPathComponent("sqlite")] {
            let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            for file in files {
                let found = readTitles(file)
                if !found.isEmpty { return found }
            }
        }
        return [:]
    }
    static func readTitles(_ file: URL) -> [String: String] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; return [:]
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)
        var statement: OpaquePointer?, columns = Set<String>()
        if sqlite3_prepare_v2(db, "PRAGMA table_info(threads)", -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let value = sqlite3_column_text(statement, 1) { columns.insert(String(cString: value)) }
            }
        }
        sqlite3_finalize(statement); statement = nil
        guard columns.contains("id"), columns.contains("title") else { return [:] }
        guard sqlite3_prepare_v2(db, "SELECT id, title FROM threads", -1, &statement, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(statement) }
        var titles: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawID = sqlite3_column_text(statement, 0), let rawTitle = sqlite3_column_text(statement, 1) else { continue }
            let title = String(cString: rawTitle).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { titles[String(cString: rawID)] = String(title.prefix(500)) }
        }
        return titles
    }
}

enum LedgerAnalytics {
    static func enrich(_ snapshot: LedgerSnapshot, resolver: ProjectResolver, titles: [String: String]) -> LedgerSnapshot {
        var result = snapshot
        result.tasks = snapshot.tasks.map { original in
            var task = original
            let project = resolver.resolve(task.workingDirectory)
            task.projectID = project.id; task.projectName = project.name; task.projectPath = project.path
            return task
        }
        result.conversations = conversations(result.tasks, titles: titles)
        let projectSets = Dictionary(uniqueKeysWithValues: result.conversations.map { ($0.id, $0.projectIDs) })
        result.projects = Dictionary(grouping: result.tasks, by: \.projectID).map { key, tasks in
            let first = tasks[0]
            return ProjectUsage(identity: ProjectIdentity(id: key, name: first.projectName, path: first.projectPath), tasks: tasks,
                                conversations: conversations(tasks, titles: titles, projectSets: projectSets))
        }.sorted { $0.usage.total == $1.usage.total ? $0.id < $1.id : $0.usage.total > $1.usage.total }
        return result
    }
    static func conversations(_ tasks: [LedgerTask], titles: [String: String], projectSets: [String: Set<String>] = [:]) -> [ConversationUsage] {
        Dictionary(grouping: tasks, by: \.sessionID).map { id, turns in
            let chronological = turns.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
            let fallback = chronological.first(where: { $0.title != "未记录用户请求" && $0.title != "Codex 后台检查" })?.title ?? chronological.first?.title ?? "未记录用户请求"
            return ConversationUsage(id: id, title: titles[id] ?? fallback, tasks: turns.sorted { $0.date < $1.date }, projectIDs: projectSets[id] ?? Set(turns.map(\.projectID)))
        }.sorted { $0.usage.total == $1.usage.total ? $0.id < $1.id : $0.usage.total > $1.usage.total }
    }
    static func categories(_ tasks: [LedgerTask]) -> [(WorkCategory, Int64, Int)] {
        WorkCategory.allCases.compactMap { category in
            let matching = tasks.filter { $0.category == category }, total = matching.reduce(Int64(0)) { $0 + $1.usage.total }
            return total > 0 ? (category, total, matching.count) : nil
        }.sorted { $0.1 > $1.1 }
    }
    static func models(_ tasks: [LedgerTask]) -> [ModelUsage] {
        var totals: [String: ModelUsage] = [:]
        for entry in tasks.flatMap(\.modelUsage) {
            var total = totals[entry.model] ?? ModelUsage(model: entry.model)
            total.usage = total.usage + entry.usage; total.responses += entry.responses; total.taskIDs.formUnion(entry.taskIDs)
            total.cost = total.cost + entry.cost
            totals[entry.model] = total
        }
        return totals.values.sorted { $0.usage.total == $1.usage.total ? $0.model < $1.model : $0.usage.total > $1.usage.total }
    }
}

extension LedgerCSV {
    static func renderProjects(_ projects: [ProjectUsage], translate: (String) -> String = { $0 }, context: CSVContext? = nil) -> String {
        let header = ["项目", "项目路径", "对话数", "任务轮次", "输入tokens", "缓存输入tokens", "输出tokens", "推理输出tokens", "总tokens", "模型", "最近活动"] + LedgerPricing.csvHeaders + (context?.headers ?? [])
        let rows = projects.map { project -> String in
            let usage = project.usage
            let name = project.name == ProjectIdentity.unknown.name ? translate(project.name) : project.name
            let values: [String] = [name, project.path, String(project.conversations.count), String(project.tasks.count), String(usage.input), String(usage.cached), String(usage.output), String(usage.reasoning), String(usage.total), project.models.map(translate).joined(separator: "; "), project.lastActivity.formatted(.iso8601)]
            return (values + LedgerPricing.csvValues(project.cost) + (context?.values(translate: translate) ?? [])).map(field).joined(separator: ",")
        }
        return "\u{feff}" + ([header.map(translate).joined(separator: ",")] + rows).joined(separator: "\r\n")
    }
    static func renderConversations(_ conversations: [ConversationUsage], projectPath: String? = nil, usageScope: String? = nil, translate: (String) -> String = { $0 }, context: CSVContext? = nil) -> String {
        let header = ["对话", "聊天ID", "项目路径", "统计范围", "任务轮次", "调用次数", "输入tokens", "缓存输入tokens", "输出tokens", "推理输出tokens", "总tokens", "模型", "涉及多个项目", "最近活动"] + LedgerPricing.csvHeaders + (context?.headers ?? [])
        let rows = conversations.map { chat -> String in
            let paths = projectPath ?? Array(Set(chat.tasks.map(\.projectPath))).sorted().joined(separator: "; ")
            let usage = chat.usage
            let models = chat.models.map(translate).joined(separator: "; ")
            let scope = usageScope ?? translate(projectPath == nil ? "整个对话" : "仅当前项目")
            let values: [String] = [chat.title, chat.id, paths, scope, String(chat.tasks.count), String(chat.responses), String(usage.input), String(usage.cached), String(usage.output), String(usage.reasoning), String(usage.total), models, translate(chat.spansProjects ? "是" : "否"), chat.lastActivity.formatted(.iso8601)]
            return (values + LedgerPricing.csvValues(chat.cost) + (context?.values(translate: translate) ?? [])).map(field).joined(separator: ",")
        }
        return "\u{feff}" + ([header.map(translate).joined(separator: ",")] + rows).joined(separator: "\r\n")
    }
}
