import Foundation

@main @MainActor struct GoalTests {
    static func main() throws {
        var checks = 0
        func expect(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        let lifetime = LedgerDemo.snapshot(scope: .history), current = LedgerDemo.snapshot()
        let first = LedgerGoal(id: "goal-app", name: "Build Codex Ledger"), second = LedgerGoal(id: "goal-paper", name: "=Research, \"paper\"\nreport")
        var book = GoalBook(goals: [first, second])
        let chat = GoalTarget(kind: .conversation, id: "demo-chat-1"), project = GoalTarget(kind: .project, id: "demo-atlas")
        book.assign(project, to: first.id)
        book.assign(chat, to: first.id)
        expect(current.tasks.filter { book.owner($0) == first.id }.count == 5, "cross-project conversation and project overlap counts each turn once")
        book.assign(chat, to: second.id)
        expect(current.tasks.filter { book.owner($0) == second.id }.count == 3, "conversation rule overrides project and captures all its directories")
        let turn = current.tasks.first { $0.sessionID == chat.id }!
        let target = GoalTarget(kind: .turn, id: turn.id)
        book.assign(target, to: first.id)
        expect(book.owner(turn) == first.id, "individual turn overrides conversation")
        book.assign(target, to: nil)
        expect(book.owner(turn) == nil, "explicit unassignment suppresses inherited rules")
        book.bindings.removeValue(forKey: target.key)
        expect(book.owner(turn) == second.id, "reset restores inherited ownership")
        let summaries = book.summaries(current: current.tasks, lifetime: lifetime.tasks)
        let assigned = summaries.flatMap(\.tasks), unassigned = current.tasks.filter { book.owner($0) == nil }
        expect(Set(assigned.map(\.id)).count == assigned.count, "no duplicated turn in goal totals")
        expect((assigned + unassigned).reduce(TokenUsage()) { $0 + $1.usage } == current.usage, "goals plus unassigned reconcile every token subset")
        expect(LedgerPricing.total(assigned) + LedgerPricing.total(unassigned) == current.cost, "priced and unpriced Decimal costs reconcile exactly")
        expect(summaries.first { $0.id == second.id }!.lifetimeUsage.total > summaries.first { $0.id == second.id }!.usage.total, "lifetime is independent of selected dates")
        expect(book.summaries(current: [], lifetime: lifetime.tasks).count == 2, "goals stay visible with no usage in the selected period")
        let restored = try GoalBook.decode(JSONEncoder().encode(book))
        expect(restored.bindings == book.bindings && restored.goals == book.goals, "names and scoped attribution survive storage")
        let csv = LedgerCSV.renderGoals(summaries, scope: "Today", lifetimeReady: true, translate: { $0 })
        expect(csv.contains("'="), "user-defined goal names are CSV formula escaped")
        expect(csv.contains("\"\"paper\"\"\nreport"), "CSV protects quoted and multiline goal names")
        expect(csv.contains(String(summaries.first { $0.id == second.id }!.lifetimeUsage.total)), "CSV uses the same lifetime totals as UI")
        var invalid = book; invalid.version = 3
        do { _ = try GoalBook.decode(JSONEncoder().encode(invalid)); preconditionFailure("future schema accepted") } catch { checks += 1 }
        var duplicate = book; duplicate.goals.append(first)
        do { _ = try GoalBook.decode(JSONEncoder().encode(duplicate)); preconditionFailure("duplicate goal accepted") } catch { checks += 1 }
        book.remove(second.id)
        expect(!book.bindings.values.contains(second.id) && !book.goals.contains { $0.id == second.id }, "deletion removes rules without mutating source tasks")
        expect(current.usage.total == lifetime.tasks.filter { $0.id.hasPrefix("demo-turn-") }.reduce(TokenUsage()) { $0 + $1.usage }.total, "source usage remains intact")

        // Store tests isolate all writes in the demo preferences, never user data.
        let defaults = LedgerPreferences.defaults, key = "goalBook.v2:/Users/demo/.codex", previous = defaults.data(forKey: key)
        defaults.removeObject(forKey: "goalBook.v1:/Users/demo/.codex"); defaults.removeObject(forKey: key)
        defer { if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) } }
        defaults.removeObject(forKey: "dashboardDateScope"); defaults.removeObject(forKey: "overviewDateScope")
        let store = LedgerStore(); store.loadDemo(); store.language = "en"; LedgerText.language = "en"
        store.newGoal(name: "Build Codex Ledger", target: chat)
        store.saveGoal(name: "Build Codex Ledger", draft: store.goalEditor!)
        let goalID = store.selectedGoalID!
        expect(store.assignmentDraft != nil && store.goal!.lifetimeTasks.isEmpty, "new goal requires attribution preview before saving work")
        store.assignGoal(chat, to: goalID)
        store.assignmentDraft = nil
        expect(store.scope == .today && store.goal != nil, "new goal retains selected date and shows full lifetime")
        let allTokens = store.goal!.lifetimeUsage.total, allCost = store.goal!.lifetimeCost
        store.scope = .today
        expect(store.goal!.lifetimeUsage.total == allTokens && store.goal!.usage.total < allTokens, "date changes keep goal lifetime constant")
        store.completeGoal(goalID)
        expect(store.goal!.goal.completionCost == allCost && store.goal!.goal.completionUsage?.total == allTokens, "completion records cost and tokens at that point")
        store.assignGoal(GoalTarget(kind: .conversation, id: "demo-chat-3"), to: goalID)
        expect(store.goal!.lifetimeCost != allCost && store.goal!.goal.completionCost == allCost, "later attribution changes lifetime without rewriting completion record")
        let completedCSV = LedgerCSV.renderGoals(store.goals, scope: "Today", lifetimeReady: true, translate: L)
        expect(completedCSV.contains("At completion: Estimated API cost USD") && completedCSV.contains(LedgerPricing.decimalString(allCost.totalUSD)), "CSV exports the frozen completion cost separately from current lifetime")
        LedgerText.language = "zh"
        expect(LedgerCSV.renderGoals(store.goals, scope: "今天", lifetimeReady: true, translate: L).contains("完成时预估API花费USD"), "goal CSV follows Chinese language")
        LedgerText.language = "en"
        let turnCSV = LedgerCSV.render(store.contextTasks, goalNames: Dictionary(uniqueKeysWithValues: store.contextTasks.map { ($0.id, "Build Codex Ledger") }), translate: L)
        expect(turnCSV.contains("Goal") && turnCSV.contains("Build Codex Ledger"), "turn CSV includes its concrete goal name")
        let reloaded = LedgerStore()
        expect(reloaded.goalBook.goals.first?.completionCost == allCost, "completion record survives app restart")
        let goalChat = store.contextConversations.first { $0.id == chat.id }!
        store.openConversation(goalChat)
        expect(store.contextUsage == goalChat.usage, "goal conversation contains only goal-attributed turns")
        store.back()
        expect(store.selectedGoalID == goalID && store.selectedConversationID == nil, "back retains goal context")
        store.back(); expect(store.selectedGoalID == nil && store.page == .goals, "second back returns to goals")
        store.showUnassigned(); expect(store.contextTasks.count == store.unassignedTasks.count, "unassigned work can be reviewed")
        store.clearFilters(); expect(!store.unassignedOnly && store.contextTasks.count == store.snapshot.tasks.count, "clear filters exits unassigned view")
        store.search = "no match"; store.navigate(.goals); store.search = "Build"
        expect(store.filteredGoals.count == 1, "goal names are searchable")
        store.search = "/Projects/Research"
        expect(store.filteredGoals.count == 1, "goal search includes contributing directories")
        store.editGoal(store.goalBook.goals.first!)
        store.saveGoal(name: "Renamed outcome", draft: store.goalEditor!)
        expect(store.goalBook.goals.first?.name == "Renamed outcome" && store.goalBook.goals.first?.completionCost == allCost, "rename preserves ownership and completion cost")
        store.openGoal(goalID); store.completeGoal(goalID)
        expect(store.goal!.goal.completedAt == nil && store.goal!.goal.completionCost == nil, "reopen clears completion baseline")
        store.snapshot = LedgerSnapshot(warnings: ["Unreadable source"]); store.lifetime = store.snapshot; store.activity = []
        store.completeGoal(goalID)
        expect(store.goal!.goal.completedAt == nil, "unreadable usage cannot be recorded as a zero-cost completion")
        store.loadDemo()
        store.deleteGoal(goalID)
        expect(store.goalBook.goals.isEmpty && store.selectedGoalID == nil && store.lifetime.usage == lifetime.usage, "delete preserves all usage and exits deleted goal")
        defaults.set(Data("invalid".utf8), forKey: key)
        let corrupt = LedgerStore(); corrupt.newGoal(name: "Must not overwrite")
        expect(corrupt.goalEditor == nil && defaults.data(forKey: key) == Data("invalid".utf8), "unreadable goal storage is preserved, never silently overwritten")
        store.loadDemo(); store.goalBook = restored; store.lifetime.warnings = ["Unreadable synthetic source"]
        expect(!store.canCompleteGoal(first.id), "partial reads cannot freeze completion money")
        let previousCompletion = store.goalBook.goals.first?.completedAt
        store.completeGoal(first.id)
        expect(store.goalBook.goals.first?.completedAt == previousCompletion, "completion is unchanged when records are incomplete")
        let backups = try FileManager.default.contentsOfDirectory(at: GoalRecovery.directory, includingPropertiesForKeys: nil)
        expect(backups.contains { $0.lastPathComponent.hasSuffix(".backup.json") }, "changes retain a portable recovery copy")
        let beforeInvalidImport = store.goalBook.goals
        expect(!store.importGoalBackup(Data("{}".utf8)) && store.goalBook.goals == beforeInvalidImport, "invalid restore does not overwrite goal data")
        print("\(checks)/\(checks) goal attribution, completion, persistence and CSV checks passed")
    }
}
