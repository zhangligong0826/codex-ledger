import SwiftUI
private typealias GoalViewState<Value> = State<Value>

struct GoalAssignmentMenu: View {
    @ObservedObject var store: LedgerStore
    var target: GoalTarget
    var suggestedName: String
    var body: some View {
        Menu {
            Text(L(target.kind == .project ? "选择此项目的工作范围" : target.kind == .conversation ? "选择此对话的工作范围" : "仅此轮次"))
            ForEach(store.goalBook.goals) { goal in
                Button { store.beginAssignment(goalID: goal.id, target: target) } label: {
                    if store.goalBook.bindings[target.key] == goal.id { Label(goal.name, systemImage: "checkmark") } else { Text(goal.name) }
                }
            }
            Divider()
            Button(L("新建目标并归入…")) { store.newGoal(name: suggestedName, target: target) }
            Button(L("不归入目标")) { store.beginAssignment(goalID: GoalBook.unassigned, target: target) }
            Button(L("使用项目／对话的归属")) { store.resetGoalAssignment(target) }
        } label: { Label(L("归入目标"), systemImage: "target") }
        .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11))
    }
}
struct GoalEditorView: View {
    @ObservedObject var store: LedgerStore
    let draft: GoalEditorDraft
    @GoalViewState private var name = ""
    @GoalViewState private var budget = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L(draft.goalID == nil ? "新建目标" : "重命名目标")).font(.headline)
            TextField(L("例如：开发 Codex Ledger、完成论文投稿"), text: $name).textFieldStyle(.roundedBorder)
                .onSubmit { save() }
            TextField(L("USD 预算（可选）"), text: $budget).textFieldStyle(.roundedBorder)
            Text(L("把同一成果的项目、对话或轮次归到一起，累计其用量和预估金额。")).font(.system(size: 12)).foregroundStyle(.secondary)
            HStack { Spacer(); Button(L("取消")) { store.goalEditor = nil }.keyboardShortcut(.cancelAction)
                Button(L("保存")) { save() }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(22).frame(width: 410).onAppear { name = draft.name; budget = draft.budget }
    }
    private func save() { store.saveGoal(name: name, draft: draft, budgetText: budget) }
}
struct GoalListView: View {
    @ObservedObject var store: LedgerStore
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if store.goalBook.goals.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L("完成一个目标，累计花了多少？"), systemImage: "target").font(.system(size: 19, weight: .semibold))
                        Text(L("给成果命名，添加项目、对话或具体轮次，再核对归属和估算金额。")).font(.system(size: 12)).foregroundStyle(.secondary)
                        Button(L("新建目标")) { store.newGoal() }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                } else if store.filteredGoals.isEmpty {
                    Text(L("没有匹配的目标")).foregroundStyle(.secondary).padding(20)
                }
                ForEach(store.filteredGoals) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        Button { store.openGoal(entry.id) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: entry.goal.completedAt == nil ? "target" : "checkmark.circle.fill").foregroundStyle(entry.goal.completedAt == nil ? .blue : .green)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.goal.name).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                                    Text(L(entry.goal.completedAt == nil ? "进行中" : "已完成")).font(.system(size: 11)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(entry.goal.completionCost != nil || store.goalAmountsReady ? LedgerPricing.display(entry.goal.completionCost ?? entry.lifetimeCost) + " USD" : store.dataUnavailable ? "—" : "…").font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                                    Text(L(entry.goal.completionCost == nil ? "累计预估 API 花费" : "完成时预估 API 花费")).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        HStack {
                            Text(rangeLabel(entry))
                            Spacer()
                            Text(countLabel(entry))
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                        if let text = GoalBudget.label(entry.goal, cost: entry.goal.completionCost ?? entry.lifetimeCost, complete: entry.goal.completionCost != nil || store.goalAmountsReady) { Text(text).font(.system(size: 11)).foregroundStyle(.secondary) }
                        if let last = entry.lastActivity { Text(L("最近活动") + " " + last.formatted(.dateTime.month().day().hour().minute())).font(.system(size: 10)).foregroundStyle(.tertiary) }
                    }.padding(16).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("未归入目标")).font(.system(size: 13, weight: .medium)); Spacer()
                        Text((store.dataUnavailable ? "—" : LedgerPricing.display(LedgerPricing.total(store.unassignedTasks))) + " USD").monospacedDigit()
                        Button(L("查看相关任务")) { store.showUnassigned() }
                    }
                    Text(L("未归属的用量会保留，归入目标后才计入其金额。每轮只计入一个目标；轮次归属优先于对话，对话优先于项目。")).font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(16)
            }.scrollTargetLayout()
        }.scrollPosition(id: $store.scrollAnchor)
    }
    private func rangeLabel(_ entry: GoalUsage) -> String {
        let prefix = L("所选日期") + " · "
        if store.dataUnavailable { return prefix + "—" }
        let amount = LedgerPricing.display(entry.cost) + " USD"
        let tokens = compactTokens(entry.usage.total) + " tokens"
        return prefix + amount + " · " + tokens
    }
    private func countLabel(_ entry: GoalUsage) -> String {
        if store.dataUnavailable { return "—" }
        let turns = L("\(entry.tasks.count) 个任务")
        let chats = L("\(Set(entry.tasks.map(\.sessionID)).count) 个对话")
        return turns + " · " + chats
    }
}
struct GoalDetailHeader: View {
    @ObservedObject var store: LedgerStore
    let entry: GoalUsage
    @GoalViewState private var confirmDelete = false
    private var lifetimeDescription: String {
        guard store.goalAmountsReady else { return store.dataUnavailable ? "—" : L("正在整理日志…") }
        if entry.goal.completedAt != nil, let record = entry.goal.completions.last {
            let tokens = compactTokens(record.usage.total) + " tokens"
            if record.legacy { return tokens + " · " + L("旧记录未保存归属明细") }
            let members = store.lifetime.tasks.filter { record.turnIDs.contains($0.id) }
            return tokens + " · " + L("\(record.turnIDs.count) 个任务") + " · " + L("\(Set(members.map(\.sessionID)).count) 个对话")
        }
        let tokens = compactTokens(entry.lifetimeUsage.total) + " tokens"
        let turns = L("\(entry.lifetimeTasks.count) 个任务")
        let chats = L("\(Set(entry.lifetimeTasks.map(\.sessionID)).count) 个对话")
        return [tokens, turns, chats].joined(separator: " · ")
    }
    private var currentCostDescription: String {
        let current = L("当前累计") + " " + LedgerPricing.display(entry.lifetimeCost) + " USD"
        let later = L("完成后用量") + " " + LedgerPricing.display(LedgerPricing.total(store.postCompletionTasks(entry.id))) + " USD"
        return [current, later].joined(separator: " · ")
    }
    private func historyDescription(_ record: CompletionRecord) -> String {
        var parts = [record.completedAt.formatted(.dateTime.year().month().day().hour().minute()), LedgerPricing.display(record.cost) + " USD"]
        if record.legacy { parts.append(L("旧记录未保存归属明细")) }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L(entry.goal.completedAt == nil ? "累计预估 API 花费" : "完成时预估 API 花费")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(store.goalAmountsReady ? LedgerPricing.display(entry.goal.completionCost ?? entry.lifetimeCost) + " USD" : store.dataUnavailable ? "—" : "…").font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    Text(lifetimeDescription).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(L(entry.goal.completedAt == nil ? "进行中" : "已完成")).font(.system(size: 12, weight: .medium)).foregroundStyle(entry.goal.completedAt == nil ? .blue : .green)
                    if let date = entry.goal.completedAt { Text(date.formatted(.dateTime.year().month().day())).font(.system(size: 10)).foregroundStyle(.secondary) }
                    Menu(L("管理目标")) {
                        Button(L("重命名目标")) { store.editGoal(entry.goal) }
                        Button(L(entry.goal.completedAt == nil ? "标记完成" : "重新打开目标")) { store.completeGoal(entry.id) }.disabled(entry.goal.completedAt == nil && !store.canCompleteGoal(entry.id))
                        Button(L("导出轮次 CSV")) { store.exportCSV(turns: true) }.disabled(!store.rangeReady || store.dataUnavailable)
                        Divider()
                        Button(L("删除目标"), role: .destructive) { confirmDelete = true }
                    }.fixedSize()
                }
            }
            if let text = GoalBudget.label(entry.goal, cost: entry.goal.completionCost ?? entry.lifetimeCost, complete: entry.goal.completionCost != nil || store.goalAmountsReady) { Text(text).font(.system(size: 11)).foregroundStyle(.secondary) }
            HStack {
                Button(L("添加工作")) { store.beginAssignment(goalID: entry.id) }.buttonStyle(.borderedProminent)
                Button(L(entry.goal.completedAt == nil ? "确认完成" : "重新打开目标")) { store.completeGoal(entry.id) }
                    .disabled(entry.goal.completedAt == nil && !store.canCompleteGoal(entry.id))
                if entry.goal.completedAt != nil { Button(L("生成成果卡片")) { store.makeShareCard() } }
                if store.canUndoAttribution { Button(L("撤销归属修改")) { store.undoAttribution() } }
            }.font(.system(size: 11))
            if store.busy { Text(L("正在刷新，完成确认请稍候")).font(.caption).foregroundStyle(.secondary) }
            let coverage = store.goalCoverage(entry.id)
            if !coverage.canComplete { Text(coverage.status == .loading ? L("正在整理日志…") : L("已知估算金额") + " · " + coverage.reasons.map(L).joined(separator: " · ")).font(.caption).foregroundStyle(.orange) }
            DisclosureGroup(L("金额说明与完成记录")) {
                Text(L("金额为 API 估算。标记完成会保存当时金额，累计不受日期筛选影响。")).font(.caption).foregroundStyle(.secondary)
                Text(L("完成记录永久保留；重新打开不会恢复已停止的持续归属规则。")).font(.caption).foregroundStyle(.secondary)
                if store.goalBook.bindings.values.contains(entry.id) { Text(L("旧版持续规则") + " · " + L("保留原来的历史和未来覆盖行为")).font(.caption).foregroundStyle(.secondary) }
                if entry.goal.completedAt != nil { Text(currentCostDescription).font(.caption).foregroundStyle(.secondary) }
                ForEach(entry.goal.completions) { record in Text(historyDescription(record)).font(.caption) }
            }.font(.caption)
        }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .confirmationDialog(L("删除目标只移除归属规则，保留所有原始用量。"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("删除目标"), role: .destructive) { store.deleteGoal(entry.id) }
            Button(L("取消"), role: .cancel) {}
        }
    }
}

