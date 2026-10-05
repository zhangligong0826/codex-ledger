import Foundation
extension CoreTests {
    static func sharedChecks(folder: URL) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Common/Fixtures")
        let fixtureRoot = fixtures.deletingLastPathComponent()
        let v2 = try GoalArchive.decode(Data(contentsOf: fixtureRoot.appendingPathComponent("goal-v2-fixture.json")))
        expect(v2.rules.count == 1 && v2.goals[0].completions[0].turnIDs == ["portable-chat:first"], "v2 portable rule and membership fixture")
        let archive = try GoalArchive.decode(Data(contentsOf: fixtureRoot.appendingPathComponent("goal-backup-fixture.json")))
        expect(archive.goals.first?.completionPriceDate == "2026-10-01" && archive.goals.first?.completionCost?.totalUSD == Decimal(string: "0.151456789") && archive.goals.first?.budgetUSD == Decimal(string: "10.25"), "portable backup preserves exact Decimal, budget and frozen price date")
        if let path = ProcessInfo.processInfo.environment["CODEX_LEDGER_INTEROP_INPUT"] {
            let external = try GoalArchive.decode(Data(contentsOf: URL(fileURLWithPath: path)))
            expect(external.goals.first?.completionCost == archive.goals.first?.completionCost && external.goals.first?.budgetUSD == archive.goals.first?.budgetUSD && external.rules.map(\.id) == v2.rules.map(\.id) && external.goals[0].completions.map(\.cost) == v2.goals[0].completions.map(\.cost) && external.goals[0].completions[0].turnIDs == v2.goals[0].completions[0].turnIDs && abs(external.rules[0].start!.timeIntervalSince(v2.rules[0].start!)) < 0.000001, "C# -> Swift precise backup accepted")
        }
        if let path = ProcessInfo.processInfo.environment["CODEX_LEDGER_SWIFT_BACKUP_OUTPUT"] { try GoalArchive.encode(v2).write(to: URL(fileURLWithPath: path)) }
        let roundtrip = try GoalArchive.decode(GoalArchive.encode(archive))
        expect(roundtrip.bindings == archive.bindings && roundtrip.goals.first?.completionCost == archive.goals.first?.completionCost, "portable backup roundtrip")
        try GoalArchive.encode(archive).write(to: folder.appendingPathComponent("swift-goal-backup.json"))
        expect(GoalBudget.parse("0.001") == Decimal(string: "0.001") && GoalBudget.parse("-1") == nil && GoalBudget.parse("NaN") == nil, "budget decimal validation")
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
                if let complete = value["complete"] as? Bool { expect(snap.isComplete == complete, "mixed-format integrity is shared across platforms") }
                let prefix = file.lastPathComponent + "/" + name
                expect(snap.usage.total == number("total") && snap.usage.cached == number("cached") && snap.usage.reasoning == number("reasoning"), prefix + " shared token subsets")
                expect(snap.tasks.count == Int(number("turns")) && snap.tasks.reduce(0) { $0 + $1.responses } == Int(number("responses")), prefix + " shared turns and response deduplication")
                expect(snap.cost.totalUSD == Decimal(string: expected["usd"] as! String) && snap.cost.pricedTokens == number("priced") && snap.cost.unpricedTokens == number("unpriced"), prefix + " shared exact money and coverage")
                let enriched = LedgerAnalytics.enrich(snap, resolver: ProjectResolver(), titles: [:])
                expect(enriched.projects.reduce(CostEstimate()) { $0 + $1.cost } == snap.cost && enriched.conversations.reduce(CostEstimate()) { $0 + $1.cost } == snap.cost, prefix + " project/chat equality")
            }
            if value["complete"] as? Bool == false {
                let next = DateScope.today.interval(now: now.addingTimeInterval(86400), calendar: scanner.calendar)
                let unaffected = scanner.snapshot(logs: logs, start: next.start, end: next.end)
                let lifetime = scanner.snapshot(logs: logs, start: .distantPast, end: next.end)
                expect(unaffected.isComplete && unaffected.logIssues.isEmpty, "shared historical conflicts exclude unrelated days")
                expect(!lifetime.isComplete && !lifetime.logIssues.isEmpty && !lifetime.hasReadFailures, "shared historical conflicts remain disclosed as accounting issues")
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
