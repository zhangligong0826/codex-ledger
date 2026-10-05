import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

extension WorkCategory {
    var color: Color {
        switch self {
        case .question: return Color(red: 0.25, green: 0.49, blue: 0.88)
        case .research: return Color(red: 0.54, green: 0.40, blue: 0.80)
        case .slides: return Color(red: 0.90, green: 0.48, blue: 0.26)
        case .document: return Color(red: 0.18, green: 0.62, blue: 0.56)
        case .spreadsheet: return Color(red: 0.29, green: 0.61, blue: 0.36)
        case .coding: return Color(red: 0.25, green: 0.39, blue: 0.66)
        case .image: return Color(red: 0.78, green: 0.39, blue: 0.61)
        case .mixed: return .orange
        case .background: return .gray
        case .unknown: return .secondary
        }
    }
}

struct LedgerHeader: View {
    var compact = false
    var body: some View {
        HStack(spacing: 10) {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: compact ? 38 : 46, height: compact ? 38 : 46)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Ledger").font(.system(size: compact ? 17 : 22, weight: .semibold))
                Text(L("把 token 对应到每一份工作")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct SummaryCard: View {
    var title: String
    var value: String
    var subtitle: String
    var symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(height: 100, alignment: .topLeading).frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct CategoryRow: View {
    var category: WorkCategory
    var total: Int64
    var count: Int
    var grandTotal: Int64
    var selected = false
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: category.symbol).foregroundStyle(category.color).frame(width: 20)
                Text(L(category.title)).font(.system(size: 11, weight: .medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(grandTotal > 0 ? String(format: "%.0f%%", Double(total) / Double(grandTotal) * 100) : "0%")
                    .font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
            }
            HStack(spacing: 8) {
                Text(compactTokens(total)).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit().fixedSize()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(category.color.opacity(0.1))
                    Capsule().fill(category.color).frame(width: max(2, geo.size.width * CGFloat(total) / CGFloat(max(1, grandTotal))))
                }
            }.frame(height: 5)
            }
        }.padding(10).background(selected ? category.color.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("\(L(category.title))，\(count) 个任务，\(exactTokens(total)) token"))
    }
}

struct UsageRing: View {
    var totals: [(WorkCategory, Int64, Int)]
    var total: Int64
    var pending = false
    var size: CGFloat = 88
    var showTotal = true
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.06), lineWidth: 12)
            ForEach(Array(totals.enumerated()), id: \.element.0) { index, entry in
                let start = Double(totals.prefix(index).reduce(Int64(0)) { $0 + $1.1 }) / Double(max(1, total))
                let end = start + Double(entry.1) / Double(max(1, total))
                Circle().trim(from: start + min(0.003, (end - start) / 4), to: end - min(0.003, (end - start) / 4))
                    .stroke(entry.0.color, style: StrokeStyle(lineWidth: 12, lineCap: .butt)).rotationEffect(.degrees(-90))
            }
            if showTotal { VStack(spacing: 2) {
                Text(pending ? "…" : compactTokens(total)).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text("tokens").font(.system(size: 9)).foregroundStyle(.secondary)
            }.padding(14) }
        }.frame(width: size, height: size).padding(6)
            .accessibilityLabel(pending ? L("正在汇总用量…") : L("总用量 \(exactTokens(total)) token"))
    }
}

