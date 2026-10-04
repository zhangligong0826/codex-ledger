import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

enum LedgerPage: String { case goals, tasks, projects, conversations, models, settings }

enum LedgerPreferences {
    static let isDemo = CommandLine.arguments.contains("--demo") || (Bundle.main.object(forInfoDictionaryKey: "LedgerDemo") as? Bool == true)
    static let defaults: UserDefaults = isDemo ? UserDefaults(suiteName: "local.codexledger.demo")! : .standard
}

struct SharePreview: Identifiable {
    let id = UUID()
    let snapshot: ShareSnapshot?
    let screenshot: NSImage?
}

@MainActor final class LedgerStore: ObservableObject {
    @Published var today = LedgerSnapshot()
    @Published var todayIsReady = false
    @Published var activity: [DailyUsage] = []
    @Published var activityReady = false
    @Published var snapshot = LedgerSnapshot()
    @Published var scope: DateScope = .today { didSet {
        guard scope != oldValue else { return }
        selectedTaskID = nil; recompute()
        if scope.days > loadedDays { refresh() }
    } }
    @Published var isLoading = false
    @Published var isComputing = false
    @Published var page: LedgerPage = .goals
    @Published var goalBook = GoalBook()
    @Published var goalEditor: GoalEditorDraft?
    @Published var selectedGoalID: String?
    @Published var unassignedOnly = false
    @Published var lifetime = LedgerSnapshot()
    @Published var lifetimeReady = false
    private var goalBookReadable = true
    @Published var search = ""
    @Published var categoryFilter: WorkCategory?
    @Published var modelFilter: String?
    @Published var selectedTaskID: String?
    @Published var selectedProjectID: String?
    @Published var selectedConversationID: String?
    @Published var language = LedgerPreferences.defaults.string(forKey: "language") ?? "en"
    @Published var heatmapMetric = LedgerPreferences.defaults.string(forKey: "heatmapMetric") ?? "tokens"
    @Published var appearance = LedgerPreferences.defaults.string(forKey: "appearance") ?? "system"
    @Published var scanCompleted = 0
    @Published var scanTotal = 0
    @Published var showFullStatus = true
    @Published var errorMessage: String?
    @Published var sourcePath: String
    @Published var launchAtLogin = false
    @Published var lastScanSeconds: Double = 0
    var didUpdate: (() -> Void)?
    @Published var isSharing = false
    var presentShare: ((SharePreview) -> Void)?
    var captureInterface: ((Bool) -> Void)?
    var prepareFilePanel: (() -> NSWindow?)?
    private var logs: [ParsedLog] = []
    private var loadedDays = 0
    private var renderedScope: DateScope?
    private var warnings: [String] = []
    private var overrides: [String: String]
    private var computeVersion = 0
    private let queue = DispatchQueue(label: "local.codexledger.scan", qos: .utility)
    private let scanner = LedgerScanner()
    private let resolver = ProjectResolver()
    private var timer: Timer?
    private let defaults = LedgerPreferences.defaults
    var showSettings: Bool {
        get { page == .settings }
        set { if newValue { page = .settings } else if page == .settings { page = .tasks } }
    }
    var showModels: Bool {
        get { page == .models }
        set { if newValue { page = .models } else if page == .models { page = .tasks } }
    }
    init() {
        let fallback = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        sourcePath = LedgerPreferences.isDemo ? "/Users/demo/.codex" : defaults.string(forKey: "sourcePath") ?? fallback
        overrides = defaults.dictionary(forKey: "categoryOverrides") as? [String: String] ?? [:]
        loadGoalBook()
        LedgerText.language = language
        showFullStatus = defaults.object(forKey: "fullStatus") as? Bool ?? true
        launchAtLogin = !LedgerPreferences.isDemo && SMAppService.mainApp.status == .enabled
    }
    var busy: Bool { isLoading || isComputing }
    var rangeReady: Bool { renderedScope == scope }
    var goalBookAvailable: Bool { goalBookReadable }
    var requiresGoalBook: Bool { page == .goals || selectedGoalID != nil || unassignedOnly }
    var contextReady: Bool { rangeReady && !dataUnavailable && (!requiresGoalBook || goalBookReadable) }
    var logsAreEmpty: Bool { logs.isEmpty && !LedgerPreferences.isDemo }
    var knownModelCount: Int { snapshot.modelUsage.filter { $0.model != "未知模型" }.count }
    var categoryTotals: [(WorkCategory, Int64, Int)] { LedgerAnalytics.categories(snapshot.tasks) }
    var dataUnavailable: Bool { rangeReady && snapshot.tasks.isEmpty && activityReady && activity.allSatisfy { $0.responses == 0 } && !snapshot.warnings.isEmpty }
    static let panelWidth: CGFloat = 300
    var panelHeight: CGFloat { !rangeReady || dataUnavailable ? 540 : categoryTotals.isEmpty ? 520 : max(540, 500 + CGFloat(min(categoryTotals.count, 3)) * 20) }
    var scanStatus: String {
        if isLoading { return scanTotal > 0 ? L("正在扫描 \(scanCompleted)/\(scanTotal) 份日志") : L("正在查找日志…") }
        return isComputing ? L("正在汇总用量…") : ""
    }
    func start() {
        applyAppearance()
        if LedgerPreferences.isDemo { loadDemo(); return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let store = self else { return }
            Task { @MainActor in store.refresh() }
        }
    }
    func refresh() {
        if LedgerPreferences.isDemo { loadDemo(); return }
        guard !isLoading else { return }
        isLoading = true; scanCompleted = 0; scanTotal = 0; didUpdate?()
        let path = sourcePath, scanner = self.scanner, begin = Date(), days = goalBook.goals.isEmpty && page != .goals ? max(30, max(loadedDays, scope.days)) : Int.max
        queue.async {
            let result = scanner.scan(root: URL(fileURLWithPath: path), days: days == Int.max ? nil : days) { completed, total in
                if completed % 10 == 0 || completed == total { DispatchQueue.main.async {
                    guard self.sourcePath == path else { return }
                    self.scanCompleted = completed; self.scanTotal = total
                } }
            }
            DispatchQueue.main.async {
                guard self.sourcePath == path else { self.isLoading = false; self.refresh(); return }
                self.logs = result.logs; self.warnings = result.warnings; self.loadedDays = days
                self.lastScanSeconds = Date().timeIntervalSince(begin); self.isLoading = false
                self.recompute()
                if self.scope.days > self.loadedDays || (self.loadedDays != Int.max && (!self.goalBook.goals.isEmpty || self.page == .goals)) { self.refresh() }
            }
        }
    }
    func recompute() {
        if LedgerPreferences.isDemo { loadDemo(); return }
        computeVersion += 1
        guard loadedDays >= scope.days else {
            renderedScope = nil; snapshot = LedgerSnapshot(); isComputing = false; didUpdate?(); return
        }
        isComputing = true; didUpdate?()
        let version = computeVersion, requestedScope = scope, path = sourcePath, logs = self.logs, overrides = self.overrides, warnings = self.warnings
        let calendar = Calendar.current, now = Date(), scanner = self.scanner, resolver = self.resolver, allLoaded = loadedDays == Int.max
        queue.async {
            let root = URL(fileURLWithPath: path)
            var titles = ConversationMetadata.titles(root: root)
            for log in logs where !log.firstPrompt.isEmpty && titles[log.sessionID] == nil { titles[log.sessionID] = log.firstPrompt }
            let todayRange = DateScope.today.interval(now: now, calendar: calendar)
            let today = LedgerAnalytics.enrich(scanner.snapshot(logs: logs, start: todayRange.start, end: todayRange.end, root: path, overrides: overrides, warnings: warnings), resolver: resolver, titles: titles)
            let range = requestedScope.interval(now: now, calendar: calendar)
            var current = requestedScope == .today ? today : LedgerAnalytics.enrich(scanner.snapshot(logs: logs, start: range.start, end: range.end, root: path, overrides: overrides, warnings: warnings), resolver: resolver, titles: titles)
            current.refreshedAt = now; current.timezone = calendar.timeZone.identifier
            let lifetimeRange = DateScope.history.interval(now: now, calendar: calendar)
            let lifetime = allLoaded ? (requestedScope == .history ? current : LedgerAnalytics.enrich(scanner.snapshot(logs: logs, start: lifetimeRange.start, end: lifetimeRange.end, root: path, overrides: overrides, warnings: warnings), resolver: resolver, titles: titles)) : LedgerSnapshot()
            let activity = scanner.dailyUsage(logs: logs, now: now, calendar: calendar)
            DispatchQueue.main.async {
                guard self.computeVersion == version, self.sourcePath == path, self.scope == requestedScope else { return }
                self.today = today; self.todayIsReady = true; self.snapshot = current; self.renderedScope = requestedScope; self.isComputing = false; self.didUpdate?()
                self.lifetime = lifetime; self.lifetimeReady = allLoaded
                self.activity = activity; self.activityReady = true
            }
        }
    }
    func navigate(_ destination: LedgerPage) {
        selectedGoalID = nil; unassignedOnly = false
        page = destination; selectedProjectID = nil; selectedConversationID = nil; selectedTaskID = nil
        categoryFilter = nil; modelFilter = nil; search = ""
        if destination == .goals && !lifetimeReady { refresh() }
    }
    func openProject(_ project: ProjectUsage) {
        selectedGoalID = nil; unassignedOnly = false
        page = .projects; selectedProjectID = project.id; selectedConversationID = nil; selectedTaskID = nil; clearFilters()
    }
    func openConversation(_ chat: ConversationUsage) { selectedConversationID = chat.id; selectedTaskID = nil; clearFilters() }
    func back() {
        if selectedConversationID != nil { selectedConversationID = nil }
        else if selectedProjectID != nil { selectedProjectID = nil }
        else { selectedGoalID = nil }
        selectedTaskID = nil; clearFilters()
    }
    func clearFilters() { search = ""; categoryFilter = nil; modelFilter = nil; unassignedOnly = false }
    var project: ProjectUsage? { snapshot.projects.first { $0.id == selectedProjectID } }
    var contextConversations: [ConversationUsage] { selectedGoalID != nil ? LedgerAnalytics.conversations(goal?.tasks ?? [], titles: Dictionary(uniqueKeysWithValues: snapshot.conversations.map { ($0.id, $0.title) }), projectSets: Dictionary(uniqueKeysWithValues: snapshot.conversations.map { ($0.id, $0.projectIDs) })) : selectedProjectID != nil ? project?.conversations ?? [] : snapshot.conversations }
    var conversation: ConversationUsage? { contextConversations.first { $0.id == selectedConversationID } }
    var contextTasks: [LedgerTask] {
        if selectedConversationID != nil { return conversation?.tasks ?? [] }
        if selectedProjectID != nil { return project?.tasks ?? [] }
        if selectedGoalID != nil { return goal?.tasks ?? [] }
        if page == .goals { return snapshot.tasks.filter { goalBook.owner($0) != nil } }
        if unassignedOnly { return snapshot.tasks.filter { goalBook.owner($0) == nil } }
        return snapshot.tasks
    }
    var filteredTasks: [LedgerTask] {
        contextTasks.filter { task in
            (categoryFilter == nil || task.category == categoryFilter) && (modelFilter == nil || task.models.contains(modelFilter!)) &&
            (search.isEmpty || [task.title, task.workingDirectory, task.projectName, task.sessionID, task.models.joined(separator: " ")].contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }
    var filteredProjects: [ProjectUsage] { snapshot.projects.filter { search.isEmpty || ($0.name == ProjectIdentity.unknown.name ? L($0.name) : $0.name).localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search) } }
    var filteredConversations: [ConversationUsage] {
        contextConversations.filter { chat in search.isEmpty || ([chat.title, chat.id, chat.models.joined(separator: " ")] + chat.tasks.map(\.projectPath)).contains { $0.localizedCaseInsensitiveContains(search) } }
    }
    var filteredModels: [ModelUsage] { snapshot.modelUsage.filter { search.isEmpty || L($0.model).localizedCaseInsensitiveContains(search) } }
    var selectedTasks: [LedgerTask] {
        if page == .goals && selectedGoalID == nil && selectedConversationID == nil { return filteredGoals.flatMap(\.tasks) }
        if page == .projects && selectedProjectID == nil && selectedConversationID == nil { return filteredProjects.flatMap(\.tasks) }
        if selectedConversationID == nil && (page == .conversations || selectedProjectID != nil || selectedGoalID != nil) { return filteredConversations.flatMap(\.tasks) }
        if page == .models {
            let models = Set(filteredModels.map(\.model))
            return contextTasks.compactMap { task in
                let usage = task.modelUsage.filter { models.contains($0.model) }
                guard !usage.isEmpty else { return nil }
                var value = task; value.modelUsage = usage; value.models = usage.map(\.model)
                value.usage = usage.reduce(TokenUsage()) { $0 + $1.usage }; value.responses = usage.reduce(0) { $0 + $1.responses }
                return value
            }
        }
        return filteredTasks
    }
    var contextUsage: TokenUsage { selectedTasks.reduce(TokenUsage()) { $0 + $1.usage } }
    var contextCost: CostEstimate { LedgerPricing.total(selectedTasks) }
    var contextCategories: [(WorkCategory, Int64, Int)] { LedgerAnalytics.categories(selectedTasks) }
    func override(task: LedgerTask, category: WorkCategory?) {
        if let category { overrides[task.id] = category.rawValue } else { overrides.removeValue(forKey: task.id) }
        defaults.set(overrides, forKey: "categoryOverrides"); recompute()
    }
    func manualCategory(_ task: LedgerTask) -> String { overrides[task.id] ?? "auto" }
    func setLanguage(_ value: String) { language = value; LedgerText.language = value; defaults.set(value, forKey: "language"); didUpdate?() }
    func setStatusStyle(_ enabled: Bool) { showFullStatus = enabled; defaults.set(enabled, forKey: "fullStatus"); didUpdate?() }
    func setHeatmapMetric(_ value: String) { heatmapMetric = value; defaults.set(value, forKey: "heatmapMetric") }
    func setAppearance(_ value: String) { appearance = value; defaults.set(value, forKey: "appearance"); applyAppearance() }
    func applyAppearance() { NSApp.appearance = appearance == "light" ? NSAppearance(named: .aqua) : appearance == "dark" ? NSAppearance(named: .darkAqua) : nil }
    func chooseDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.showsHiddenFiles = true
        panel.message = L("选择包含 sessions 的 Codex 数据目录（通常为 ~/.codex）"); panel.directoryURL = URL(fileURLWithPath: sourcePath)
        presentFilePanel(panel) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.sourcePath = url.path; self.defaults.set(url.path, forKey: "sourcePath"); self.logs = []; self.loadedDays = 0
            self.loadGoalBook(); self.lifetime = LedgerSnapshot(); self.lifetimeReady = false; self.selectedGoalID = nil
            self.computeVersion += 1; self.isComputing = false; self.renderedScope = nil; self.snapshot = LedgerSnapshot(); self.today = LedgerSnapshot(); self.todayIsReady = false; self.activity = []; self.activityReady = false; self.didUpdate?(); self.refresh()
        }
    }
    func setLogin(_ enabled: Bool) {
        guard !LedgerPreferences.isDemo else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { errorMessage = L("请在系统设置 → 通用 → 登录项中允许 Codex Ledger。") }
        } catch { errorMessage = L("登录项设置失败：\(error.localizedDescription)"); launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
    func openChat(_ task: LedgerTask) { openChat(id: task.sessionID) }
    func openChat(id: String) { if let url = URL(string: "codex://threads/\(id)") { NSWorkspace.shared.open(url) } }
    func makeShareCard(overview: Bool = false) {
        guard rangeReady, activityReady, !busy, !isSharing, !dataUnavailable, overview || !requiresGoalBook || goalBookReadable else { return }
        let now = snapshot.refreshedAt
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: snapshot.timezone) ?? scanner.calendar.timeZone
        let sourceLogs = logs, goalBook = self.goalBook, path = sourcePath, sourceOverrides = overrides
        let goalID = overview ? nil : selectedGoalID, projectID = overview ? nil : selectedProjectID
        let chatID = overview ? nil : selectedConversationID
        let goalList = !overview && page == .goals && goalID == nil
        let category = overview ? nil : categoryFilter, model = overview ? nil : modelFilter
        let query = overview ? "" : search
        let unassigned = !overview && unassignedOnly
        let listedGoalIDs = Set(filteredGoals.map(\.id))
        let projectList = !overview && page == .projects && projectID == nil && chatID == nil
        let chatList = !overview && chatID == nil && !goalList && (page == .conversations || projectID != nil || goalID != nil)
        let listedProjectIDs = Set(filteredProjects.map(\.id)), listedChatIDs = Set(filteredConversations.map(\.id))
        let selected: [LedgerTask]
        if !overview && page == .models { selected = selectedTasks }
        else if overview { selected = snapshot.tasks }
        else if goalList { selected = snapshot.tasks.filter { task in goalBook.owner(task).map { listedGoalIDs.contains($0) } ?? false } }
        else if projectList { selected = filteredProjects.flatMap(\.tasks) }
        else if chatList { selected = filteredConversations.flatMap(\.tasks) }
        else { selected = filteredTasks }
        let chosenGoal = goalID.flatMap { id in goals.first { $0.id == id } }
        let kind = chatID != nil ? "对话用量" : goalID != nil ? "目标花费" : projectID != nil ? "项目用量" : goalList ? "目标账本" : "用量总览"
        let title = chatID != nil ? conversation?.title ?? L(kind) : chosenGoal?.goal.name ?? project?.name ?? L(kind)
        let interval = scope.interval(now: now, calendar: calendar)
        let range = L(scope.rawValue), priceDate = LedgerPricing.verifiedDate, warning = !snapshot.warnings.isEmpty
        let demoMonth = LedgerPreferences.isDemo ? LedgerDemo.snapshot(scope: .month).tasks : nil
        let metric = heatmapMetric
        let modelPage = !overview && page == .models
        let scanner = self.scanner, resolver = self.resolver
        isSharing = true
        queue.async {
            let monthRange = DateScope.month.interval(now: now, calendar: calendar)
            let monthTasks = demoMonth ?? LedgerAnalytics.enrich(scanner.snapshot(logs: sourceLogs, start: monthRange.start, end: monthRange.end, root: path, overrides: sourceOverrides), resolver: resolver, titles: [:]).tasks
            let monthModels: Set<String>? = modelPage ? Set(monthTasks.flatMap(\.models).filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }) : nil
            let matching = monthTasks.filter { task in
                if let monthModels { return !Set(task.models).isDisjoint(with: monthModels) }
                if let goalID, goalBook.owner(task) != goalID { return false }
                if goalList { return goalBook.owner(task).map { listedGoalIDs.contains($0) } ?? false }
                if unassigned && goalBook.owner(task) != nil { return false }
                if let projectID, task.projectID != projectID { return false }
                if let chatID, task.sessionID != chatID { return false }
                if projectList { return query.isEmpty || listedProjectIDs.contains(task.projectID) }
                if chatList { return query.isEmpty || listedChatIDs.contains(task.sessionID) }
                if let category, task.category != category { return false }
                if let model, !task.models.contains(model) { return false }
                return query.isEmpty || [task.title, task.projectName, task.projectPath, task.workingDirectory, task.sessionID, task.models.joined(separator: " ")].contains { $0.localizedCaseInsensitiveContains(query) }
            }
            let days: [DailyUsage]
            if demoMonth != nil {
                days = (0..<30).map { offset in
                    let date = calendar.date(byAdding: .day, value: offset, to: monthRange.start)!
                    let tasks = matching.filter { calendar.isDate($0.date, inSameDayAs: date) }.map { task -> LedgerTask in
                        guard let monthModels else { return task }; var value = task
                        value.modelUsage = task.modelUsage.filter { monthModels.contains($0.model) }
                        value.usage = value.modelUsage.reduce(TokenUsage()) { $0 + $1.usage }
                        value.responses = value.modelUsage.reduce(0) { $0 + $1.responses }; return value
                    }
                    return DailyUsage(date: date, usage: tasks.reduce(TokenUsage()) { $0 + $1.usage }, responses: tasks.reduce(0) { $0 + $1.responses }, cost: LedgerPricing.total(tasks))
                }
            } else { days = scanner.dailyUsage(logs: sourceLogs, now: now, calendar: calendar, taskIDs: Set(matching.map(\.id)), models: monthModels) }
            let value = ShareSnapshot(kind: kind, privateTitle: title, range: range, timezone: calendar.timeZone.identifier,
                usage: selected.reduce(TokenUsage()) { $0 + $1.usage }, cost: LedgerPricing.total(selected), turns: selected.count,
                conversations: Set(selected.map(\.sessionID)).count, models: Set(selected.flatMap(\.models)).subtracting(["未知模型"]).count,
                days: days, completionCost: chatID == nil ? chosenGoal?.goal.completionCost : nil,
                completionDate: chosenGoal?.goal.completedAt, completionPriceDate: chosenGoal?.goal.completionPriceDate,
                filtered: category != nil || model != nil || !query.isEmpty || unassigned, warning: warning, priceDate: priceDate, capturedAt: now, rangeStart: interval.start, rangeEnd: interval.end, heatmapMetric: metric)
            DispatchQueue.main.async { self.isSharing = false; self.presentShare?(SharePreview(snapshot: value, screenshot: nil)) }
        }
    }
    func exportCSV(models modelMode: Bool? = nil, turns: Bool = false) {
        guard rangeReady, !busy, !dataUnavailable, modelMode != nil || !requiresGoalBook || goalBookReadable else { return }
        let (contents, kind) = csvExport(models: modelMode, turns: turns)
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Codex-\(kind)-\(L(scope.rawValue))-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).csv"
        presentFilePanel(panel) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try contents.write(to: url, atomically: true, encoding: .utf8) }
            catch { self?.errorMessage = L("导出失败：\(error.localizedDescription)") }
        }
    }
    func csvExport(models modelMode: Bool? = nil, turns: Bool = false) -> (String, String) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: snapshot.timezone) ?? scanner.calendar.timeZone
        let range = scope.interval(now: snapshot.refreshedAt, calendar: calendar)
        let context = CSVContext(complete: snapshot.isComplete, warnings: snapshot.warnings, capturedAt: snapshot.refreshedAt, start: range.start, end: range.end, timezone: calendar.timeZone.identifier)
        let contents: String, kind: String
        let names = Dictionary(uniqueKeysWithValues: goalBook.goals.map { ($0.id, $0.name) })
        let goalNames = Dictionary(uniqueKeysWithValues: snapshot.tasks.compactMap { task -> (String, String)? in
            if !goalBookReadable { return (task.id, L("目标账本无法读取，原有数据已保留。")) }
            guard let id = goalBook.owner(task), let name = names[id] else { return nil }; return (task.id, name)
        })
        if let modelMode {
            contents = modelMode ? LedgerCSV.renderModels(snapshot.modelUsage, translate: L, context: context) : LedgerCSV.render(snapshot.tasks, goalNames: goalNames, translate: L, context: context); kind = modelMode ? "Models" : "Tasks"
        } else if page == .goals && conversation == nil {
            let selectedGoals = selectedGoalID == nil ? filteredGoals : goalBook.summaries(current: filteredConversations.flatMap(\.tasks), lifetime: lifetime.tasks).filter { $0.id == selectedGoalID }
            contents = turns ? LedgerCSV.render(filteredTasks, goalNames: goalNames, translate: L, context: context) : LedgerCSV.renderGoals(selectedGoals, scope: L(scope.rawValue), lifetimeReady: goalAmountsReady, translate: L, context: context); kind = turns ? "Goal-Turns" : "Goals"
        } else if let chat = conversation {
            let filteredChat = LedgerAnalytics.conversations(filteredTasks, titles: [chat.id: chat.title], projectSets: [chat.id: chat.projectIDs])
            contents = turns ? LedgerCSV.render(filteredTasks, goalNames: goalNames, translate: L, context: context) : LedgerCSV.renderConversations(filteredChat, projectPath: project?.path, usageScope: selectedGoalID == nil ? nil : L("仅当前目标"), translate: L, context: context); kind = turns ? "Tasks" : "Conversations"
        } else if page == .projects && selectedProjectID == nil {
            contents = LedgerCSV.renderProjects(filteredProjects, translate: L, context: context); kind = "Projects"
        } else if page == .conversations || selectedProjectID != nil {
            contents = LedgerCSV.renderConversations(filteredConversations, projectPath: project?.path, usageScope: selectedGoalID == nil ? nil : L("仅当前目标"), translate: L, context: context); kind = "Conversations"
        } else if page == .models {
            contents = LedgerCSV.renderModels(filteredModels, translate: L, context: context); kind = "Models"
        } else { contents = LedgerCSV.render(filteredTasks, goalNames: goalNames, translate: L, context: context); kind = "Tasks" }
        return (contents, kind)
    }
    private func presentFilePanel(_ panel: NSSavePanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = prepareFilePanel?() { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { NSApp.activate(ignoringOtherApps: true); panel.begin(completionHandler: completion) }
    }
    // A separate attribution book per data root prevents unrelated imports sharing IDs.
    private var goalBookKey: String { "goalBook.v1:" + URL(fileURLWithPath: sourcePath).standardizedFileURL.resolvingSymlinksInPath().path }
    private func loadGoalBook() {
        goalBookReadable = true; goalBook = GoalBook()
        let legacyKey = "goalBook.v1:" + URL(fileURLWithPath: sourcePath).standardizedFileURL.path
        if defaults.data(forKey: goalBookKey) == nil, let old = defaults.data(forKey: legacyKey) { defaults.set(old, forKey: goalBookKey) }
        guard let data = defaults.data(forKey: goalBookKey) else { return }
        do { goalBook = try GoalBook.decode(data) }
        catch { goalBookReadable = false; errorMessage = L("目标账本无法读取，原有数据已保留。") }
    }
    private func saveGoalBook() {
        guard goalBookReadable else { return }
        let previous = defaults.data(forKey: goalBookKey)
        do {
            let next = try JSONEncoder().encode(goalBook)
            if let previous, previous != next { try GoalRecovery.save(previous, source: goalBookKey) }
            defaults.set(next, forKey: goalBookKey)
        } catch {
            if let previous, let old = try? GoalBook.decode(previous) { goalBook = old }
            errorMessage = L("账本备份或保存失败，原有数据未覆盖。")
        }
    }
    func exportGoalBackup() {
        guard goalBookReadable, let data = try? GoalArchive.encode(goalBook) else { errorMessage = L("目标账本无法读取，原有数据已保留。"); return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Codex-Ledger-Goals.json"
        presentFilePanel(panel) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try data.write(to: url, options: .atomic) } catch { self?.errorMessage = L("保存失败，请重试") }
        }
    }
    @discardableResult func importGoalBackup(_ data: Data) -> Bool {
        do {
            let book = try GoalArchive.decode(data)
            if let previous = defaults.data(forKey: goalBookKey) { try GoalRecovery.save(previous, source: goalBookKey) }
            defaults.set(try JSONEncoder().encode(book), forKey: goalBookKey)
            goalBook = book; goalBookReadable = true; errorMessage = nil; navigate(.goals); return true
        } catch { errorMessage = L("备份无效或恢复失败，原有账本未覆盖。"); return false }
    }
    func chooseGoalBackup() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        presentFilePanel(panel) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8 * 1024 * 1024, let data = try? Data(contentsOf: url), (try? GoalArchive.decode(data)) != nil else { self.errorMessage = L("备份无效或恢复失败，原有账本未覆盖。"); return }
            let alert = NSAlert(); alert.messageText = L("导入将替换当前目录的目标账本，原有账本会先备份。")
            alert.addButton(withTitle: L("导入账本")); alert.addButton(withTitle: L("取消"))
            if let window = self.prepareFilePanel?() { alert.beginSheetModal(for: window) { if $0 == .alertFirstButtonReturn { self.importGoalBackup(data) } } }
            else if alert.runModal() == .alertFirstButtonReturn { self.importGoalBackup(data) }
        }
    }
    var goals: [GoalUsage] { goalBook.summaries(current: snapshot.tasks, lifetime: lifetime.tasks) }
    var goalAmountsReady: Bool { lifetimeReady && !dataUnavailable && goalBookReadable && lifetime.isComplete }
    var goal: GoalUsage? { goals.first { $0.id == selectedGoalID } }
    var filteredGoals: [GoalUsage] { goals.filter { search.isEmpty || $0.goal.name.localizedCaseInsensitiveContains(search) || ($0.tasks + $0.lifetimeTasks).contains { [$0.title, $0.projectPath].contains { $0.localizedCaseInsensitiveContains(search) } } } }
    var unassignedTasks: [LedgerTask] { snapshot.tasks.filter { goalBook.owner($0) == nil } }
    func openGoal(_ id: String) {
        page = .goals; selectedGoalID = id; selectedProjectID = nil; selectedConversationID = nil; selectedTaskID = nil; unassignedOnly = false; clearFilters()
        scope = .history
        if !lifetimeReady { refresh() }
    }
    func editGoal(_ goal: LedgerGoal) { goalEditor = GoalEditorDraft(name: goal.name, goalID: goal.id, budget: goal.budgetUSD.map(LedgerPricing.decimalString) ?? "") }
    func newGoal(name: String = "", target: GoalTarget? = nil) {
        guard goalBookReadable else { errorMessage = L("目标账本无法读取，原有数据已保留。"); return }
        goalEditor = GoalEditorDraft(name: name, target: target)
    }
    func saveGoal(name: String, draft: GoalEditorDraft, budgetText: String? = nil) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, goalBookReadable else { return }
        var budget: Decimal?
        if let text = budgetText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let amount = GoalBudget.parse(text) else { errorMessage = L("请输入非负的 USD 预算，最多 8 位小数。"); return }; budget = amount
        }
        if let id = draft.goalID, let index = goalBook.goals.firstIndex(where: { $0.id == id }) { goalBook.goals[index].name = String(name.prefix(160)); if budgetText != nil { goalBook.goals[index].budgetUSD = budget } }
        else {
            let goal = LedgerGoal(name: String(name.prefix(160)), budgetUSD: budget); goalBook.goals.append(goal)
            if let target = draft.target { goalBook.assign(target, to: goal.id) }
            saveGoalBook(); goalEditor = nil; openGoal(goal.id); return
        }
        saveGoalBook(); goalEditor = nil
    }
    func assignGoal(_ target: GoalTarget, to id: String?) {
        guard goalBookReadable, id == nil || goalBook.goals.contains(where: { $0.id == id }) else { return }
        goalBook.assign(target, to: id); saveGoalBook()
        if !lifetimeReady { refresh() }
    }
    func resetGoalAssignment(_ target: GoalTarget) {
        guard goalBookReadable else { return }
        goalBook.bindings.removeValue(forKey: target.key); saveGoalBook()
    }
    func completeGoal(_ id: String) {
        guard goalBookReadable, let index = goalBook.goals.firstIndex(where: { $0.id == id }) else { return }
        if goalBook.goals[index].completedAt == nil {
            guard goalAmountsReady, !busy, let entry = goals.first(where: { $0.id == id }) else { return }
            goalBook.goals[index].completedAt = Date()
            goalBook.goals[index].completionCost = entry.lifetimeCost
            goalBook.goals[index].completionUsage = entry.lifetimeUsage
            goalBook.goals[index].completionPriceDate = LedgerPricing.verifiedDate
        } else {
            goalBook.goals[index].completedAt = nil; goalBook.goals[index].completionCost = nil; goalBook.goals[index].completionUsage = nil; goalBook.goals[index].completionPriceDate = nil
        }
        saveGoalBook()
    }
    func deleteGoal(_ id: String) {
        guard goalBookReadable else { return }
        goalBook.remove(id); saveGoalBook()
        if selectedGoalID == id { navigate(.goals) }
    }
    func showUnassigned() { navigate(.tasks); unassignedOnly = true }
    func loadDemo() {
        let scenario = ProcessInfo.processInfo.environment["CODEX_LEDGER_DEMO_STATE"] ?? (Bundle.main.object(forInfoDictionaryKey: "LedgerDemoState") as? String) ?? "ready"
        loadedDays = Int.max; renderedScope = scenario == "loading" ? nil : scope; isComputing = false; isLoading = scenario == "loading"
        scanCompleted = 12; scanTotal = 80
        snapshot = LedgerDemo.snapshot(empty: scenario != "ready", error: scenario == "error", scope: scope)
        today = LedgerDemo.snapshot(empty: scenario != "ready", error: scenario == "error"); todayIsReady = scenario != "loading"
        activity = LedgerDemo.activity(empty: scenario != "ready")
        activityReady = scenario != "loading"
        lifetime = LedgerDemo.snapshot(empty: scenario != "ready", error: scenario == "error", scope: .history)
        lifetimeReady = scenario != "loading"; didUpdate?()
    }
}
