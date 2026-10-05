import Foundation
@main struct V2Tests {
    static func main() throws {
        var count = 0
        func expect(_ value: Bool, _ label: String) { precondition(value, label); count += 1 }
        let start = Date(timeIntervalSince1970: 1_790_000_000), complete = start.addingTimeInterval(200)
        var tasks = LedgerDemo.snapshot(scope: .history).tasks
        for i in tasks.indices { tasks[i].startedAt = start.addingTimeInterval(Double(i) * 10); tasks[i].date = tasks[i].attributionStart }
        let a = LedgerGoal(id: "a", name: "Outcome A"), b = LedgerGoal(id: "b", name: "Outcome B")
        var book = GoalBook(goals: [a, b])
        let project = GoalTarget(kind: .project, id: tasks[0].projectID)
        let selected = AttributionRule(target: project, goalID: a.id, mode: .selected, turnIDs: [tasks[0].id], savedAt: start)
        book.apply(selected)
        expect(book.owner(tasks[0]) == a.id, "fixed selection owns selected work")
        var future = tasks[0]; future.id = "future"; future.startedAt = complete.addingTimeInterval(20)
        expect(book.owner(future) == nil, "fixed selection never receives future work")
        let live = AttributionRule(target: project, goalID: b.id, mode: .fromDate, start: start, savedAt: start.addingTimeInterval(20))
        let preview = book.preview(live, tasks: tasks)
        expect(preview.displaced[a.id] == nil && preview.cost == LedgerPricing.total(preview.tasks), "preview respects fixed turn precedence and exact cost")
        book.apply(live)
        expect(book.owner(tasks[0]) == a.id, "fixed historical work has turn precedence")
        book.apply(AttributionRule(target: project, goalID: b.id, mode: .selected, turnIDs: [tasks[0].id], savedAt: start.addingTimeInterval(30)))
        expect(book.owner(tasks[0]) == b.id, "newest fixed selection wins at turn precedence")
        var sliced = tasks[0]; sliced.date = complete.addingTimeInterval(10)
        expect(book.owner(sliced) == b.id, "response date does not change stable attribution")
        book.apply(AttributionRule(target: GoalTarget(kind: .conversation, id: tasks[0].sessionID), goalID: a.id, mode: .selected, turnIDs: [tasks[0].id]))
        expect(book.owner(tasks[0]) == a.id, "conversation beats project")
        book.apply(AttributionRule(target: GoalTarget(kind: .turn, id: tasks[0].id), goalID: b.id, mode: .selected, turnIDs: [tasks[0].id]))
        expect(book.owner(tasks[0]) == b.id, "turn beats conversation")
        let issue = LogIssue(path: "synthetic", messages: ["conflict"], dates: [start], affectedTurnIDs: [tasks[0].id], unknownScope: false)
        let snapshot = LedgerSnapshot(tasks: tasks, warnings: ["conflict"], logIssues: [issue])
        expect(AccountingCoverage.evaluate(snapshot, turnIDs: ["unrelated"]).canComplete, "unrelated dated issue does not block")
        expect(!AccountingCoverage.evaluate(snapshot, turnIDs: [tasks[0].id]).canComplete, "related issue blocks completion")
        expect(!AccountingCoverage.evaluate(LedgerSnapshot(warnings: ["missing source"], hasReadFailures: true), turnIDs: []).canComplete, "empty context cannot hide unknown failure")
        expect(AccountingCoverage.evaluate(snapshot, loaded: false).status == .loading, "loading separate from partial")
        book.complete(b.id, tasks: tasks, now: complete, capturedAt: start, coverage: .init(status: .partial, reasons: ["conflict"]))
        expect(book.goals[1].completions.isEmpty, "partial data cannot freeze final amount")
        book.complete(b.id, tasks: tasks, now: complete, capturedAt: start, coverage: .init(status: .complete))
        let frozen = book.goals[1].completions[0]
        expect(book.owner(future) == nil, "continuous rule stops new starts at completion")
        expect(book.owner(sliced) == b.id, "inflight work retains owner after completion")
        book.reopen(b.id)
        expect(book.goals[1].completions == [frozen] && book.owner(future) == nil, "reopen preserves history and stopped rule")
        book.complete(b.id, tasks: tasks, now: complete.addingTimeInterval(10), capturedAt: complete, coverage: .init(status: .complete))
        expect(book.goals[1].completions.count == 2 && book.goals[1].completions[0] == frozen, "recompletion appends immutable record")
        let restored = try GoalArchive.decode(GoalArchive.encode(book))
        expect(restored.rules.map(\.id) == book.rules.map(\.id) && restored.goals[1].completions.map(\.cost) == book.goals[1].completions.map(\.cost) && abs(restored.goals[1].completions[0].completedAt.timeIntervalSince(frozen.completedAt)) < 0.000001, "v2 portable records and UTC dates roundtrip")
        let roots = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let legacy = try GoalArchive.decode(Data(contentsOf: roots.appendingPathComponent("Common/goal-backup-fixture.json")))
        expect(legacy.version == 2 && legacy.goals[0].completions[0].legacy && legacy.goals[0].completions[0].turnIDs.isEmpty, "v1 migrates without fabricated membership")
        expect(legacy.goals[0].completions[0].cost == legacy.goals[0].completionCost, "v1 money remains exact")
        let unknown = CostEstimate(unpricedTokens: 99)
        var unknownTask = tasks[0]; unknownTask.modelUsage = [ModelUsage(model: "future-model", usage: TokenUsage(["input_tokens": 99]), cost: unknown)]
        var unknownBook = GoalBook(goals: [a]); unknownBook.assign(GoalTarget(kind: .turn, id: unknownTask.id), to: a.id)
        unknownBook.complete(a.id, tasks: [unknownTask], now: complete, capturedAt: complete, coverage: .init(status: .complete))
        expect(unknownBook.goals[0].completions[0].cost.unpricedTokens == 99, "unknown pricing alone permits completion with unpriced coverage")
        print("\(count)/\(count) v2 attribution, scoped coverage, immutable completion and migration checks passed")
    }
}