struct AssignmentView: View {
    @ObservedObject var store: LedgerStore
    let draft: AssignmentDraft
    @GoalViewState private var targetKey = ""
    @GoalViewState private var query = ""
    @GoalViewState private var mode = AttributionMode.selected
    @GoalViewState private var from = Calendar.current.startOfDay(for: Date())
    @GoalViewState private var ongoing = false
    @GoalViewState private var selected = Set<String>()
    private var targets: [GoalTarget] {
        if let target = draft.target { return [target] }
        let projects = store.lifetime.projects.map { GoalTarget(kind: .project, id: $0.id) }
        let chats = store.lifetime.conversations.map { GoalTarget(kind: .conversation, id: $0.id) }
        return projects + chats + store.lifetime.tasks.map { GoalTarget(kind: .turn, id: $0.id) }
    }
    private var target: GoalTarget? { targets.first { $0.key == targetKey } }
    private func title(_ target: GoalTarget) -> String {
        switch target.kind {
        case .project: return L("项目") + " · " + (store.lifetime.projects.first { $0.id == target.id }.map { L($0.name) + " · " + $0.path } ?? target.id)
        case .conversation: return L("对话") + " · " + (store.lifetime.conversations.first { $0.id == target.id }?.title ?? target.id)
        case .turn: return L("任务轮次") + " · " + (store.lifetime.tasks.first { $0.id == target.id }?.title ?? target.id)
        }
    }
    private var matching: [LedgerTask] {
        guard let target else { return [] }
        return store.lifetime.tasks.filter { target.kind == .turn ? $0.id == target.id : target.kind == .conversation ? $0.sessionID == target.id : $0.projectID == target.id }
    }
    private var rule: AttributionRule? {
        guard let target else { return nil }
        return AttributionRule(target: target, goalID: draft.goalID, mode: mode, turnIDs: selected, start: mode == .fromDate ? from : nil,
            end: mode != .selected && !ongoing ? Date() : nil)
    }
    private func previewDescription(_ count: Int, cost: CostEstimate) -> String {
        [L("归属预览"), String(count) + " " + L("任务轮次"), LedgerPricing.display(cost) + " USD"].joined(separator: " · ")
    }
    private func displacementDescription(_ id: String, count: Int) -> String {
        let name = store.goalBook.goals.first { $0.id == id }?.name ?? id
        return L("将从以下目标移出工作") + ": " + name + " · " + String(count)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("添加工作") + " · " + (store.goalBook.goals.first { $0.id == draft.goalID }?.name ?? "")).font(.headline).lineLimit(2)
            TextField(L("搜索项目、路径或对话"), text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(targets.filter { query.isEmpty || title($0).localizedCaseInsensitiveContains(query) }, id: \.key) { value in
                        Button { targetKey = value.key; selected = Set(matching.map(\.id)) } label: { HStack { Image(systemName: targetKey == value.key ? "checkmark.circle.fill" : "circle"); Text(title(value)).lineLimit(2); Spacer() } }.buttonStyle(.plain)
                    }
                }
            }.frame(height: 120)
            Picker(L("归属范围"), selection: $mode) {
                Text(L("仅选中的历史工作")).tag(AttributionMode.selected)
                Text(L("从指定日期开始")).tag(AttributionMode.fromDate)
                Text(L("整个项目或对话")).tag(AttributionMode.entire)
            }
            if mode == .selected {
                ScrollView { LazyVStack(alignment: .leading) { ForEach(matching) { task in
                    Toggle(task.title + " · " + LedgerPricing.display(task.cost) + " USD", isOn: Binding(get: { selected.contains(task.id) }, set: { if $0 { selected.insert(task.id) } else { selected.remove(task.id) } })).font(.caption)
                } } }.frame(height: 100)
            } else {
                if mode == .fromDate { DatePicker(L("开始时间（本机时区）"), selection: $from) }
                Toggle(L("持续包含后续开始的轮次"), isOn: $ongoing).disabled(store.goalBook.goals.first { $0.id == draft.goalID }?.completedAt != nil)
            }
            if let rule {
                let preview = store.goalBook.preview(rule, tasks: store.lifetime.tasks)
                Text(previewDescription(preview.tasks.count, cost: preview.cost)).font(.headline)
                ForEach(preview.displaced.keys.sorted(), id: \.self) { id in Text(displacementDescription(id, count: preview.displaced[id]!)).font(.caption).foregroundStyle(.orange) }
            }
            HStack { Button(L("取消")) { store.assignmentDraft = nil }.keyboardShortcut(.cancelAction); Spacer()
                Button(L("保存归属")) { if let rule { store.saveAssignment(rule) } }.keyboardShortcut(.defaultAction).disabled(rule == nil || !store.lifetimeReady)
            }
        }.padding(22).frame(width: 560).onAppear { targetKey = draft.target?.key ?? ""; selected = Set(matching.map(\.id)) }
    }
}
