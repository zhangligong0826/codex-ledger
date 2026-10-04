import Foundation

enum LedgerDemo {
    static func activity(empty: Bool = false) -> [DailyUsage] {
        let calendar = Calendar.current, range = DateScope.month.interval(now: Date(), calendar: Calendar.current)
        let tasks = snapshot(empty: empty, scope: .month).tasks
        return (0..<30).map { index in
            let date = calendar.date(byAdding: .day, value: index, to: range.start)!
            let matches = tasks.filter { calendar.startOfDay(for: $0.date) == date }
            return DailyUsage(date: date, usage: matches.reduce(TokenUsage()) { $0 + $1.usage }, responses: matches.reduce(0) { $0 + $1.responses }, cost: LedgerPricing.total(matches))
        }
    }
    static func snapshot(empty: Bool = false, error: Bool = false, scope: DateScope = .today) -> LedgerSnapshot {
        var result = LedgerSnapshot(files: empty ? 0 : 8, warnings: error ? ["没有找到 sessions 或 archived_sessions。请在设置中选择 Codex 数据目录。"] : [])
        guard !empty else { return result }
        let projects = [ProjectIdentity(id: "demo-atlas", name: "Atlas", path: "/Users/demo/Projects/Atlas"), ProjectIdentity(id: "demo-research", name: "Research", path: "/Users/demo/Projects/Research"), .unknown]
        let amounts: [(Int, String, WorkCategory, Int64, String)] = [
            (0, "demo-chat-1", .coding, 3800000, "Build the analytics dashboard"),
            (0, "demo-chat-1", .question, 860000, "Explain the caching strategy"),
            (0, "demo-chat-2", .slides, 2150000, "Create the launch presentation"),
            (1, "demo-chat-1", .research, 920000, "Compare the research results"),
            (1, "demo-chat-3", .document, 1700000, "Write the research summary"),
            (1, "demo-chat-3", .spreadsheet, 740000, "Prepare the experiment data"),
            (0, "demo-chat-4", .image, 530000, "Design the application icon"),
            (2, "demo-chat-5", .background, 16000, "Codex 后台检查")
        ]
        for (index, entry) in amounts.enumerated() {
            let (projectIndex, session, category, total, title) = entry, project = projects[projectIndex]
            var usage = TokenUsage(); usage.input = total - total / 100; usage.cached = total / 2; usage.output = total / 100; usage.reasoning = usage.output / 3
            let now = Date(), elapsed = now.timeIntervalSince(Calendar.current.startOfDay(for: now))
            let date = now.addingTimeInterval(-min(Double(index * 600), elapsed * Double(index) / 8))
            let model = index == 7 ? "demo-unpriced-model" : index % 2 == 0 ? "gpt-6.1-sol" : "gpt-5.5"
            result.tasks.append(LedgerTask(id: "demo-turn-\(index)", sessionID: session, title: title, category: category, reason: "一般问答；可在任务详情中修正", usage: usage, date: date, models: [model], artifacts: [], finished: true, responses: index + 1, subagentResponses: 0, workingDirectory: project.path, projectID: project.id, projectName: project.name, projectPath: project.path, lastActivity: date))
        }
        if scope == .yesterday { result.tasks = [] }
        let historicalDays = scope == .today ? 0 : scope == .yesterday ? 1 : scope == .week ? 6 : 29
        if historicalDays > 0 {
            for day in 1...historicalDays where day % 5 != 0 {
                let date = Calendar.current.date(byAdding: .day, value: -day, to: Calendar.current.startOfDay(for: Date()))!
                var usage = TokenUsage(); usage.input = Int64((day * 17 % 23 + 1) * 180_000)
                usage.output = usage.input / 80; usage.cached = usage.input / 2
                result.tasks.append(LedgerTask(id: "demo-history-\(day)", sessionID: "demo-chat-1", title: "Improve the analytics dashboard", category: .coding, reason: "提示词涉及代码或调试", usage: usage, date: date, models: ["gpt-5.5"], artifacts: [], finished: true, responses: day % 9 + 1, subagentResponses: 0, workingDirectory: projects[0].path, projectID: projects[0].id, projectName: projects[0].name, projectPath: projects[0].path, lastActivity: date))
            }
        }
        for index in result.tasks.indices {
            let task = result.tasks[index]
            // Each fixture represents several responses. Split before pricing too.
            let count = Int64(task.responses)
            var cost = CostEstimate()
            for call in 0..<count {
                var part = TokenUsage()
                func split(_ value: Int64) -> Int64 { value / count + (call < value % count ? 1 : 0) }
                part.input = split(task.usage.input); part.cached = split(task.usage.cached)
                part.output = split(task.usage.output); part.reasoning = split(task.usage.reasoning)
                cost = cost + LedgerPricing.estimate(model: task.models[0], usage: part)
            }
            result.tasks[index].modelUsage = [ModelUsage(model: task.models[0], usage: task.usage, responses: task.responses, taskIDs: [task.id], cost: cost)]
        }
        result.tasks.sort { $0.usage.total > $1.usage.total }
        let titles = ["demo-chat-1": "Analytics architecture", "demo-chat-2": "Launch presentation", "demo-chat-3": "Research report", "demo-chat-4": "Application icon", "demo-chat-5": "Codex 后台检查"]
        result.conversations = LedgerAnalytics.conversations(result.tasks, titles: titles)
        let sets = Dictionary(uniqueKeysWithValues: result.conversations.map { ($0.id, $0.projectIDs) })
        result.projects = projects.map { project in
            let tasks = result.tasks.filter { $0.projectID == project.id }
            return ProjectUsage(identity: project, tasks: tasks, conversations: LedgerAnalytics.conversations(tasks, titles: titles, projectSets: sets))
        }.sorted { $0.usage.total > $1.usage.total }
        result.modelUsage = LedgerAnalytics.models(result.tasks)
        return result
    }
}
