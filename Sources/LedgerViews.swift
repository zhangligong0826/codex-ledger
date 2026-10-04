import AppKit
import SwiftUI

struct UsageMetrics: View {
    var usage: TokenUsage
    var pending = false
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), alignment: .leading)], alignment: .leading, spacing: 10) {
            metric("输入", usage.input); metric("其中缓存", usage.cached)
            metric("输出", usage.output); metric("其中推理", usage.reasoning)
        }
    }
    func metric(_ label: String, _ value: Int64) -> some View {
        HStack(spacing: 5) { Text(L(label)).foregroundStyle(.secondary); Text(pending ? "—" : compactTokens(value)).monospacedDigit() }
            .font(.system(size: 11)).help(pending ? L("正在汇总用量…") : exactTokens(value) + " tokens")
    }
}

struct StatusPopover: View {
    @ObservedObject var store: LedgerStore
    var openDashboard: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 9) {
                HStack {
                    Text(L("用量总览")).font(.system(size: 14, weight: .semibold))
                    Image(systemName: "info.circle").foregroundStyle(.secondary).help(L("本机 Codex 日志 · 输入 + 输出（包含缓存）"))
                    Spacer()
                    Button { store.exportCSV(models: false) } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(.plain).disabled(store.busy || !store.rangeReady).help(L("导出 CSV"))
                }
                Picker(L("时间"), selection: $store.scope) { ForEach(DateScope.allCases) { Text(L($0.rawValue)).tag($0) } }
                    .pickerStyle(.menu).labelsHidden().controlSize(.small).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            UsageRing(totals: store.categoryTotals, total: store.snapshot.usage.total, pending: !store.rangeReady)
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(store.categoryTotals.prefix(3), id: \.0) { c, value, _ in legend(L(c.title), value, c.color) }
                                if store.categoryTotals.count > 3 { legend(L("其他用途"), store.categoryTotals.dropFirst(3).reduce(0) { $0 + $1.1 }, .gray) }
                                if store.categoryTotals.isEmpty { Text(!store.rangeReady ? L("正在整理日志…") : L("暂时没有用量记录")).font(.system(size: 11)).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity)
                        }
                        HStack {
                            Text(store.rangeReady ? L("\(store.snapshot.tasks.count) 个任务") : "—")
                            Spacer()
                            Text(store.rangeReady ? L("输入 \(compactTokens(store.snapshot.usage.input)) · 输出 \(compactTokens(store.snapshot.usage.output))") : "—")
                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }.padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    HStack {
                        Label(L("任务用途"), systemImage: "chart.bar.xaxis").font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Button(store.rangeReady ? L("\(store.knownModelCount) 个模型") : "—") { store.navigate(.models); openDashboard() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 9) {
                        if !store.rangeReady {
                            HStack { ProgressView().controlSize(.small); Text(L("正在整理日志，请稍候")).font(.system(size: 11)) }.padding(.vertical, 10)
                        } else if store.snapshot.tasks.isEmpty {
                            Text(store.snapshot.warnings.isEmpty ? L("这个日期范围内暂无记录") : L("需要检查数据目录")).font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 10)
                        }
                        ForEach(store.categoryTotals.prefix(5), id: \.0) { c, value, count in
                            Button { store.navigate(.tasks); store.categoryFilter = c; openDashboard() } label: {
                                VStack(spacing: 4) {
                                    HStack {
                                        Text(L(c.title)).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                        Spacer(minLength: 4)
                                        Text(compactTokens(value)).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                                        Text(String(format: "%.1f%%", Double(value) / Double(max(1, store.snapshot.usage.total)) * 100)).font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                                        Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                                    }
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.primary.opacity(0.08))
                                            Capsule().fill(c.color).frame(width: geo.size.width * CGFloat(value) / CGFloat(max(1, store.snapshot.usage.total)))
                                        }
                                    }.frame(height: 3)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).help(L("\(count) 个任务 · \(exactTokens(value)) token"))
                        }
                        Button { store.navigate(.projects); openDashboard() } label: {
                            HStack { Text(L("查看项目与对话")); Spacer(); Image(systemName: "arrow.up.right") }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }.padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    if !store.snapshot.warnings.isEmpty { Label(L("部分日志不可读，账本内可查看详情"), systemImage: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(.orange) }
                }.padding(.horizontal, 12).padding(.bottom, 10)
            }.id(store.scope)
            if store.busy { HStack { ProgressView().controlSize(.mini); Text(store.scanStatus).font(.system(size: 10)).lineLimit(1); Spacer() }.padding(.horizontal, 14).padding(.bottom, 6) }
            Divider()
            HStack {
                Text("Codex Ledger \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0")").font(.system(size: 9)).foregroundStyle(.secondary)
                Button { store.refresh() } label: {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(store.busy ? L("正在更新…") : L("\(max(0, 30 - Int(context.date.timeIntervalSince(store.today.refreshedAt)))) 秒后更新")).font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }.buttonStyle(.plain).disabled(store.busy).keyboardShortcut("r", modifiers: .command)
                Spacer(minLength: 3)
                Menu(L("选项")) {
                    Button(L("项目")) { store.navigate(.projects); openDashboard() }
                    Button(L("对话")) { store.navigate(.conversations); openDashboard() }
                    Button(L("全部工作")) { store.navigate(.tasks); openDashboard() }
                    Button(L("查看模型用量")) { store.navigate(.models); openDashboard() }
                    Button(L("导出 CSV…")) { store.exportCSV(models: false) }.disabled(store.busy || !store.rangeReady)
                    Button(L("设置…")) { store.navigate(.settings); openDashboard() }
                    Picker(L("语言"), selection: Binding(get: { store.language }, set: store.setLanguage)) { Text("English").tag("en"); Text("简体中文").tag("zh") }
                    Picker(L("外观"), selection: Binding(get: { store.appearance }, set: store.setAppearance)) { Text(L("跟随系统")).tag("system"); Text(L("浅色")).tag("light"); Text(L("深色")).tag("dark") }
                    Divider(); Button(L("退出 Codex Ledger")) { NSApp.terminate(nil) }
                }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 11))
            }.padding(.horizontal, 12).padding(.vertical, 9)
        }.id(store.language).frame(width: 340).frame(maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
    }
    func legend(_ title: String, _ value: Int64, _ color: Color) -> some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 7, height: 7); Text(title).lineLimit(1); Spacer(minLength: 3); Text(compactTokens(value)).foregroundStyle(.secondary).monospacedDigit() }.font(.system(size: 10))
    }
}

