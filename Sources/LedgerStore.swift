import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import CryptoKit

struct ViewContext {
    var page: LedgerPage
    var goal: String?
    var project: String?
    var conversation: String?
    var scope: DateScope
    var search: String
    var category: WorkCategory?
    var model: String?
    var day: Date?
    var unassigned: Bool
    var sort = "cost"
    var scrollID: String?
}

enum LedgerPage: String { case goals, tasks, projects, conversations, models, settings }

enum LedgerPreferences {
    static let isDemo = CommandLine.arguments.contains("--demo") || (Bundle.main.object(forInfoDictionaryKey: "LedgerDemo") as? Bool == true)
    static let defaults: UserDefaults = isDemo ? UserDefaults(suiteName: (Bundle.main.bundleIdentifier ?? "local.codexledger") + ".demo")! : .standard
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
    @Published var contextActivity: [DailyUsage] = []
    private var activityVersion = 0
    @Published var snapshot = LedgerSnapshot() { didSet { goalSummaries = nil } }
    @Published var overviewSnapshot = LedgerSnapshot()
    @Published var overviewReady = false
    @Published var overviewScope: DateScope = .today { didSet { defaults.set(overviewScope.rawValue, forKey: "overviewDateScope"); updateOverview() } }
    @Published var selectedDay: Date?
    private var navigation: [ViewContext] = []
    private var pageContexts: [LedgerPage: ViewContext] = [:]
    var viewContext: ViewContext { ViewContext(page: page, goal: selectedGoalID, project: selectedProjectID, conversation: selectedConversationID, scope: scope, search: search, category: categoryFilter, model: modelFilter, day: selectedDay, unassigned: unassignedOnly, sort: sortOrder, scrollID: scrollAnchor) }
    private func restore(_ c: ViewContext) { page = c.page; selectedGoalID = goalBook.goals.contains { $0.id == c.goal } ? c.goal : nil; selectedProjectID = c.project; selectedConversationID = c.conversation; scope = c.scope; search = c.search; categoryFilter = c.category; modelFilter = c.model; selectedDay = c.day; unassignedOnly = c.unassigned; sortOrder = c.sort; scrollAnchor = c.scrollID; selectedTaskID = nil }
    @Published var scope: DateScope = .today { didSet {
        guard scope != oldValue else { return }
        defaults.set(scope.rawValue, forKey: "dashboardDateScope"); selectedDay = nil
        selectedTaskID = nil; recompute(reuseHistory: true)
        if scope.days > loadedDays { refresh() }
    } }
    @Published var isLoading = false
    @Published var isComputing = false
    @Published var page: LedgerPage = .goals
    @Published var goalBook = GoalBook() { didSet { goalSummaries = nil } }
    @Published var goalEditor: GoalEditorDraft?
    @Published var assignmentDraft: AssignmentDraft?
    private var undoBooks: [AttributionState] = []
    var canUndoAttribution: Bool { !undoBooks.isEmpty }
    func undoAttribution() { guard let previous = undoBooks.popLast() else { return }; goalBook.rules = previous.rules; goalBook.bindings = previous.bindings
        for i in goalBook.rules.indices where !goalBook.rules[i].legacy && goalBook.rules[i].mode != .selected && goalBook.rules[i].end == nil {
            if let completed = goalBook.goals.first(where: { $0.id == goalBook.rules[i].goalID })?.completedAt { goalBook.rules[i].end = completed }
        }
        saveGoalBook() }
    func beginAssignment(goalID: String, target: GoalTarget? = nil) { assignmentDraft = AssignmentDraft(goalID: goalID, target: target) }
    func saveAssignment(_ rule: AttributionRule) { undoBooks.append(AttributionState(rules: goalBook.rules, bindings: goalBook.bindings)); goalBook.apply(rule); saveGoalBook(); assignmentDraft = nil }

