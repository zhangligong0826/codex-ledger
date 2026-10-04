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
            let current = requestedScope == .today ? today : LedgerAnalytics.enrich(scanner.snapshot(logs: logs, start: range.start, end: range.end, root: path, overrides: overrides, warnings: warnings), resolver: resolver, titles: titles)
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
    var contextUsage: TokenUsage { contextTasks.reduce(TokenUsage()) { $0 + $1.usage } }
    var contextCost: CostEstimate { LedgerPricing.total(contextTasks) }
    var contextCategories: [(WorkCategory, Int64, Int)] { LedgerAnalytics.categories(contextTasks) }
    func override(task: LedgerTask, category: WorkCategory?) {
        if let category { overrides[task.id] = category.rawValue } else { overrides.removeValue(forKey: task.id) }
        defaults.set(overrides, forKey: "categoryOverrides"); recompute()
    }
    func manualCategory(_ task: LedgerTask) -> String { overrides[task.id] ?? "auto" }
    func setLanguage(_ value: String) { language = value; LedgerText.language = value; defaults.set(value, forKey: "language"); didUpdate?() }
    func setStatusStyle(_ enabled: Bool) { showFullStatus = enabled; defaults.set(enabled, forKey: "fullStatus"); didUpdate?() }
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
        guard rangeReady, activityReady, !busy, !isSharing, !dataUnavailable else { return }
        let now = Date(), calendar = scanner.calendar
        let sourceLogs = logs, goalBook = self.goalBook, path = sourcePath
        let goalID = overview ? nil : selectedGoalID, projectID = overview ? nil : selectedProjectID
        let chatID = overview ? nil : selectedConversationID
        let goalList = !overview && page == .goals && goalID == nil
        let category = overview ? nil : categoryFilter, model = overview ? nil : modelFilter
        let query = overview ? "" : search
        let unassigned = !overview && unassignedOnly
        let listedGoalIDs = Set(filteredGoals.map(\.id))
        let selected = overview ? snapshot.tasks : goalList ? snapshot.tasks.filter { task in goalBook.owner(task).map { listedGoalIDs.contains($0) } ?? false } : filteredTasks
        let chosenGoal = goalID.flatMap { id in goals.first { $0.id == id } }
        let kind = chatID != nil ? "对话用量" : goalID != nil ? "目标花费" : projectID != nil ? "项目用量" : goalList ? "目标账本" : "用量总览"
        let title = chatID != nil ? conversation?.title ?? L(kind) : chosenGoal?.goal.name ?? project?.name ?? L(kind)
        let range = L(scope.rawValue), priceDate = LedgerPricing.verifiedDate, warning = !snapshot.warnings.isEmpty
        let demoMonth = LedgerPreferences.isDemo ? LedgerDemo.snapshot(scope: .month).tasks : nil
        let scanner = self.scanner, resolver = self.resolver
        isSharing = true
        queue.async {
            let monthRange = DateScope.month.interval(now: now, calendar: calendar)
            let monthTasks = demoMonth ?? LedgerAnalytics.enrich(scanner.snapshot(logs: sourceLogs, start: monthRange.start, end: monthRange.end, root: path), resolver: resolver, titles: [:]).tasks
            let matching = monthTasks.filter { task in
                if let goalID, goalBook.owner(task) != goalID { return false }
                if goalList { return goalBook.owner(task).map { listedGoalIDs.contains($0) } ?? false }
                if unassigned && goalBook.owner(task) != nil { return false }
                if let projectID, task.projectID != projectID { return false }
                if let chatID, task.sessionID != chatID { return false }
                if let category, task.category != category { return false }
                if let model, !task.models.contains(model) { return false }
                return query.isEmpty || [task.title, task.projectName, task.projectPath, task.workingDirectory, task.sessionID, task.models.joined(separator: " ")].contains { $0.localizedCaseInsensitiveContains(query) }
            }
            let days: [DailyUsage]
            if demoMonth != nil {
                days = (0..<30).map { offset in
                    let date = calendar.date(byAdding: .day, value: offset, to: monthRange.start)!
                    let tasks = matching.filter { calendar.isDate($0.date, inSameDayAs: date) }
                    return DailyUsage(date: date, usage: tasks.reduce(TokenUsage()) { $0 + $1.usage }, responses: tasks.reduce(0) { $0 + $1.responses }, cost: LedgerPricing.total(tasks))
                }
            } else { days = scanner.dailyUsage(logs: sourceLogs, now: now, calendar: calendar, taskIDs: Set(matching.map(\.id))) }
            let value = ShareSnapshot(kind: kind, privateTitle: title, range: range, timezone: calendar.timeZone.identifier,
                usage: selected.reduce(TokenUsage()) { $0 + $1.usage }, cost: LedgerPricing.total(selected), turns: selected.count,
                conversations: Set(selected.map(\.sessionID)).count, models: Set(selected.flatMap(\.models)).subtracting(["未知模型"]).count,
                days: days, completionCost: chatID == nil ? chosenGoal?.goal.completionCost : nil,
                completionDate: chosenGoal?.goal.completedAt, completionPriceDate: chosenGoal?.goal.completionPriceDate,
                filtered: category != nil || model != nil || !query.isEmpty || unassigned, warning: warning, priceDate: priceDate)
            DispatchQueue.main.async { self.isSharing = false; self.presentShare?(SharePreview(snapshot: value, screenshot: nil)) }
        }
    }
    func exportCSV(models modelMode: Bool? = nil, turns: Bool = false) {
        guard rangeReady, !busy, !dataUnavailable else { return }
        let contents: String, kind: String
        let names = Dictionary(uniqueKeysWithValues: goalBook.goals.map { ($0.id, $0.name) })
        let goalNames = Dictionary(uniqueKeysWithValues: snapshot.tasks.compactMap { task -> (String, String)? in
            guard let id = goalBook.owner(task), let name = names[id] else { return nil }; return (task.id, name)
        })
        if let modelMode {
            contents = modelMode ? LedgerCSV.renderModels(snapshot.modelUsage, translate: L) : LedgerCSV.render(snapshot.tasks, goalNames: goalNames, translate: L); kind = modelMode ? "Models" : "Tasks"
        } else if page == .goals && conversation == nil {
            contents = turns ? LedgerCSV.render(filteredTasks, goalNames: goalNames, translate: L) : LedgerCSV.renderGoals(selectedGoalID == nil ? filteredGoals : goal.map { [$0] } ?? [], scope: L(scope.rawValue), lifetimeReady: goalAmountsReady, translate: L); kind = turns ? "Goal-Turns" : "Goals"
        } else if let chat = conversation {
            contents = turns ? LedgerCSV.render(filteredTasks, goalNames: goalNames, translate: L) : LedgerCSV.renderConversations([chat], projectPath: project?.path, usageScope: selectedGoalID == nil ? nil : L("仅当前目标"), translate: L); kind = turns ? "Tasks" : "Conversations"
        } else if page == .projects && selectedProjectID == nil {
            contents = LedgerCSV.renderProjects(filteredProjects, translate: L); kind = "Projects"
        } else if page == .conversations || selectedProjectID != nil {
            contents = LedgerCSV.renderConversations(filteredConversations, projectPath: project?.path, usageScope: selectedGoalID == nil ? nil : L("仅当前目标"), translate: L); kind = "Conversations"
        } else if page == .models {
            contents = LedgerCSV.renderModels(filteredModels, translate: L); kind = "Models"
        } else { contents = LedgerCSV.render(filteredTasks, goalNames: goalNames, translate: L); kind = "Tasks" }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Codex-\(kind)-\(L(scope.rawValue))-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).csv"
        presentFilePanel(panel) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try contents.write(to: url, atomically: true, encoding: .utf8) }
            catch { self?.errorMessage = L("导出失败：\(error.localizedDescription)") }
        }
    }
    private func presentFilePanel(_ panel: NSSavePanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = prepareFilePanel?() { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { NSApp.activate(ignoringOtherApps: true); panel.begin(completionHandler: completion) }
    }
    // A separate attribution book per data root prevents unrelated imports sharing IDs.
    private var goalBookKey: String { "goalBook.v1:" + URL(fileURLWithPath: sourcePath).standardizedFileURL.path }
    private func loadGoalBook() {
        goalBookReadable = true; goalBook = GoalBook()
        guard let data = defaults.data(forKey: goalBookKey) else { return }
        do { goalBook = try GoalBook.decode(data) }
        catch { goalBookReadable = false; errorMessage = L("目标账本无法读取，原有数据已保留。") }
    }
    private func saveGoalBook() {
        guard goalBookReadable else { return }
        do { defaults.set(try JSONEncoder().encode(goalBook), forKey: goalBookKey) }
        catch { errorMessage = L("目标账本无法保存。") }
    }
    var goals: [GoalUsage] { goalBook.summaries(current: snapshot.tasks, lifetime: lifetime.tasks) }
    var goalAmountsReady: Bool { lifetimeReady && !dataUnavailable }
    var goal: GoalUsage? { goals.first { $0.id == selectedGoalID } }
    var filteredGoals: [GoalUsage] { goals.filter { search.isEmpty || $0.goal.name.localizedCaseInsensitiveContains(search) || ($0.tasks + $0.lifetimeTasks).contains { [$0.title, $0.projectPath].contains { $0.localizedCaseInsensitiveContains(search) } } } }
    var unassignedTasks: [LedgerTask] { snapshot.tasks.filter { goalBook.owner($0) == nil } }
    func openGoal(_ id: String) {
        page = .goals; selectedGoalID = id; selectedProjectID = nil; selectedConversationID = nil; selectedTaskID = nil; unassignedOnly = false; clearFilters()
        scope = .history
        if !lifetimeReady { refresh() }
    }
    func editGoal(_ goal: LedgerGoal) { goalEditor = GoalEditorDraft(name: goal.name, goalID: goal.id) }
    func newGoal(name: String = "", target: GoalTarget? = nil) {
        guard goalBookReadable else { errorMessage = L("目标账本无法读取，原有数据已保留。"); return }
        goalEditor = GoalEditorDraft(name: name, target: target)
    }
    func saveGoal(name: String, draft: GoalEditorDraft) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, goalBookReadable else { return }
        if let id = draft.goalID, let index = goalBook.goals.firstIndex(where: { $0.id == id }) { goalBook.goals[index].name = String(name.prefix(160)) }
        else {
            let goal = LedgerGoal(name: String(name.prefix(160))); goalBook.goals.append(goal)
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
