import Foundation
@main @MainActor struct BenchmarkTests {
    static func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(30)
        while !condition() { guard Date() < deadline else { throw CocoaError(.coderReadCorrupt) }; try await Task.sleep(nanoseconds: 2_000_000) }
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-fixed-benchmark-" + UUID().uuidString)
        let sessions = root.appendingPathComponent("sessions"), cache = root.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "ledger.fixed.benchmark." + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(60)
        func line(_ type: String, _ payload: [String: Any], _ date: Date) throws -> String {
            String(data: try JSONSerialization.data(withJSONObject: ["timestamp": date.formatted(.iso8601), "type": type, "payload": payload]), encoding: .utf8)! + "\n"
        }
        var templates: [String] = []
        for day in 0..<90 {
            let date = Calendar.current.date(byAdding: .day, value: -day, to: now)!
            var text = try line("session_meta", ["id": "BENCH_SESSION", "cwd": "/tmp/ledger-synthetic-benchmark"], date)
            text += try line("turn_context", ["turn_id": "turn", "model": "gpt-5.4"], date)
            for response in 0..<20 { text += try line("token_usage_record", ["thread_id": "BENCH_SESSION", "turn_id": "turn", "response_id": "BENCH_SESSION-response-\(response)", "model": "gpt-5.4", "usage": ["input_tokens": 100, "output_tokens": 10]], date) }
            templates.append(text)
        }
        for i in 0..<1000 {
            let file = sessions.appendingPathComponent("session-\(i).jsonl"), date = Calendar.current.date(byAdding: .day, value: -(i % 90), to: now)!
            try templates[i % 90].replacingOccurrences(of: "BENCH_SESSION", with: "benchmark-\(i)").write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        }
        let cold = LedgerStore(sourcePath: root.path, defaults: defaults, scanner: LedgerScanner(cacheDirectory: cache))
        cold.refresh(recentFirst: true); try await wait { cold.lifetimeReady && !cold.busy }
        precondition(cold.lifetime.usage.total == 2_200_000, "fixed corpus full total")
        let warm = LedgerStore(sourcePath: root.path, defaults: defaults, scanner: LedgerScanner(cacheDirectory: cache))
        let begin = Date(); warm.refresh(recentFirst: true)
        try await wait { warm.todayIsReady }; let today = Date().timeIntervalSince(begin)
        try await wait { warm.lifetimeReady && !warm.busy }; let history = Date().timeIntervalSince(begin)
        let navigationStart = Date(); warm.scope = .history; try await wait { warm.rangeReady && !warm.busy }; warm.navigate(.projects)
        _ = warm.filteredProjects; let navigation = Date().timeIntervalSince(navigationStart)
        precondition(warm.lifetime.usage == cold.lifetime.usage && warm.lifetime.cost == cold.lifetime.cost, "warm cache preserves counts and Decimal cost")
        print(String(format: "BENCHMARK fixed corpus: 1000 logs / 20000 responses; warm today %.3fs; complete history %.3fs; ordinary navigation %.3fs; targets 2s / 5s / 1s", today, history, navigation))
    }
}
