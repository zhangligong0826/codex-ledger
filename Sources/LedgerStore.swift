import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

enum LedgerPage: String { case tasks, projects, conversations, models, settings }

enum LedgerPreferences {
    static let isDemo = CommandLine.arguments.contains("--demo") || (Bundle.main.object(forInfoDictionaryKey: "LedgerDemo") as? Bool == true)
    static let defaults: UserDefaults = isDemo ? UserDefaults(suiteName: "local.codexledger.demo")! : .standard
}

@MainActor final class LedgerStore: ObservableObject {
    @Published var today = LedgerSnapshot()
    @Published var todayIsReady = false
    @Published var snapshot = LedgerSnapshot()
    @Published var scope: DateScope = .today { didSet {
        guard scope != oldValue else { return }
        selectedTaskID = nil; recompute()
        if scope.days > loadedDays { refresh() }
    } }
    @Published var isLoading = false
    @Published var isComputing = false
    @Published var page: LedgerPage = .projects
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
        LedgerText.language = language
        showFullStatus = defaults.object(forKey: "fullStatus") as? Bool ?? true
        launchAtLogin = !LedgerPreferences.isDemo && SMAppService.mainApp.status == .enabled
    }
    var busy: Bool { isLoading || isComputing }
    var rangeReady: Bool { renderedScope == scope }
    var logsAreEmpty: Bool { logs.isEmpty && !LedgerPreferences.isDemo }
    var knownModelCount: Int { snapshot.modelUsage.filter { $0.model != "未知模型" }.count }
    var categoryTotals: [(WorkCategory, Int64, Int)] { LedgerAnalytics.categories(snapshot.tasks) }
    var panelHeight: CGFloat { !rangeReady ? 380 : max(360, min(460, 325 + CGFloat(min(categoryTotals.count, 5)) * 27)) }
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
        let path = sourcePath, scanner = self.scanner, begin = Date(), days = max(loadedDays, scope.days)
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
                if self.scope.days > self.loadedDays { self.refresh() }
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
        let calendar = Calendar.current, now = Date(), scanner = self.scanner, resolver = self.resolver
        queue.async {
            let root = URL(fileURLWithPath: path)
            var titles = ConversationMetadata.titles(root: root)
            for log in logs where !log.firstPrompt.isEmpty && titles[log.sessionID] == nil { titles[log.sessionID] = log.firstPrompt }
            let todayRange = DateScope.today.interval(now: now, calendar: calendar)
            let today = LedgerAnalytics.enrich(scanner.snapshot(logs: logs, start: todayRange.start, end: todayRange.end, root: path, overrides: overrides, warnings: warnings), resolver: resolver, titles: titles)
            let range = requestedScope.interval(now: now, calendar: calendar)
            let current = requestedScope == .today ? today : LedgerAnalytics.enrich(scanner.snapshot(logs: logs, start: range.start, end: range.end, root: path, overrides: overrides, warnings: warnings), resolver: resolver, titles: titles)
            DispatchQueue.main.async {
                guard self.computeVersion == version, self.sourcePath == path, self.scope == requestedScope else { return }
                self.today = today; self.todayIsReady = true; self.snapshot = current; self.renderedScope = requestedScope; self.isComputing = false; self.didUpdate?()
            }
        }
    }
    func navigate(_ destination: LedgerPage) {
        page = destination; selectedProjectID = nil; selectedConversationID = nil; selectedTaskID = nil
        categoryFilter = nil; modelFilter = nil; search = ""
    }
    func openProject(_ project: ProjectUsage) {
        page = .projects; selectedProjectID = project.id; selectedConversationID = nil; selectedTaskID = nil; clearFilters()
    }
    func openConversation(_ chat: ConversationUsage) { selectedConversationID = chat.id; selectedTaskID = nil; clearFilters() }
    func back() {
        if selectedConversationID != nil { selectedConversationID = nil }
        else { selectedProjectID = nil }
        selectedTaskID = nil; clearFilters()
    }
    func clearFilters() { search = ""; categoryFilter = nil; modelFilter = nil }
    var project: ProjectUsage? { snapshot.projects.first { $0.id == selectedProjectID } }
    var contextConversations: [ConversationUsage] { selectedProjectID != nil ? project?.conversations ?? [] : snapshot.conversations }
    var conversation: ConversationUsage? { contextConversations.first { $0.id == selectedConversationID } }
    var contextTasks: [LedgerTask] {
        if selectedConversationID != nil { return conversation?.tasks ?? [] }
        if selectedProjectID != nil { return project?.tasks ?? [] }
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
            self.computeVersion += 1; self.isComputing = false; self.renderedScope = nil; self.snapshot = LedgerSnapshot(); self.today = LedgerSnapshot(); self.todayIsReady = false; self.didUpdate?(); self.refresh()
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
    func exportCSV(models modelMode: Bool? = nil, turns: Bool = false) {
        guard rangeReady, !busy else { return }
        let contents: String, kind: String
        if let modelMode {
            contents = modelMode ? LedgerCSV.renderModels(snapshot.modelUsage, translate: L) : LedgerCSV.render(snapshot.tasks, translate: L); kind = modelMode ? "Models" : "Tasks"
        } else if let chat = conversation {
            contents = turns ? LedgerCSV.render(filteredTasks, translate: L) : LedgerCSV.renderConversations([chat], projectPath: project?.path, translate: L); kind = turns ? "Tasks" : "Conversations"
        } else if page == .projects && selectedProjectID == nil {
            contents = LedgerCSV.renderProjects(filteredProjects, translate: L); kind = "Projects"
        } else if page == .conversations || selectedProjectID != nil {
            contents = LedgerCSV.renderConversations(filteredConversations, projectPath: project?.path, translate: L); kind = "Conversations"
        } else if page == .models {
            contents = LedgerCSV.renderModels(filteredModels, translate: L); kind = "Models"
        } else { contents = LedgerCSV.render(filteredTasks, translate: L); kind = "Tasks" }
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
    func loadDemo() {
        let scenario = ProcessInfo.processInfo.environment["CODEX_LEDGER_DEMO_STATE"] ?? (Bundle.main.object(forInfoDictionaryKey: "LedgerDemoState") as? String) ?? "ready"
        loadedDays = Int.max; renderedScope = scenario == "loading" ? nil : scope; isComputing = false; isLoading = scenario == "loading"
        scanCompleted = 12; scanTotal = 80
        snapshot = LedgerDemo.snapshot(empty: scenario != "ready", error: scenario == "error")
        today = snapshot; todayIsReady = scenario != "loading"; didUpdate?()
    }
}