struct DashboardView: View {
    @ObservedObject var store: LedgerStore
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210); Divider()
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.system(size: 23, weight: .semibold)).lineLimit(2).textSelection(.enabled)
                        Text(store.showSettings ? L("本地运行，按你的习惯记录。") : L(store.scope.rawValue) + " · " + TimeZone.current.identifier).font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if !store.showSettings {
                        Picker(L("时间"), selection: $store.scope) { ForEach(DateScope.allCases) { Text(L($0.rawValue)).tag($0) } }.pickerStyle(.menu).labelsHidden().frame(width: 135)
                        Button { store.exportCSV() } label: { Image(systemName: "square.and.arrow.up") }.help(L("导出 CSV")).disabled(store.busy || !store.rangeReady)
                    }
                    Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }.help(L("刷新")).disabled(store.busy).keyboardShortcut("r", modifiers: .command)
                }
                if store.showSettings { settings }
                else {
                    if store.selectedProjectID != nil || store.selectedConversationID != nil {
                        HStack {
                            Button { store.back() } label: { Label(L("返回"), systemImage: "chevron.left") }
                            Text(store.selectedProjectID != nil ? L("仅当前项目") : L("整个对话")).font(.system(size: 11)).foregroundStyle(.secondary)
                            if store.conversation?.spansProjects == true { Label(L("涉及多个项目"), systemImage: "folder.badge.questionmark").font(.system(size: 11)).foregroundStyle(.secondary) }
                            Spacer()
                            if let chat = store.conversation {
                                Button(L("导出轮次 CSV")) { store.exportCSV(turns: true) }.disabled(store.busy || !store.rangeReady)
                                Button(L("打开聊天")) { store.openChat(id: chat.id) }
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 10) {
                        SummaryCard(title: L("总 token"), value: store.rangeReady ? compactTokens(store.contextUsage.total) : "…", subtitle: L("输入 + 输出 · 含缓存"), symbol: "chart.bar")
                        SummaryCard(title: L("任务轮次"), value: store.rangeReady ? "\(store.contextTasks.count)" : "…", subtitle: store.rangeReady ? L("\(store.contextTasks.filter(\.finished).count) 轮已结束") : L("正在整理日志…"), symbol: "square.stack")
                        SummaryCard(title: L("关联文件"), value: store.rangeReady ? "\(Set(store.contextTasks.flatMap(\.artifacts)).count)" : "…", subtitle: L("已存在的本地文件"), symbol: "doc.on.doc")
                        SummaryCard(title: L("使用模型"), value: store.rangeReady ? "\(Set(store.contextTasks.flatMap(\.models)).subtracting(["未知模型"]).count)" : "…", subtitle: L("已识别的不同模型"), symbol: "cpu")
                    }
                    UsageMetrics(usage: store.contextUsage, pending: !store.rangeReady)
                    if store.busy { HStack { ProgressView().controlSize(.small); Text(store.scanStatus).font(.system(size: 11)).foregroundStyle(.secondary) } }
                    if !store.snapshot.warnings.isEmpty { Text(store.snapshot.warnings.prefix(3).map(L).joined(separator: "\n")).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled) }
                    HStack {
                        Text(listTitle).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 6)
                        if !store.search.isEmpty || store.categoryFilter != nil || store.modelFilter != nil { Button(L("清除筛选")) { store.clearFilters() }.font(.system(size: 11)) }
                        TextField(L("搜索项目、对话或模型"), text: $store.search).textFieldStyle(.roundedBorder).frame(maxWidth: 215)
                    }
                    if store.selectedConversationID != nil { conversationSummary }
                    content.id(store.page.rawValue + (store.selectedProjectID ?? "") + (store.selectedConversationID ?? "") + store.scope.rawValue).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    HStack {
                        Text(store.rangeReady ? L("\(store.snapshot.files) 份日志 · 分类可手动修正") : L("正在整理日志…")).font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        if store.rangeReady { Text(L("更新于 \(store.snapshot.refreshedAt.formatted(.dateTime.hour().minute().second()))")).font(.system(size: 10)).foregroundStyle(.secondary) }
                    }
                }
            }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.id(store.language).background(Color(nsColor: .windowBackgroundColor))
            .alert("Codex Ledger", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button(L("知道了")) { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
    }
    var title: String {
        if store.showSettings { return L("设置") }
        if store.selectedConversationID != nil { return store.conversation.map { displayTitle($0.title) } ?? L("对话") }
        if store.selectedProjectID != nil { return store.project.map { displayProject($0.name) } ?? L("项目") }
        switch store.page { case .projects: return L("项目"); case .conversations: return L("对话"); case .models: return L("模型用量"); default: return L("你的工作，用量可见") }
    }
    var listTitle: String {
        if store.selectedConversationID != nil { return L("任务轮次") }
        if store.selectedProjectID != nil { return L("项目中的对话") }
        return store.categoryFilter.map { L($0.title) } ?? store.modelFilter ?? title
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 15) {
            LedgerHeader(compact: true)
            VStack(spacing: 3) {
                navigation("项目", "folder", .projects, store.snapshot.projects.count)
                navigation("对话", "bubble.left.and.bubble.right", .conversations, store.snapshot.conversations.count)
                navigation("全部工作", "square.grid.2x2", .tasks, store.snapshot.tasks.count)
                navigation("模型用量", "cpu", .models, store.knownModelCount)
            }
            Text(L("TOKEN 用在哪里")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 8)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.categoryTotals, id: \.0) { c, value, count in
                        Button { store.navigate(.tasks); store.categoryFilter = c } label: { CategoryRow(category: c, total: value, count: count, grandTotal: store.snapshot.usage.total, selected: store.page == .tasks && store.categoryFilter == c) }.buttonStyle(.plain)
                    }
                }
            }
            Button { store.navigate(.settings) } label: { Label(L("设置"), systemImage: "gearshape") }.buttonStyle(.plain).font(.system(size: 12)).padding(.horizontal, 8)
            Divider()
            Label(L("仅在这台 Mac 上统计"), systemImage: "lock.shield").font(.system(size: 10)).foregroundStyle(.secondary)
            Text(L("不上传聊天内容")).font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(14).background(Color.primary.opacity(0.025))
    }
    func navigation(_ title: String, _ symbol: String, _ page: LedgerPage, _ count: Int) -> some View {
        Button { store.navigate(page) } label: {
            HStack { Label(L(title), systemImage: symbol); Spacer(); Text(store.rangeReady ? "\(count)" : "—").foregroundStyle(.secondary) }
                .font(.system(size: 12, weight: .medium)).padding(9).contentShape(Rectangle())
        }.buttonStyle(.plain).background(store.page == page ? Color.primary.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 9))
    }
    @ViewBuilder var content: some View {
        if !store.rangeReady { emptyState(loading: true) }
        else if store.selectedConversationID != nil || store.page == .tasks { taskList }
        else if store.selectedProjectID != nil || store.page == .conversations { conversationList }
        else if store.page == .projects { projectList }
        else { modelList }
    }
    var projectList: some View {
        Group {
            if store.filteredProjects.isEmpty { emptyState() }
            else { ScrollView { LazyVStack(spacing: 10) { ForEach(store.filteredProjects) { project in
                Button { store.openProject(project) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        rowHeader(displayProject(project.name), "folder", project.usage.total)
                        Text(project.path.isEmpty ? L("缺少工作目录") : project.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2).help(project.path)
                        Text(L("\(project.conversations.count) 个对话") + " · " + L("\(project.tasks.count) 个任务") + " · " + L("最近活动") + " " + date(project.lastActivity)).font(.system(size: 11)).foregroundStyle(.secondary)
                        UsageMetrics(usage: project.usage)
                    }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
                }.buttonStyle(.plain)
            } } } }
        }
    }
    var conversationList: some View {
        Group {
            if store.filteredConversations.isEmpty { emptyState() }
            else { ScrollView { LazyVStack(spacing: 10) { ForEach(store.filteredConversations) { chat in
                Button { store.openConversation(chat) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        rowHeader(displayTitle(chat.title), "bubble.left.and.bubble.right", chat.usage.total)
                        HStack {
                            Text(L("\(chat.tasks.count) 个任务") + " · " + L("\(chat.responses) 次响应") + " · " + date(chat.lastActivity))
                            Spacer()
                            if chat.spansProjects { Text(L("涉及多个项目")) }
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(Array(Set(chat.tasks.map(\.projectPath))).sorted().map { $0.isEmpty ? L("未识别项目") : $0 }.joined(separator: " · ")).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                        UsageMetrics(usage: chat.usage)
                    }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
                }.buttonStyle(.plain)
            } } } }
        }
    }
    var taskList: some View {
        Group {
            if store.filteredTasks.isEmpty { emptyState() }
            else { ScrollView { LazyVStack(spacing: 8) { ForEach(store.filteredTasks) { task in TaskCard(task: task, store: store, expanded: store.selectedTaskID == task.id) } } }.id(store.selectedConversationID ?? "tasks") }
        }
    }
    var modelList: some View {
        Group {
            if store.filteredModels.isEmpty { emptyState() }
            else { ScrollView { LazyVStack(spacing: 10) { ForEach(store.filteredModels) { model in
                VStack(alignment: .leading, spacing: 10) {
                    rowHeader(L(model.model), "cpu", model.usage.total)
                    Text(L("\(model.taskIDs.count) 个任务 · \(model.responses) 次调用")).font(.system(size: 11)).foregroundStyle(.secondary)
                    UsageMetrics(usage: model.usage)
                    HStack { Spacer(); Button(L("查看相关任务")) { store.navigate(.tasks); store.modelFilter = model.model } }
                }.padding(15).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            } } } }
        }
    }
    @ViewBuilder var conversationSummary: some View {
        if let chat = store.conversation {
            DisclosureGroup(L("用途与模型")) {
                ScrollView {
                  VStack(alignment: .leading, spacing: 8) {
                    ForEach(chat.modelUsage) { model in
                        HStack { Text(L(model.model)); Spacer(); Text(compactTokens(model.usage.total)).monospacedDigit(); Text(L("\(model.responses) 次响应")).foregroundStyle(.secondary) }.font(.system(size: 11))
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(chat.categoryTotals, id: \.0) { category, amount, _ in
                            HStack { Circle().fill(category.color).frame(width: 7, height: 7); Text(L(category.title)); Text(compactTokens(amount)).monospacedDigit() }.font(.system(size: 10))
                        }
                    }
                  }.padding(.top, 6)
                }.frame(maxHeight: 145)
            }.font(.system(size: 11)).id(chat.id)
        }
    }
    func emptyState(loading: Bool = false) -> some View {
        VStack(spacing: 10) {
            if loading { ProgressView() } else { Image(systemName: "tray").font(.system(size: 28)).foregroundStyle(.secondary) }
            Text(loading ? L("正在整理日志，请稍候") : store.snapshot.warnings.isEmpty ? L("这个范围内没有匹配的任务") : L("需要检查数据目录")).font(.system(size: 13))
            if !loading {
                Text(L("可以切换日期、清除筛选，或在设置中检查数据目录。")).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack { Button(L("清除筛选")) { store.clearFilters() }; Button(L("设置…")) { store.navigate(.settings) } }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    func rowHeader(_ title: String, _ symbol: String, _ total: Int64) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.blue)
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Text(compactTokens(total)).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit().fixedSize()
            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary).padding(.top, 5)
        }
    }
    func displayProject(_ value: String) -> String { value == ProjectIdentity.unknown.name ? L(value) : value }
    func displayTitle(_ value: String) -> String { ["未记录用户请求", "Codex 后台检查"].contains(value) ? L(value) : value }
    func date(_ value: Date) -> String { value.formatted(Date.FormatStyle().month().day().hour().minute().locale(Locale(identifier: store.language == "en" ? "en_US" : "zh_CN"))) }
    var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("数据来源")).font(.system(size: 16, weight: .semibold))
                    Text(store.sourcePath).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    HStack { Button(L("选择 Codex 数据目录…")) { store.chooseDirectory() }; Button(L("在 Finder 中显示")) { NSWorkspace.shared.selectFile(store.sourcePath, inFileViewerRootedAtPath: "") } }
                    Text(L("按需读取 sessions 和 archived_sessions 中的日志。每 30 秒检查一次，只重新解析发生变化的文件。")).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(L("项目按工作目录或 Git 仓库分组。对话标题只读本机元数据，缺失时使用用户请求。")).font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("菜单栏与启动")).font(.system(size: 16, weight: .semibold))
                    Toggle(L("菜单栏显示今日 token 数字"), isOn: Binding(get: { store.showFullStatus }, set: store.setStatusStyle))
                    Picker(L("外观"), selection: Binding(get: { store.appearance }, set: store.setAppearance)) { Text(L("跟随系统")).tag("system"); Text(L("浅色")).tag("light"); Text(L("深色")).tag("dark") }.frame(maxWidth: 270)
                    Picker(L("语言"), selection: Binding(get: { store.language }, set: store.setLanguage)) { Text("English").tag("en"); Text("简体中文").tag("zh") }.frame(maxWidth: 270)
                    Toggle(L("登录时启动"), isOn: Binding(get: { store.launchAtLogin }, set: store.setLogin)).disabled(LedgerPreferences.isDemo)
                    Text(L("登录启动建议在将应用移动到固定位置后开启。右键点击菜单栏图标也可刷新、打开账本或退出。")).font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("如何理解数字")).font(.system(size: 16, weight: .semibold))
                    Text(L("总 token = 输入 + 输出。缓存和推理分别是输入、输出的子集。日期按模型调用时间统计。项目内的对话只显示归属该项目的消耗；全局对话显示所选日期内的完整消耗。只覆盖本机可读日志，不代表订阅额度或账单。")).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled)
                    Text(L("只读本机日志及对话索引，不联网、不调用模型、不读取登录凭证。CSV 仅在你选择导出时保存。")).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(String(format: L("上次扫描 %.2f 秒 · %d 份日志"), store.lastScanSeconds, store.snapshot.files)).font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