    @Published var selectedGoalID: String?
    @Published var unassignedOnly = false
    @Published var lifetime = LedgerSnapshot() { didSet { goalSummaries = nil } }
    @Published var lifetimeReady = false
    private var goalBookReadable = true
    @Published var sortOrder = "cost"
    @Published var scrollAnchor: String?
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
    @Published var lastCheckedAt = Date()
    var didUpdate: (() -> Void)?
    @Published var isSharing = false
    var presentShare: ((SharePreview) -> Void)?
    var captureInterface: ((Bool) -> Void)?
    var prepareFilePanel: (() -> NSWindow?)?
    private var logs: [ParsedLog] = []
    private var publishedLogs: [ParsedLog] = []
    private var loadedDays = 0
    private var renderedScope: DateScope?
    private var warnings: [String] = []
    private var overrides: [String: String]
    private var computeVersion = 0
    private var logsRevision = 0
    private var lastComputedRevision = -1
    private var lastComputationDay: Date?
    private var lastComputationTimezone = ""
    private var lastComputationTime = Date.distantPast
    private var lastComputedOverrides: [String: String] = [:]
    private var cachedTitles: [String: String] = [:]
    private var goalSummaries: [GoalUsage]?
    private(set) var computationCount = 0
    private(set) var historyAggregationCount = 0
    private let queue = DispatchQueue(label: "local.codexledger.scan", qos: .utility)
    private let scanQueue = DispatchQueue(label: "local.codexledger.files", qos: .utility)
    private let scanner: LedgerScanner
    private let resolver = ProjectResolver()
    private var timer: Timer?
    private let defaults: UserDefaults
    var showSettings: Bool {
        get { page == .settings }
        set { if newValue { page = .settings } else if page == .settings { page = .tasks } }
    }
    var showModels: Bool {
        get { page == .models }
        set { if newValue { page = .models } else if page == .models { page = .tasks } }
    }
    init(sourcePath: String? = nil, defaults: UserDefaults = LedgerPreferences.defaults, scanner: LedgerScanner? = nil) {
        self.defaults = defaults
        self.scanner = scanner ?? LedgerScanner(cacheDirectory: LedgerPreferences.isDemo ? nil : LedgerScanner.applicationCacheDirectory)
        let fallback = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        self.sourcePath = sourcePath ?? (LedgerPreferences.isDemo ? "/Users/demo/.codex" : defaults.string(forKey: "sourcePath") ?? fallback)
        overrides = defaults.dictionary(forKey: "categoryOverrides") as? [String: String] ?? [:]
        language = defaults.string(forKey: "language") ?? "en"
        appearance = defaults.string(forKey: "appearance") ?? "system"
        heatmapMetric = defaults.string(forKey: "heatmapMetric") ?? "tokens"
        loadGoalBook()
        scope = defaults.string(forKey: "dashboardDateScope").flatMap(DateScope.init(rawValue:)) ?? .today
        overviewScope = defaults.string(forKey: "overviewDateScope").flatMap(DateScope.init(rawValue:)) ?? .today
        LedgerText.language = language
        showFullStatus = defaults.object(forKey: "fullStatus") as? Bool ?? true
        launchAtLogin = !LedgerPreferences.isDemo && SMAppService.mainApp.status == .enabled
    }
    private func updateOverview() {
        if overviewScope == .today && todayIsReady { overviewSnapshot = today; overviewReady = true; return }
        if overviewScope == .history && lifetimeReady { overviewSnapshot = lifetime; overviewReady = true; return }
        if LedgerPreferences.isDemo { overviewSnapshot = LedgerDemo.snapshot(scope: overviewScope); overviewReady = true; return }
        let requested = overviewScope, sourceLogs = logs, scanner = scanner, path = sourcePath, warnings = warnings, now = snapshot.refreshedAt, calendar = Calendar.current, overrides = overrides
        guard loadedDays >= requested.days else { overviewReady = false; refresh(); return }
        let resolver = self.resolver
        queue.async {
            let range = requested.interval(now: now, calendar: calendar)
            let value = LedgerAnalytics.enrich(scanner.snapshot(logs: sourceLogs, start: range.start, end: range.end, root: path, overrides: overrides, warnings: warnings), resolver: resolver, titles: [:])
            DispatchQueue.main.async { guard self.overviewScope == requested, self.sourcePath == path else { return }; self.overviewSnapshot = value; self.overviewReady = true; self.didUpdate?() }
        }
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
    @Published var categoriesExpanded = false { didSet { didUpdate?() } }
    var panelHeight: CGFloat { 410 + (categoriesExpanded ? CGFloat(min(categoryTotals.count, 3)) * 40 : 0) + CGFloat(min(goals.count, 2)) * 30 + (snapshot.warnings.isEmpty ? 0 : 30) }
    var scanStatus: String {
        if isLoading { return scanTotal > 0 ? L("正在扫描 \(scanCompleted)/\(scanTotal) 份日志") : L("正在查找日志…") }
        return isComputing ? L("正在汇总用量…") : ""
    }
    func start() {
        applyAppearance()
        if LedgerPreferences.isDemo { loadDemo(); return }
        refresh(recentFirst: true)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let store = self else { return }
            Task { @MainActor in store.refresh(force: false) }
        }
    }
    func refresh(force: Bool = true, recentFirst: Bool = false) {
        if LedgerPreferences.isDemo { loadDemo(); return }
        guard !busy else { return }
        isLoading = true; scanCompleted = 0; scanTotal = 0; didUpdate?()
        let path = sourcePath, scanner = self.scanner, begin = Date(), days = recentFirst ? max(30, scope.days) : (goalBook.goals.isEmpty && page != .goals ? max(30, max(loadedDays, max(scope.days, overviewScope.days))) : Int.max)
        // History parsing cannot hold up a date switch using already loaded logs.
        scanQueue.async {
            var lastProgress = Date.distantPast
            let result = scanner.scan(root: URL(fileURLWithPath: path), days: days == Int.max ? nil : days) { completed, total in
                let now = Date()
                if completed == 0 || completed == total || now.timeIntervalSince(lastProgress) >= 0.2 {
                    lastProgress = now
                    DispatchQueue.main.async {
                    guard self.sourcePath == path else { return }
                    self.scanCompleted = completed; self.scanTotal = total
                    }
                }
            }
            DispatchQueue.main.async {
                guard self.sourcePath == path else { self.isLoading = false; self.refresh(); return }
                self.logs = result.logs; self.warnings = result.warnings; self.loadedDays = days
                self.logsRevision = result.revision
                self.lastCheckedAt = Date(); self.lastScanSeconds = self.lastCheckedAt.timeIntervalSince(begin); self.isLoading = false
                // A lightweight manifest check every 30 seconds is enough when nothing
                // changed. Refresh enrichment periodically to notice titles/repos/files.
                if force || !self.canReuseHistory || !self.rangeReady { self.recompute() }
                else { self.didUpdate?() }
                if max(self.scope.days, self.overviewScope.days) > self.loadedDays || (self.loadedDays != Int.max && (!self.goalBook.goals.isEmpty || self.page == .goals)) {
                    self.refreshAfterComputation = true
                    if !self.busy { self.refreshAfterComputation = false; self.refresh() }
                }
            }
        }
    }
    private var refreshAfterComputation = false
    private var canReuseHistory: Bool {
        lastComputedRevision == logsRevision && lastComputationDay == Calendar.current.startOfDay(for: Date()) &&
        lastComputationTimezone == Calendar.current.timeZone.identifier && lastComputedOverrides == overrides &&
        Date().timeIntervalSince(lastComputationTime) < 300
    }
    func recompute(reuseHistory: Bool = false) {
        if LedgerPreferences.isDemo { loadDemo(); return }
        computeVersion += 1
        guard loadedDays >= scope.days else {
            renderedScope = nil; snapshot = LedgerSnapshot(); isComputing = false; didUpdate?(); return
        }
        isComputing = true; didUpdate?()
        let version = computeVersion, requestedScope = scope, path = sourcePath, logs = self.logs, overrides = self.overrides, warnings = self.warnings
        let calendar = Calendar.current, now = Date(), scanner = self.scanner, resolver = self.resolver, allLoaded = loadedDays == Int.max
        let reuse = reuseHistory && canReuseHistory
        computationCount += 1
        if !reuse && allLoaded { historyAggregationCount += 1 }
        let previousToday = today, previousLifetime = lifetime, previousActivity = activity, previousTitles = cachedTitles, revision = logsRevision
        queue.async {
            let root = URL(fileURLWithPath: path)
            var titles = reuse ? previousTitles : ConversationMetadata.titles(root: root)
            for log in logs where !log.firstPrompt.isEmpty && titles[log.sessionID] == nil { titles[log.sessionID] = log.firstPrompt }
            let todayRange = DateScope.today.interval(now: now, calendar: calendar)
            let today = reuse ? previousToday : LedgerAnalytics.enrich(scanner.snapshot(logs: logs, start: todayRange.start, end: todayRange.end, root: path, overrides: overrides, warnings: warnings), resolver: resolver, titles: titles)
            let range = requestedScope.interval(now: now, calendar: calendar)
            var current = requestedScope == .today ? today : (requestedScope == .history && reuse && allLoaded ? previousLifetime : LedgerAnalytics.enrich(scanner.snapshot(logs: logs, start: range.start, end: range.end, root: path, overrides: overrides, warnings: warnings), resolver: resolver, titles: titles))
            current.refreshedAt = now; current.timezone = calendar.timeZone.identifier
            let lifetimeRange = DateScope.history.interval(now: now, calendar: calendar)
            let lifetime = allLoaded ? (requestedScope == .history ? current : (reuse ? previousLifetime : LedgerAnalytics.enrich(scanner.snapshot(logs: logs, start: lifetimeRange.start, end: lifetimeRange.end, root: path, overrides: overrides, warnings: warnings), resolver: resolver, titles: titles))) : LedgerSnapshot()
            let activity = reuse ? previousActivity : scanner.dailyUsage(logs: logs, now: now, calendar: calendar)
            DispatchQueue.main.async {
                guard self.computeVersion == version, self.sourcePath == path, self.scope == requestedScope else { return }
                self.publishedLogs = logs
                self.today = today; self.todayIsReady = true; self.snapshot = current; self.renderedScope = requestedScope; self.isComputing = false; self.didUpdate?()
                self.lifetime = lifetime; self.lifetimeReady = allLoaded
                self.activity = activity; self.activityReady = true; self.updateOverview()
                self.lastComputedRevision = revision; self.cachedTitles = titles
                self.lastComputationDay = calendar.startOfDay(for: now); self.lastComputationTimezone = calendar.timeZone.identifier
                self.lastComputedOverrides = overrides
                if !reuse { self.lastComputationTime = now }
                if self.refreshAfterComputation { self.refreshAfterComputation = false; self.refresh() }
            }
        }
    }
    func navigate(_ destination: LedgerPage) {
        pageContexts[page] = viewContext; navigation.removeAll()
        if let previous = pageContexts[destination] { restore(previous) }
        else { page = destination; selectedGoalID = nil; selectedProjectID = nil; selectedConversationID = nil; selectedTaskID = nil; clearFilters() }
        if destination == .goals && !lifetimeReady { refresh() }
    }
    func openProject(_ project: ProjectUsage) {
        navigation.append(viewContext)
        selectedGoalID = nil; unassignedOnly = false; page = .projects; selectedProjectID = project.id; selectedConversationID = nil; selectedTaskID = nil; clearFilters()
    }
    func openConversation(_ chat: ConversationUsage) { navigation.append(viewContext); selectedConversationID = chat.id; selectedTaskID = nil; clearFilters() }
    func back() {
        if let previous = navigation.popLast() { restore(previous); return }
        if selectedConversationID != nil { selectedConversationID = nil }
        else if selectedProjectID != nil { selectedProjectID = nil }
        else { selectedGoalID = nil }
        selectedTaskID = nil
    }
    func showDay(_ day: Date) { navigate(.tasks); scope = .month; selectedDay = Calendar.current.startOfDay(for: day) }
    func clearFilters() { selectedDay = nil; search = ""; categoryFilter = nil; modelFilter = nil; unassignedOnly = false }
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
        applyUsageFilters(contextTasks).filter { task in
            (categoryFilter == nil || task.category == categoryFilter) && (modelFilter == nil || task.models.contains(modelFilter!)) &&
            (search.isEmpty || [task.title, task.workingDirectory, task.projectName, task.sessionID, task.models.joined(separator: " ")].contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }
    var filteredProjects: [ProjectUsage] { LedgerAnalytics.projects(applyUsageFilters(snapshot.tasks), titles: cachedTitles).filter { search.isEmpty || ($0.name == ProjectIdentity.unknown.name ? L($0.name) : $0.name).localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search) }.sorted { a, b in sortOrder == "recent" ? a.lastActivity > b.lastActivity : sortOrder == "tokens" ? a.usage.total > b.usage.total : a.cost.totalUSD > b.cost.totalUSD } }
    var filteredConversations: [ConversationUsage] {
        let titles = Dictionary(uniqueKeysWithValues: contextConversations.map { ($0.id, $0.title) })
        let sets = Dictionary(uniqueKeysWithValues: contextConversations.map { ($0.id, $0.projectIDs) })
        return LedgerAnalytics.conversations(applyUsageFilters(contextConversations.flatMap(\.tasks)), titles: titles, projectSets: sets).filter { chat in search.isEmpty || ([chat.title, chat.id, chat.models.joined(separator: " ")] + chat.tasks.map(\.projectPath)).contains { $0.localizedCaseInsensitiveContains(search) } }.sorted { a, b in sortOrder == "recent" ? a.lastActivity > b.lastActivity : sortOrder == "tokens" ? a.usage.total > b.usage.total : a.cost.totalUSD > b.cost.totalUSD }
    }
    var filteredModels: [ModelUsage] { LedgerAnalytics.models(applyUsageFilters(contextTasks)).filter { search.isEmpty || L($0.model).localizedCaseInsensitiveContains(search) } }
    private var baseSelectedTasks: [LedgerTask] {
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
    func applyUsageFilters(_ input: [LedgerTask]) -> [LedgerTask] {
        input.compactMap { task -> LedgerTask? in
            guard categoryFilter == nil || task.category == categoryFilter else { return nil }
            var value = task
            if let day = selectedDay {
                if value.samples.isEmpty { guard Calendar.current.isDate(value.date, inSameDayAs: day) else { return nil } }
                else {
                    let samples = value.samples.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
                    guard !samples.isEmpty else { return nil }
                    value.samples = samples; value.usage = samples.reduce(TokenUsage()) { $0 + $1.usage }
                    value.modelUsage = Dictionary(grouping: samples, by: \.model).map { name, calls in ModelUsage(model: name, usage: calls.reduce(TokenUsage()) { $0 + $1.usage }, responses: calls.count, taskIDs: [task.id], cost: calls.reduce(CostEstimate()) { $0 + $1.cost }) }
                    value.date = samples.map(\.date).min()!; value.lastActivity = samples.map(\.date).max()!; value.responses = samples.count
                }
            }
            if let model = modelFilter {
                let usages = value.modelUsage.filter { $0.model == model }; guard !usages.isEmpty else { return nil }
                value.modelUsage = usages; value.models = [model]; value.usage = usages.reduce(TokenUsage()) { $0 + $1.usage }; value.responses = usages.reduce(0) { $0 + $1.responses }
                value.samples = value.samples.filter { $0.model == model }
            }
            return value
        }
    }
    var selectedTasks: [LedgerTask] { applyUsageFilters(baseSelectedTasks) }
    var contextCoverage: AccountingCoverage { AccountingCoverage.evaluate(snapshot, turnIDs: Set(selectedTasks.map(\.id)), loaded: rangeReady, interval: effectiveInterval) }
    var effectiveInterval: DateInterval {
        if let day = selectedDay { return DateInterval(start: day, end: Calendar.current.date(byAdding: .day, value: 1, to: day)!) }
        return scope.interval(now: snapshot.refreshedAt, calendar: Calendar.current)
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
    func updateContextActivity() {
        activityVersion += 1
        let version = activityVersion, logs = publishedLogs, capturedAt = snapshot.refreshedAt, book = goalBook, goal = selectedGoalID, project = selectedProjectID, chat = selectedConversationID, query = search, category = categoryFilter, model = modelFilter, scanner = scanner, resolver = resolver, titles = cachedTitles
        let demo = LedgerPreferences.isDemo ? LedgerDemo.snapshot(scope: .month).tasks : nil
        queue.async {
            let range = DateScope.month.interval(now: capturedAt, calendar: scanner.calendar)
            let tasks = demo ?? LedgerAnalytics.enrich(scanner.snapshot(logs: logs, start: range.start, end: range.end), resolver: resolver, titles: titles).tasks
            let selected = tasks.filter { task in
                (goal == nil || book.owner(task) == goal) && (project == nil || task.projectID == project) && (chat == nil || task.sessionID == chat) && (category == nil || task.category == category) && (query.isEmpty || [task.title, task.projectName, task.projectPath, titles[task.sessionID] ?? ""].contains { $0.localizedCaseInsensitiveContains(query) })
            }
            let days = scanner.dailyUsage(logs: logs, now: capturedAt, taskIDs: Set(selected.map(\.id)), models: model.map { Set([$0]) })
            DispatchQueue.main.async { guard self.activityVersion == version else { return }; self.contextActivity = demo == nil ? days : (0..<30).map { offset in
                    let date = scanner.calendar.date(byAdding: .day, value: offset, to: range.start)!
                    let matching = selected.filter { scanner.calendar.isDate($0.date, inSameDayAs: date) }.map { task -> LedgerTask in
                        guard let model else { return task }; var value = task; value.modelUsage = task.modelUsage.filter { $0.model == model }; value.usage = value.modelUsage.reduce(TokenUsage()) { $0 + $1.usage }; return value
                    }
                    return DailyUsage(date: date, usage: matching.reduce(TokenUsage()) { $0 + $1.usage }, responses: matching.reduce(0) { $0 + $1.responses }, cost: LedgerPricing.total(matching))
                } }
        }
    }
    func makeShareCard(overview: Bool = false) {
        guard overview ? overviewReady : rangeReady, activityReady, !isSharing, !dataUnavailable, overview || !requiresGoalBook || goalBookReadable else { return }
        let snapshot = overview ? overviewSnapshot : self.snapshot
        let scope = overview ? overviewScope : self.scope
        let now = snapshot.refreshedAt
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: snapshot.timezone) ?? scanner.calendar.timeZone
        let sourceLogs = publishedLogs, goalBook = self.goalBook, path = sourcePath, sourceOverrides = overrides
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
        else if goalList { selected = selectedTasks }
        else if projectList { selected = selectedTasks }
        else if chatList { selected = selectedTasks }
        else { selected = selectedTasks }
        let chosenGoal = goalID.flatMap { id in goals.first { $0.id == id } }
        let kind = chatID != nil ? "对话用量" : goalID != nil ? "目标花费" : projectID != nil ? "项目用量" : goalList ? "目标账本" : "用量总览"
        let title = chatID != nil ? conversation?.title ?? L(kind) : chosenGoal?.goal.name ?? project?.name ?? L(kind)
        let interval = overview || selectedDay == nil ? scope.interval(now: now, calendar: calendar) : effectiveInterval
        let range = overview || selectedDay == nil ? L(scope.rawValue) : L("仅此日"), priceDate = LedgerPricing.verifiedDate, warning = !AccountingCoverage.evaluate(snapshot, turnIDs: Set(selected.map(\.id))).canComplete
        let demoMonth = LedgerPreferences.isDemo ? LedgerDemo.snapshot(scope: .month).tasks : nil
        let coverage = AccountingCoverage.evaluate(snapshot, turnIDs: Set(selected.map(\.id)), interval: interval)
        let shareContext = ShareContext(kind: kind, entityID: chatID ?? projectID ?? goalID, query: query, category: category?.rawValue, model: model, start: interval.start, end: interval.end, timezone: calendar.timeZone.identifier, coverage: coverage, capturedAt: now, completion: chosenGoal?.goal.completedAt == nil ? nil : chosenGoal?.goal.completions.last)
        let metric = heatmapMetric
        let modelPage = !overview && page == .models
        let scanner = self.scanner, resolver = self.resolver
        isSharing = true
        queue.async {
            let monthRange = DateScope.month.interval(now: now, calendar: calendar)
            let monthTasks = demoMonth ?? LedgerAnalytics.enrich(scanner.snapshot(logs: sourceLogs, start: monthRange.start, end: monthRange.end, root: path, overrides: sourceOverrides), resolver: resolver, titles: [:]).tasks
            let monthModels: Set<String>? = model.map { Set([$0]) } ?? (modelPage ? Set(monthTasks.flatMap(\.models).filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }) : nil)
            let matching = monthTasks.filter { task in
                if let monthModels { return !Set(task.models).isDisjoint(with: monthModels) }
                if let category, task.category != category { return false }
                if let goalID, goalBook.owner(task) != goalID { return false }
                if goalList && !(goalBook.owner(task).map { listedGoalIDs.contains($0) } ?? false) { return false }
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
                filtered: category != nil || model != nil || !query.isEmpty || unassigned, warning: warning, priceDate: priceDate, capturedAt: now, rangeStart: interval.start, rangeEnd: interval.end, heatmapMetric: metric, context: shareContext)
            DispatchQueue.main.async { self.isSharing = false; self.presentShare?(SharePreview(snapshot: value, screenshot: nil)) }
        }
    }
    func exportCSV(models modelMode: Bool? = nil, turns: Bool = false) {
        guard modelMode != nil ? overviewReady : rangeReady, !dataUnavailable, modelMode != nil || !requiresGoalBook || goalBookReadable else { return }
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
        let snapshot = modelMode == nil ? self.snapshot : overviewSnapshot
        let scope = modelMode == nil ? self.scope : overviewScope
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: snapshot.timezone) ?? scanner.calendar.timeZone
        let range = modelMode != nil || selectedDay == nil ? scope.interval(now: snapshot.refreshedAt, calendar: calendar) : effectiveInterval
        let coverage = modelMode != nil ? AccountingCoverage.evaluate(snapshot) : contextCoverage
        let context = CSVContext(complete: coverage.canComplete, warnings: coverage.reasons, capturedAt: snapshot.refreshedAt, start: range.start, end: range.end, timezone: calendar.timeZone.identifier)
        let contents: String, kind: String
        let names = Dictionary(uniqueKeysWithValues: goalBook.goals.map { ($0.id, $0.name) })
        let goalNames = Dictionary(uniqueKeysWithValues: snapshot.tasks.compactMap { task -> (String, String)? in
            if !goalBookReadable { return (task.id, L("目标账本无法读取，原有数据已保留。")) }
            guard let id = goalBook.owner(task), let name = names[id] else { return nil }; return (task.id, name)
        })
        if let modelMode {
            contents = modelMode ? LedgerCSV.renderModels(snapshot.modelUsage, translate: L, context: context) : LedgerCSV.render(snapshot.tasks, goalNames: goalNames, translate: L, context: context); kind = modelMode ? "Models" : "Tasks"
        } else if page == .goals && conversation == nil {
            let selectedGoals = selectedGoalID == nil ? filteredGoals : goalBook.summaries(current: selectedTasks, lifetime: lifetime.tasks).filter { $0.id == selectedGoalID }
            contents = turns ? LedgerCSV.render(selectedTasks, goalNames: goalNames, translate: L, context: context) : LedgerCSV.renderGoals(selectedGoals, scope: L(scope.rawValue), lifetimeReady: goalAmountsReady, translate: L, context: context, coverageByGoal: Dictionary(uniqueKeysWithValues: selectedGoals.map { ($0.id, goalCoverage($0.id)) })); kind = turns ? "Goal-Turns" : "Goals"
        } else if let chat = conversation {
            let filteredChat = LedgerAnalytics.conversations(selectedTasks, titles: [chat.id: chat.title], projectSets: [chat.id: chat.projectIDs])
            contents = turns ? LedgerCSV.render(selectedTasks, goalNames: goalNames, translate: L, context: context) : LedgerCSV.renderConversations(filteredChat, projectPath: project?.path, usageScope: selectedGoalID == nil ? nil : L("仅当前目标"), translate: L, context: context); kind = turns ? "Tasks" : "Conversations"
        } else if page == .projects && selectedProjectID == nil {
            contents = LedgerCSV.renderProjects(LedgerAnalytics.projects(selectedTasks, titles: cachedTitles), translate: L, context: context); kind = "Projects"
        } else if page == .conversations || selectedProjectID != nil {
            contents = LedgerCSV.renderConversations(LedgerAnalytics.conversations(selectedTasks, titles: cachedTitles), projectPath: project?.path, usageScope: selectedGoalID == nil ? nil : L("仅当前目标"), translate: L, context: context); kind = "Conversations"
        } else if page == .models {
            contents = LedgerCSV.renderModels(filteredModels, translate: L, context: context); kind = "Models"
        } else { contents = LedgerCSV.render(selectedTasks, goalNames: goalNames, translate: L, context: context); kind = "Tasks" }
        return (contents, kind)
    }
    private func presentFilePanel(_ panel: NSSavePanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = prepareFilePanel?() { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { NSApp.activate(ignoringOtherApps: true); panel.begin(completionHandler: completion) }
    }
    // A separate attribution book per data root prevents unrelated imports sharing IDs.
    private var usesFileBook: Bool { !LedgerPreferences.isDemo && defaults === UserDefaults.standard }
    private var goalBookURL: URL {
        let digest = SHA256.hash(data: Data(goalBookKey.utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CodexLedger/GoalBooks/" + digest + "-v2.json")
    }
    private var storedGoalData: Data? { usesFileBook && FileManager.default.fileExists(atPath: goalBookURL.path) ? try? Data(contentsOf: goalBookURL) : defaults.data(forKey: goalBookKey) }
    private func writeGoalData(_ data: Data) throws {
        if usesFileBook {
            try FileManager.default.createDirectory(at: goalBookURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: goalBookURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: goalBookURL.path)
        } else { defaults.set(data, forKey: goalBookKey) }
    }
    private var goalBookKey: String { "goalBook.v2:" + URL(fileURLWithPath: sourcePath).standardizedFileURL.resolvingSymlinksInPath().path }
    private func loadGoalBook() {
        goalBookReadable = true; goalBook = GoalBook()
        let canonical = URL(fileURLWithPath: sourcePath).standardizedFileURL.resolvingSymlinksInPath().path
        let legacyKeys = ["goalBook.v1:" + canonical, "goalBook.v1:" + URL(fileURLWithPath: sourcePath).standardizedFileURL.path]
        do {
            if usesFileBook && FileManager.default.fileExists(atPath: goalBookURL.path) { goalBook = try GoalBook.decode(Data(contentsOf: goalBookURL)); return }
            if let data = defaults.data(forKey: goalBookKey) { goalBook = try GoalBook.decode(data); if usesFileBook { try writeGoalData(data) }; return }
            if let original = legacyKeys.compactMap({ defaults.data(forKey: $0) }).first {
                let migrated = try GoalBook.decode(original)
                // Preserve the exact v1 bytes as well as the portable recovery copy.
                try FileManager.default.createDirectory(at: GoalRecovery.directory, withIntermediateDirectories: true)
                try original.write(to: GoalRecovery.directory.appendingPathComponent("v1-original-" + UUID().uuidString + ".recovery.bin"), options: .atomic)
                try writeGoalData(JSONEncoder().encode(migrated))
                goalBook = migrated
            }
        } catch { goalBookReadable = false; errorMessage = L("目标账本无法读取，原有数据已保留。") }
    }

    private func saveGoalBook() {
        guard goalBookReadable else { return }
        let previous = storedGoalData
        do {
            let next = try JSONEncoder().encode(goalBook)
            if let previous, previous != next { try GoalRecovery.save(previous, source: goalBookKey) }
            try writeGoalData(next)
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
            if let previous = storedGoalData { try GoalRecovery.save(previous, source: goalBookKey) }
            try writeGoalData(JSONEncoder().encode(book))
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
    var goals: [GoalUsage] {
        if let goalSummaries { return goalSummaries }
        let value = goalBook.summaries(current: snapshot.tasks, lifetime: lifetime.tasks)
        goalSummaries = value
        return value
    }
    var goalAmountsReady: Bool { lifetimeReady && goalBookReadable }
    func goalCoverage(_ id: String) -> AccountingCoverage {
        AccountingCoverage.evaluate(lifetime, turnIDs: Set(lifetime.tasks.filter { goalBook.owner($0) == id }.map(\.id)), loaded: lifetimeReady)
    }
    func canCompleteGoal(_ id: String) -> Bool { goalAmountsReady && !busy && goalCoverage(id).canComplete }
    func postCompletionTasks(_ id: String) -> [LedgerTask] {
        guard let at = goalBook.goals.first(where: { $0.id == id })?.completions.last?.completedAt else { return [] }
        return lifetime.tasks.filter { goalBook.owner($0) == id }.compactMap { task -> LedgerTask? in
            let samples = task.samples.filter { $0.date >= at }
            guard !samples.isEmpty else { return nil }
            var value = task; value.samples = samples; value.usage = samples.reduce(TokenUsage()) { $0 + $1.usage }
            value.modelUsage = Dictionary(grouping: samples, by: \.model).map { model, calls in ModelUsage(model: model, usage: calls.reduce(TokenUsage()) { $0 + $1.usage }, responses: calls.count, taskIDs: [task.id], cost: calls.reduce(CostEstimate()) { $0 + $1.cost }) }
            value.responses = samples.count; return value
        }
    }
    var goal: GoalUsage? { goals.first { $0.id == selectedGoalID } }
    var filteredGoals: [GoalUsage] { goalBook.summaries(current: applyUsageFilters(snapshot.tasks), lifetime: lifetime.tasks).filter { search.isEmpty || $0.goal.name.localizedCaseInsensitiveContains(search) || ($0.tasks + $0.lifetimeTasks).contains { [$0.title, $0.projectPath].contains { $0.localizedCaseInsensitiveContains(search) } } } }
    var unassignedTasks: [LedgerTask] { snapshot.tasks.filter { goalBook.owner($0) == nil } }
    func openGoal(_ id: String) {
        navigation.append(viewContext)
        page = .goals; selectedGoalID = id; selectedProjectID = nil; selectedConversationID = nil; selectedTaskID = nil; unassignedOnly = false; clearFilters()
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
            saveGoalBook(); goalEditor = nil; openGoal(goal.id); beginAssignment(goalID: goal.id, target: draft.target); return
        }
        saveGoalBook(); goalEditor = nil
    }
    func assignGoal(_ target: GoalTarget, to id: String?) {
        guard goalBookReadable, id == nil || goalBook.goals.contains(where: { $0.id == id }) else { return }
        let matched = lifetime.tasks.filter { target.kind == .turn ? $0.id == target.id : target.kind == .conversation ? $0.sessionID == target.id : $0.projectID == target.id }
        undoBooks.append(AttributionState(rules: goalBook.rules, bindings: goalBook.bindings))
        goalBook.apply(AttributionRule(target: target, goalID: id ?? GoalBook.unassigned, mode: .selected, turnIDs: Set(matched.map(\.id))))
        saveGoalBook()
        if !lifetimeReady { refresh() }
    }
    func resetGoalAssignment(_ target: GoalTarget) {
        guard goalBookReadable else { return }
        undoBooks.append(AttributionState(rules: goalBook.rules, bindings: goalBook.bindings)); goalBook.rules.removeAll { $0.target == target }; goalBook.bindings.removeValue(forKey: target.key); saveGoalBook()
    }
    func completeGoal(_ id: String) {
        guard goalBookReadable, let index = goalBook.goals.firstIndex(where: { $0.id == id }) else { return }
        if goalBook.goals[index].completedAt == nil {
            let coverage = goalCoverage(id)
            guard canCompleteGoal(id) else { errorMessage = coverage.reasons.map(L).joined(separator: "\n"); return }
            goalBook.complete(id, tasks: lifetime.tasks, now: Date(), capturedAt: lifetime.refreshedAt, coverage: coverage)
        } else { goalBook.reopen(id) }
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
        lifetimeReady = scenario != "loading"; updateOverview(); didUpdate?()
    }
}
