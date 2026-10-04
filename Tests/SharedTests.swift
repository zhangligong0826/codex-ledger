import Foundation
extension CoreTests {
    static func sharedChecks(folder: URL) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Common/Fixtures")
        let parser = LogParser(), scanner = LedgerScanner(timezone: TimeZone(secondsFromGMT: 0)!)
        let scopes: [String: DateScope] = ["today": .today, "yesterday": .yesterday, "30d": .month, "all": .history]
        for file in try FileManager.default.contentsOfDirectory(at: fixtures, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            let value = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let now = parser.date(value["now"])!
            var logs: [ParsedLog] = []
            for (index, rows) in (value["logs"] as! [[[String: Any]]]).enumerated() {
                let url = folder.appendingPathComponent(file.lastPathComponent + String(index) + ".jsonl")
                let lines = try rows.map { String(data: try JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! }.joined(separator: "\n") + "\n"
                try lines.write(to: url, atomically: true, encoding: .utf8); logs.append(try parser.parse(url: url))
            }
            for (name, expected) in value["expected"] as! [String: [String: Any]] {
                let interval = scopes[name]!.interval(now: now, calendar: scanner.calendar)
                let snap = scanner.snapshot(logs: logs, start: interval.start, end: interval.end)
                func number(_ key: String) -> Int64 { (expected[key] as! NSNumber).int64Value }
                let prefix = file.lastPathComponent + "/" + name
                expect(snap.usage.total == number("total") && snap.usage.cached == number("cached") && snap.usage.reasoning == number("reasoning"), prefix + " shared token subsets")
                expect(snap.tasks.count == Int(number("turns")) && snap.tasks.reduce(0) { $0 + $1.responses } == Int(number("responses")), prefix + " shared turns and response deduplication")
                expect(snap.cost.totalUSD == Decimal(string: expected["usd"] as! String) && snap.cost.pricedTokens == number("priced") && snap.cost.unpricedTokens == number("unpriced"), prefix + " shared exact money and coverage")
                let enriched = LedgerAnalytics.enrich(snap, resolver: ProjectResolver(), titles: [:])
                expect(enriched.projects.reduce(CostEstimate()) { $0 + $1.cost } == snap.cost && enriched.conversations.reduce(CostEstimate()) { $0 + $1.cost } == snap.cost, prefix + " project/chat equality")
            }
            let month = scanner.snapshot(logs: logs, start: DateScope.month.interval(now: now, calendar: scanner.calendar).start, end: DateScope.month.interval(now: now, calendar: scanner.calendar).end)
            let days = scanner.dailyUsage(logs: logs, now: now)
            expect(days.count == 30 && days.reduce(CostEstimate()) { $0 + $1.cost } == month.cost, file.lastPathComponent + " shared monthly daily costs")
            for task in month.tasks {
                let ownDays = scanner.dailyUsage(logs: logs, now: now, taskIDs: [task.id])
                expect(ownDays.reduce(CostEstimate()) { $0 + $1.cost } == task.cost && ownDays.reduce(TokenUsage()) { $0 + $1.usage } == task.usage, "scoped daily usage includes children and excludes other work")
            }
        }
    }
}
