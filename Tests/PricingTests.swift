import Foundation

extension CoreTests {
    static func pricingChecks(folder: URL) throws {
        func cost(_ model: String, _ input: Int, _ output: Int, _ cached: Int = 0, _ reasoning: Int = 0, request: Bool = true) -> CostEstimate {
            LedgerPricing.estimate(model: model, usage: TokenUsage(usage(input, output, cached: cached, reasoning: reasoning)), hasRequestUsage: request)
        }
        func decimal(_ text: String) -> Decimal { Decimal(string: text)! }
        let short = cost("gpt-5.5", 100_000, 5_000, 60_000, 4_000)
        expect(short.inputUSD == decimal("0.2") && short.cachedUSD == decimal("0.03") && short.outputUSD == decimal("0.15"), "input excludes cached tokens and components use official Standard rates")
        expect(short.totalUSD == decimal("0.38"), "reasoning is included in output and never charged twice")
        expect(cost("gpt-5.5", 100_000, 5_000, 60_000).totalUSD == short.totalUSD, "reasoning subset does not affect price")
        expect(cost("gpt-6.1-sol", 100_000, 5_000, 60_000).totalUSD == decimal("0.136"), "Sol cached input uses the verified five-percent rate")
        let long = cost("gpt-5.5", 300_000, 10_000, 200_000)
        expect(long.totalUSD == decimal("1.65"), "long context doubles both input prices and multiplies output by 1.5")
        expect(cost("gpt-5.5", 272_000, 0).totalUSD == decimal("1.36"), "272K boundary remains short context")
        expect(cost("gpt-5.5", 272_001, 0).totalUSD == decimal("2.72001"), "long context starts above 272K")
        expect(cost("gpt-5.3-codex", 300_000, 10_000, 200_000).totalUSD == decimal("0.35"), "Codex model with no published long-context tier keeps its Standard prices")
        expect(cost("gpt-5.5-2026-04-23", 100_000, 5_000, 60_000) == short, "documented model snapshot alias is priced explicitly")
        for name in ["gpt-reserve", "codex-auto-review", "gpt-5.5-future", "gpt-6.1-sol-2099-01-01", "未知模型"] {
            let unknown = cost(name, 100, 10)
            expect(unknown.unpricedTokens == 110 && !unknown.hasEstimate, "undocumented name \(name) is unpriced rather than guessed")
        }
        let legacy = cost("gpt-5.5", 300_000, 10_000, 200_000, request: false)
        expect(legacy.unverifiedContextTokens == 310_000 && legacy.totalUSD == decimal("0.9"), "unverified legacy context uses a marked baseline, not an aggregate long-context tier")
        expect(LedgerPricing.display(CostEstimate()) == "$0.00", "empty usage has a genuine zero estimate")
        expect(LedgerPricing.money(decimal("0.00001")) == "<$0.01", "sub-cent cost is not misleadingly displayed as zero")
        expect(LedgerPricing.csvValues(cost("missing", 100, 10))[0].isEmpty, "unpriced CSV cost is blank rather than zero")
        expect(LedgerPricing.csvValues(short)[0] == "0.38", "CSV retains exact Decimal cost")

        let now = Date(), scanner = LedgerScanner()
        var parent = ParsedLog(path: "parent", size: 0, modified: now, sessionID: "chat")
        parent.turns["a"] = TurnInfo(id: "a", sessionID: "chat", rootTurnID: "a", prompt: "Build a dashboard", start: now, workingDirectory: folder.appendingPathComponent("One").path)
        parent.turns["b"] = TurnInfo(id: "b", sessionID: "chat", rootTurnID: "b", prompt: "Compare results", start: now, workingDirectory: folder.appendingPathComponent("Two").path)
        parent.samples = [
            UsageSample(id: "r1", sessionID: "chat", turnID: "a", rootTurnID: "a", date: now, model: "gpt-5.5", usage: TokenUsage(usage(200_000, 1_000))),
            UsageSample(id: "r2", sessionID: "chat", turnID: "a", rootTurnID: "a", date: now, model: "gpt-5.5", usage: TokenUsage(usage(200_000, 1_000))),
            UsageSample(id: "r3", sessionID: "chat", turnID: "b", rootTurnID: "b", date: now, model: "gpt-6.1-sol", usage: TokenUsage(usage(100_000, 5_000, cached: 60_000))),
            UsageSample(id: "old", sessionID: "chat", turnID: "b", rootTurnID: "b", date: now.addingTimeInterval(-86400), model: "gpt-5.5", usage: TokenUsage(usage(1_000_000, 10)))
        ]
        var child = ParsedLog(path: "child", size: 0, modified: now, sessionID: "agent", parentID: "chat", internalAgent: true)
        child.turns["child"] = TurnInfo(id: "child", sessionID: "agent", rootTurnID: "a", start: now)
        child.samples = [UsageSample(id: "child-r", sessionID: "agent", turnID: "child", rootTurnID: "a", date: now, model: "unpriced-agent", usage: TokenUsage(usage(100, 10)))]
        let raw = scanner.snapshot(logs: [parent, parent, child, child], start: now.addingTimeInterval(-1), end: now.addingTimeInterval(1))
        let snap = LedgerAnalytics.enrich(raw, resolver: ProjectResolver(), titles: [:])
        expect(snap.cost.totalUSD == decimal("2.196"), "two short-context calls stay short after grouping, duplicate records and out-of-range cost are excluded")
        expect(snap.cost.unpricedTokens == 110 && snap.cost.pricedTokens == 507_000, "unpriced child is retained once and attributed to the parent")
        expect(snap.cost.pricedTokens + snap.cost.unpricedTokens == snap.usage.total, "price coverage accounts for every token")
        expect(snap.projects.reduce(CostEstimate()) { $0 + $1.cost } == snap.cost, "project cost totals exactly match task costs")
        expect(snap.conversations.reduce(CostEstimate()) { $0 + $1.cost } == snap.cost, "global conversation cost totals exactly match task costs")
        expect(snap.modelUsage.reduce(CostEstimate()) { $0 + $1.cost } == snap.cost, "model costs retain the same per-response calculation")
        expect(LedgerAnalytics.models(snap.tasks).reduce(CostEstimate()) { $0 + $1.cost } == snap.cost, "scoped model aggregation carries costs without repricing")
        expect(snap.projects.allSatisfy { $0.conversations.reduce(CostEstimate()) { $0 + $1.cost } == $0.cost }, "each project's conversation costs equal that project's cost")
        expect(snap.projects.first?.cost.totalUSD == decimal("2.06"), "project-scoped cross-project conversation keeps only its own response costs")
        expect(LedgerPricing.display(snap.cost).hasSuffix(" *"), "partial estimate is visibly marked")
        for csv in [LedgerCSV.render(snap.tasks), LedgerCSV.renderModels(snap.modelUsage), LedgerCSV.renderProjects(snap.projects), LedgerCSV.renderConversations(snap.conversations)] {
            let rows = csv.components(separatedBy: "\r\n")
            let headers = rows[0].components(separatedBy: ",")
            let index = headers.firstIndex(of: "预估API花费USD")!
            let total = rows.dropFirst().reduce(Decimal.zero) { sum, row in
                let value = row.components(separatedBy: ",")[index].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return sum + (Decimal(string: value) ?? 0)
            }
            expect(total == snap.cost.totalUSD, "CSV exported costs sum to the same exact scoped estimate")
        }

        let file = folder.appendingPathComponent("pricing-legacy.jsonl")
        let text = line("session_meta", ["id": "legacy-cost"]) + line("turn_context", ["turn_id": "t", "model": "gpt-5.5"]) + line("event_msg", ["type": "token_count", "info": ["total_token_usage": usage(300_000, 10_000), "last_token_usage": usage(300_000, 10_000)]])
        try text.write(to: file, atomically: true, encoding: .utf8)
        let parsed = try LogParser().parse(url: file)
        expect(parsed.samples.first?.hasRequestUsage == true && parsed.samples.first?.cost.totalUSD == decimal("3.45"), "legacy last-response usage confirms context only when it matches the cumulative delta")
        let mismatched = text.replacingOccurrences(of: "\"last_token_usage\"", with: "\"unavailable\"")
        try mismatched.write(to: file, atomically: true, encoding: .utf8)
        let unverified = try LogParser().parse(url: file)
        expect(unverified.samples.first?.hasRequestUsage == false, "legacy records without confirmed response usage remain approximate")
        let record = line("session_meta", ["id": "record-model"]) + line("turn_context", ["turn_id": "t", "model": "gpt-reserve"]) + line("token_usage_record", ["thread_id": "record-model", "turn_id": "t", "response_id": "r", "model": "gpt-5.5", "usage": usage(100_000, 5_000, cached: 60_000)])
        try record.write(to: file, atomically: true, encoding: .utf8)
        let recorded = try LogParser().parse(url: file)
        expect(recorded.samples.first?.cost == short, "response's recorded model takes precedence over a fallback turn model")
        LedgerText.language = "en"
        expect(L("预估 API 花费") == "Estimated API cost" && L("单价未知") == "Unpriced", "cost labels support English")
        expect(!L(LedgerPricing.explanation).contains("按已核对"), "full cost basis supports English")
        LedgerText.language = "zh"
    }
}