struct TaskCard: View {
    let task: LedgerTask
    @ObservedObject var store: LedgerStore
    let expanded: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { store.selectedTaskID = expanded ? nil : task.id } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: task.category.symbol).foregroundStyle(task.category.color).font(.system(size: 17))
                        .frame(width: 34, height: 34).background(task.category.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title == "未记录用户请求" || task.title == "Codex 后台检查" ? L(task.title) : task.title).font(.system(size: 12, weight: .medium)).lineLimit(expanded ? nil : 2).multilineTextAlignment(.leading)
                        if let id = store.goalBook.owner(task), let goal = store.goalBook.goals.first(where: { $0.id == id }) {
                            Label(goal.name, systemImage: "target").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        HStack(spacing: 8) {
                            Text(L(task.category.title)).foregroundStyle(task.category.color)
                            Text(task.date.formatted(Date.FormatStyle().month().day().hour().minute().locale(Locale(identifier: store.language == "en" ? "en_US" : "zh_CN")))).foregroundStyle(.secondary)
                            Text(task.finished ? L("已结束") : L("未记录结束")).foregroundStyle(.secondary)
                            if !task.artifacts.isEmpty { Label("\(task.artifacts.count)", systemImage: "paperclip").foregroundStyle(.secondary) }
                        }.font(.system(size: 10))
                    }
                    Spacer(minLength: 10)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(compactTokens(task.usage.total)).font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(LedgerPricing.display(task.cost)).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit().help(L("预估 API 花费") + " · USD")
                        Text(L("\(task.responses) 次响应")).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 10)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded {
                Divider()
                HStack {
                    Picker(L("分类"), selection: Binding(get: { store.manualCategory(task) }, set: { store.override(task: task, category: WorkCategory(rawValue: $0)) })) {
                        Text(L("自动分类")).tag("auto")
                        ForEach(WorkCategory.allCases) { Text(L($0.title)).tag($0.rawValue) }
                    }.frame(width: 245)
                    Spacer()
                    Button(L("打开聊天")) { store.openChat(task) }
                }
                GoalAssignmentMenu(store: store, target: GoalTarget(kind: .turn, id: task.id), suggestedName: task.title)
                Text(L(task.reason)).font(.system(size: 11)).foregroundStyle(.secondary)
                UsageMetrics(usage: task.usage, cost: task.cost)
                Text(task.projectPath.isEmpty ? L("未识别项目") : task.projectPath).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                Text(L("模型：\(task.models.map(L).joined(separator: ", "))\(task.subagentResponses > 0 ? " · 含 \(task.subagentResponses) 次子代理响应" : "")"))
                    .font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                ForEach(task.artifacts, id: \.self) { path in
                    HStack {
                        Image(systemName: "doc").foregroundStyle(.secondary)
                        Text(URL(fileURLWithPath: path).lastPathComponent).font(.system(size: 11)).lineLimit(1).help(path)
                        Spacer()
                        Button(L("打开")) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } label: { Image(systemName: "folder") }.help(L("在 Finder 中显示"))
                    }
                }
            }
        }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }
    func detailMetric(_ label: String, _ value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(L(label)).foregroundStyle(.secondary); Text(exactTokens(value)).monospacedDigit() }.font(.system(size: 11))
    }
}

