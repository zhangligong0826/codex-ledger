import SwiftUI

struct GoalAssignmentMenu: View {
    @ObservedObject var store: LedgerStore
    var target: GoalTarget
    var suggestedName: String
    var body: some View {
        Menu {
            Text(L(target.kind == .project ? "此项目（含后续任务）" : target.kind == .conversation ? "整个对话（所有项目及后续轮次）" : "仅此轮次"))
            ForEach(store.goalBook.goals) { goal in
                Button { store.assignGoal(target, to: goal.id) } label: {
                    if store.goalBook.bindings[target.key] == goal.id { Label(goal.name, systemImage: "checkmark") } else { Text(goal.name) }
                }
            }
            Divider()
            Button(L("新建目标并归入…")) { store.newGoal(name: suggestedName, target: target) }
            Button(L("不归入目标")) { store.assignGoal(target, to: nil) }
            Button(L("沿用上级归属")) { store.resetGoalAssignment(target) }
        } label: { Label(L("归入目标"), systemImage: "target") }
        .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11))
    }
}
struct GoalEditorView: View {
    @ObservedObject var store: LedgerStore
    let draft: GoalEditorDraft
    @State private var name = ""
    @State private var budget = ""
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
                        Text(L("先给成果命名，再从项目或对话的“归入目标”菜单加入相关工作。跨对话、跨目录和问答轮次都能计入同一目标。")).font(.system(size: 12)).foregroundStyle(.secondary)
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
            }
        }
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
    @State private var confirmDelete = false
    private var lifetimeDescription: String {
        guard store.goalAmountsReady else { return store.dataUnavailable ? "—" : L("正在整理日志…") }
        let tokens = compactTokens(entry.lifetimeUsage.total) + " tokens"
        let turns = L("\(entry.lifetimeTasks.count) 个任务")
        let chats = L("\(Set(entry.lifetimeTasks.map(\.sessionID)).count) 个对话")
        return [tokens, turns, chats].joined(separator: " · ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("累计预估 API 花费")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(store.goalAmountsReady ? LedgerPricing.display(entry.lifetimeCost) + " USD" : store.dataUnavailable ? "—" : "…").font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(lifetimeDescription).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(L(entry.goal.completedAt == nil ? "进行中" : "已完成")).font(.system(size: 12, weight: .medium)).foregroundStyle(entry.goal.completedAt == nil ? .blue : .green)
                    if let date = entry.goal.completedAt { Text(date.formatted(.dateTime.year().month().day())).font(.system(size: 10)).foregroundStyle(.secondary) }
                    if let cost = entry.goal.completionCost { Text(L("完成时") + " " + LedgerPricing.display(cost) + " USD").font(.system(size: 11, weight: .medium)).monospacedDigit() }
                    Menu(L("管理目标")) {
                        Button(L("重命名目标")) { store.editGoal(entry.goal) }
                        Button(L(entry.goal.completedAt == nil ? "标记完成" : "重新打开目标")) { store.completeGoal(entry.id) }.disabled(!store.goalAmountsReady || store.busy)
                        Button(L("导出轮次 CSV")) { store.exportCSV(turns: true) }.disabled(store.busy || !store.rangeReady || store.dataUnavailable)
                        Divider()
                        Button(L("删除目标"), role: .destructive) { confirmDelete = true }
                    }.fixedSize()
                }
            }
            if let text = GoalBudget.label(entry.goal, cost: entry.goal.completionCost ?? entry.lifetimeCost, complete: entry.goal.completionCost != nil || store.goalAmountsReady) { Text(text).font(.system(size: 11)).foregroundStyle(.secondary) }
            Text(L("金额为 API 估算。标记完成会保存当时金额，累计不受日期筛选影响。")).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .help(L("后续用量继续计入累计，不改变完成时记录；重新打开目标会清除完成时记录。"))
            HStack {
                Button(L("从项目归入")) { store.navigate(.projects) }
                Button(L("从对话归入")) { store.navigate(.conversations) }
            }.font(.system(size: 11))
        }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .confirmationDialog(L("删除目标只移除归属规则，保留所有原始用量。"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("删除目标"), role: .destructive) { store.deleteGoal(entry.id) }
            Button(L("取消"), role: .cancel) {}
        }
    }
}
