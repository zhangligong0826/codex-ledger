import Foundation

@main @MainActor struct StorePerformanceTests {
    static func settle(_ store: LedgerStore) async throws {
        let deadline = Date().addingTimeInterval(15)
        while store.busy {
            guard Date() < deadline else { throw CocoaError(.coderReadCorrupt) }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    static func line(_ type: String, _ payload: [String: Any], date: Date) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: ["type": type, "payload": payload, "timestamp": date.formatted(.iso8601)]), encoding: .utf8)! + "\n"
    }
    static func log(response: String, input: Int, date: Date) throws -> String {
        try line("session_meta", ["id": "fixture-chat", "cwd": "/tmp/Codex-Ledger-Fixture"], date: date) +
        line("turn_context", ["turn_id": response, "model": "gpt-5.4"], date: date) +
        line("token_usage_record", ["thread_id": "fixture-chat", "turn_id": response, "response_id": response, "model": "gpt-5.4", "usage": ["input_tokens": input, "output_tokens": input / 10]], date: date)
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-performance-" + UUID().uuidString)
        let sessions = root.appendingPathComponent("sessions"), index = root.appendingPathComponent("index")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(60)
        let oldDate = Calendar.current.date(byAdding: .day, value: -45, to: now)!
        let recent = sessions.appendingPathComponent("recent.jsonl"), old = sessions.appendingPathComponent("old.jsonl")
        let recentData = try log(response: "recent", input: 100, date: now)
        try recentData.write(to: recent, atomically: true, encoding: .utf8)
        try log(response: "old", input: 80, date: oldDate).write(to: old, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: old.path)
        let suite = "local.codexledger.test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let scanner = LedgerScanner(cacheDirectory: index)
        let store = LedgerStore(sourcePath: root.path, defaults: defaults, scanner: scanner)
        let goal = LedgerGoal(name: "Synthetic outcome")
        store.goalBook.goals = [goal]
        store.goalBook.assign(GoalTarget(kind: .conversation, id: "fixture-chat"), to: goal.id)
        store.refresh(recentFirst: true)
        try await settle(store)
        precondition(store.rangeReady && store.todayIsReady && store.activityReady && store.lifetimeReady && store.goalAmountsReady, "staged startup finishes both current and lifetime ranges")
        precondition(store.snapshot.usage.total == 110 && store.lifetime.usage.total == 198 && store.goals.first!.id == goal.id, "current and historical usage stay separate")
        let initialCount = store.computationCount, historyCount = store.historyAggregationCount
        store.refresh(force: false); try await settle(store)
        precondition(store.computationCount == initialCount && scanner.parsedFileCount == 0, "timer refresh with no changes skips parsing and aggregation")
        store.scope = .month; try await settle(store)
        precondition(store.historyAggregationCount == historyCount && store.lifetime.usage.total == 198, "date changes reuse lifetime instead of rebuilding it")
        store.scope = .history; try await settle(store)
        precondition(store.snapshot.usage.total == 198 && store.historyAggregationCount == historyCount, "all time can reuse the existing complete snapshot")
        let cachedAmount = store.goals.first!.lifetimeCost
        store.goalBook.assign(GoalTarget(kind: .conversation, id: "fixture-chat"), to: nil)
        precondition(store.goals.first!.lifetimeUsage.total == 0, "goal edits invalidate cached ownership summaries")
        store.goalBook.assign(GoalTarget(kind: .conversation, id: "fixture-chat"), to: goal.id)
        precondition(store.goals.first!.lifetimeCost == cachedAmount, "reassignment restores exact Decimal cost")
        let before = store.computationCount
        let appended = try line("token_usage_record", ["thread_id": "fixture-chat", "turn_id": "recent", "response_id": "extra", "model": "gpt-5.4", "usage": ["input_tokens": 40, "output_tokens": 4]], date: now)
        try (recentData + appended).write(to: recent, atomically: true, encoding: .utf8)
        store.refresh(force: false); try await settle(store)
        precondition(store.computationCount == before + 1 && scanner.parsedFileCount == 1 && store.lifetime.usage.total == 242 && store.goals.first!.lifetimeUsage.total == 242, "new records update current, lifetime and goal amounts together")
        let forced = store.computationCount
        store.refresh(); try await settle(store)
        precondition(store.computationCount == forced + 1, "manual refresh always rechecks optional metadata and artifacts")
        try (recentData + appended + "bad complete line\n").write(to: recent, atomically: true, encoding: .utf8)
        store.refresh(force: false); try await settle(store)
        precondition(!store.canCompleteGoal(store.goalBook.goals.first!.id) && !store.lifetime.isComplete && store.lifetime.usage.total == 242, "corrupt source warnings survive cache use and block finalizing a goal")
        print("10/10 staged startup, unchanged refresh, cached scopes and goal invalidation checks passed")
    }
}