final class UsagePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = LedgerStore()
    var statusItem: NSStatusItem!
    var usagePanel: UsagePanel?
    var localMonitor: Any?
    var globalMonitor: Any?
    var dashboard: NSWindow?
    var shareWindow: NSWindow?
    var showPopoverOnLoad = CommandLine.arguments.contains("--show-popover")
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        let panelItem = NSMenuItem(title: L("显示用量面板"), action: #selector(showPanelAction), keyEquivalent: "l")
        panelItem.target = self; appMenu.addItem(panelItem); appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: L("退出 Codex Ledger"), action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self; appMenu.addItem(quitItem)
        appItem.submenu = appMenu; mainMenu.addItem(appItem); NSApp.mainMenu = mainMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = menuBarIcon()
            button.imagePosition = .imageLeading; button.target = self; button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, self.usagePanel?.isVisible == true else { return event }
            if event.type == .keyDown, event.keyCode == 53 { self.usagePanel?.orderOut(nil); return nil }
            if event.type != .keyDown && event.window !== self.usagePanel && event.window !== self.statusItem.button?.window { self.usagePanel?.orderOut(nil) }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.usagePanel?.orderOut(nil) }
        store.didUpdate = { [weak self] in self?.updateStatus() }
        store.presentShare = { [weak self] value in self?.openShare(value) }
        store.captureInterface = { [weak self] overview in
            guard let self, let content = (overview ? self.usagePanel : self.dashboard)?.contentView,
                  let image = ShareImages.capture(content) else { return }
            self.openShare(SharePreview(snapshot: nil, screenshot: image))
        }
        store.prepareFilePanel = { [weak self] in self?.openDashboard(); return self?.dashboard }
        updateStatus(); store.start()
        if CommandLine.arguments.contains("--show-dashboard") || LedgerPreferences.isDemo { openDashboard() }
    }
    func updateStatus() {
        dashboard?.title = L("Codex Ledger · 工作账本"); usagePanel?.title = L("Codex Ledger · 用量总览")
        NSApp.mainMenu?.items.first?.submenu?.items.first?.title = L("显示用量面板")
        NSApp.mainMenu?.items.first?.submenu?.items.last?.title = L("退出 Codex Ledger")
        statusItem.button?.title = store.showFullStatus ? " " + (!store.todayIsReady ? "…" : compactTokens(store.today.usage.total)) : ""
        statusItem.button?.toolTip = store.todayIsReady ? L("Codex Ledger · 今日 \(exactTokens(store.today.usage.total)) token · \(store.today.tasks.count) 个任务") : L("正在整理日志…")
        statusItem.button?.setAccessibilityLabel(statusItem.button?.toolTip ?? "Codex Ledger")
        if usagePanel?.isVisible == true { layoutUsagePanel() }
        if showPopoverOnLoad && store.rangeReady {
            showPopoverOnLoad = false
            showUsagePanel()
        }
    }
    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            for (title, action) in [(L("打开工作账本"), #selector(openDashboardAction)), (L("刷新用量"), #selector(refreshAction)), (L("设置…"), #selector(settingsAction))] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
            }
            menu.addItem(.separator())
            let quit = NSMenuItem(title: L("退出 Codex Ledger"), action: #selector(quitAction), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
            statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
        } else { showPanelAction() }
    }
    @objc func refreshAction() { store.refresh() }
    @objc func showPanelAction() {
        if usagePanel?.isVisible == true { usagePanel?.orderOut(nil) }
        else { showUsagePanel() }
    }
    func showUsagePanel() {
        if usagePanel == nil {
            let panel = UsagePanel(contentRect: NSRect(x: 0, y: 0, width: LedgerStore.panelWidth, height: 560), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = L("Codex Ledger · 用量总览")
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.level = .floating; panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.transient, .moveToActiveSpace]
            panel.contentViewController = NSHostingController(rootView: StatusPopover(store: store, openDashboard: { [weak self] in self?.openDashboard() }).clipShape(RoundedRectangle(cornerRadius: 18)))
            usagePanel = panel
        }
        layoutUsagePanel()
        NSApp.activate(ignoringOtherApps: true); usagePanel?.makeKeyAndOrderFront(nil)
    }
    private func layoutUsagePanel() {
        guard let button = statusItem.button, let panel = usagePanel else { return }
        let screen = button.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? NSRect(x: visible.maxX - 20, y: visible.maxY, width: 20, height: 24)
        let height = min(store.panelHeight, visible.height - 16)
        let width = min(LedgerStore.panelWidth, visible.width - 16)
        panel.setContentSize(NSSize(width: width, height: height))
        panel.setFrameOrigin(NSPoint(x: max(visible.minX + 8, min(anchor.maxX - width, visible.maxX - width - 8)), y: max(visible.minY + 8, min(anchor.minY - height - 8, visible.maxY - height - 8))))
    }
    @objc func openDashboardAction() { openDashboard() }
    @objc func settingsAction() { store.navigate(.settings); openDashboard() }
    @objc func quitAction() { NSApp.terminate(nil) }
    func openShare(_ preview: SharePreview) {
        usagePanel?.orderOut(nil)
        shareWindow?.close()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 610), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("分享"); window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SharePreviewView(preview: preview, language: store.language, close: { [weak window] in window?.close() }))
        shareWindow = window; window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func openDashboard() {
        usagePanel?.orderOut(nil)
        if dashboard == nil {
            let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let initial = NSSize(width: min(1080, visible.width - 32), height: min(720, visible.height - 64))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: initial), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = L("Codex Ledger · 工作账本"); window.contentMinSize = NSSize(width: min(880, initial.width), height: min(580, initial.height))
            window.contentViewController = NSHostingController(rootView: DashboardView(store: store))
            window.isReleasedWhenClosed = false; window.delegate = self; window.center()
            window.setFrameAutosaveName("CodexLedgerDashboard"); dashboard = window
            let frame = window.frame
            if frame.width > visible.width || frame.height > visible.height || !visible.intersects(frame) { window.setContentSize(initial); window.center() }
        }
        NSApp.activate(ignoringOtherApps: true); dashboard?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let panel = usagePanel, panel.isVisible { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); return false }
        openDashboard(); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }
    private func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            for (index, height) in [5.0, 9.0, 13.0].enumerated() {
                NSBezierPath(roundedRect: NSRect(x: 2 + Double(index) * 5, y: 2, width: 3.5, height: height), xRadius: 1.2, yRadius: 1.2).fill()
            }
            return true
        }
        image.isTemplate = true; image.accessibilityDescription = L("Codex 今日用量"); return image
    }
}

@main struct CodexLedgerMain {
    static func main() {
        if CommandLine.arguments.contains("--diagnose") { diagnose(); return }
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
    static func diagnose() {
        let root = ProcessInfo.processInfo.environment["CODEX_LEDGER_SOURCE"] ?? ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        let scopes: [String: DateScope] = ["today": .today, "yesterday": .yesterday, "7d": .week, "30d": .month, "all": .history]
        let argument = CommandLine.arguments.first { $0.hasPrefix("--scope=") }.map { String($0.dropFirst(8)) } ?? "today"
        guard let scope = scopes[argument] else { fputs("Scope must be today, yesterday, 7d, 30d, or all\n", stderr); exit(2) }
        let scanner = LedgerScanner(cacheDirectory: CommandLine.arguments.contains("--use-cache") ? LedgerScanner.applicationCacheDirectory : nil); let start = Date()
        let now = Date()
        let result = scanner.scan(root: URL(fileURLWithPath: root), now: now, days: scope.days == Int.max ? nil : max(30, scope.days))
        let scanSeconds = Date().timeIntervalSince(start), aggregationStart = Date()
        let range = scope.interval(now: now, calendar: .current)
        let snap = scanner.snapshot(logs: result.logs, start: range.start, end: range.end, root: root, warnings: result.warnings)
        let enriched = LedgerAnalytics.enrich(snap, resolver: ProjectResolver(), titles: ConversationMetadata.titles(root: URL(fileURLWithPath: root)))
        var output: [String: Any] = ["files": snap.files, "tasks": snap.tasks.count, "projects": enriched.projects.count, "conversations": enriched.conversations.count, "projectTotal": enriched.projects.reduce(Int64(0)) { $0 + $1.usage.total }, "conversationTotal": enriched.conversations.reduce(Int64(0)) { $0 + $1.usage.total }, "input": snap.usage.input, "cached": snap.usage.cached, "output": snap.usage.output, "reasoning": snap.usage.reasoning, "total": snap.usage.total, "categories": Dictionary(WorkCategory.allCases.map { c in (c.rawValue, snap.tasks.filter { $0.category == c }.reduce(Int64(0)) { $0 + $1.usage.total }) }, uniquingKeysWith: { a, _ in a }), "warnings": snap.warnings, "malformed": snap.malformed, "seconds": Date().timeIntervalSince(start)]
        output["isComplete"] = snap.isComplete
        output["affectedLogCount"] = snap.logIssues.count
        output["hasReadFailures"] = snap.hasReadFailures
        output["estimatedAPIUSD"] = LedgerPricing.decimalString(snap.cost.totalUSD)
        output["pricedTokens"] = snap.cost.pricedTokens
        output["unpricedTokens"] = snap.cost.unpricedTokens
        output["unverifiedContextTokens"] = snap.cost.unverifiedContextTokens
        output["projectEstimatedAPIUSD"] = LedgerPricing.decimalString(enriched.projects.reduce(CostEstimate()) { $0 + $1.cost }.totalUSD)
        output["conversationEstimatedAPIUSD"] = LedgerPricing.decimalString(enriched.conversations.reduce(CostEstimate()) { $0 + $1.cost }.totalUSD)
        output["modelEstimatedAPIUSD"] = LedgerPricing.decimalString(snap.modelUsage.reduce(CostEstimate()) { $0 + $1.cost }.totalUSD)
        output["pricingDate"] = LedgerPricing.verifiedDate
        output["scanSeconds"] = scanSeconds
        output["aggregationSeconds"] = Date().timeIntervalSince(aggregationStart)
        output["parsedFiles"] = scanner.parsedFileCount
        output["diskCacheHits"] = scanner.diskCacheHits
        output["memoryCacheHits"] = scanner.memoryCacheHits
        let heatmapStart = Date()
        let activity = scanner.dailyUsage(logs: result.logs, now: now, calendar: .current)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        output["activityTotal"] = activity.reduce(Int64(0)) { $0 + $1.usage.total }
        output["activeDays"] = activity.filter { $0.usage.total > 0 }.count
        output["activityEstimatedAPIUSD"] = LedgerPricing.decimalString(activity.reduce(CostEstimate()) { $0 + $1.cost }.totalUSD)
        output["dailyUsage"] = activity.map { ["date": formatter.string(from: $0.date), "total": $0.usage.total, "responses": $0.responses, "estimatedAPIUSD": LedgerPricing.decimalString($0.cost.totalUSD), "pricedTokens": $0.cost.pricedTokens, "unpricedTokens": $0.cost.unpricedTokens] as [String: Any] }
        output["heatmapSeconds"] = Date().timeIntervalSince(heatmapStart)
        output["totalSeconds"] = Date().timeIntervalSince(start)
        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
    }
}
