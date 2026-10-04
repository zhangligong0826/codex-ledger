import Foundation

enum LedgerDemo {
    static func snapshot(empty: Bool = false, error: Bool = false) -> LedgerSnapshot {
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
            let date = Date().addingTimeInterval(Double(-index * 600))
            result.tasks.append(LedgerTask(id: "demo-turn-\(index)", sessionID: session, title: title, category: category, reason: "一般问答；可在任务详情中修正", usage: usage, date: date, models: [index % 2 == 0 ? "model-alpha" : "model-beta"], artifacts: [], finished: true, responses: index + 1, subagentResponses: 0, workingDirectory: project.path, projectID: project.id, projectName: project.name, projectPath: project.path, lastActivity: date))
        }
        for index in result.tasks.indices {
            let task = result.tasks[index]
            result.tasks[index].modelUsage = [ModelUsage(model: task.models[0], usage: task.usage, responses: task.responses, taskIDs: [task.id])]
        }
        result.tasks.sort { $0.usage.total > $1.usage.total }
        let titles = ["demo-chat-1": "Analytics architecture", "demo-chat-2": "Launch presentation", "demo-chat-3": "Research report", "demo-chat-4": "Application icon", "demo-chat-5": "Codex 后台检查"]
        result.conversations = LedgerAnalytics.conversations(result.tasks, titles: titles)
        let sets = Dictionary(uniqueKeysWithValues: result.conversations.map { ($0.id, $0.projectIDs) })
        result.projects = projects.map { project in
            let tasks = result.tasks.filter { $0.projectID == project.id }
            return ProjectUsage(identity: project, tasks: tasks, conversations: LedgerAnalytics.conversations(tasks, titles: titles, projectSets: sets))
        }.sorted { $0.usage.total > $1.usage.total }
        result.modelUsage = ["model-alpha", "model-beta"].map { name in
            let tasks = result.tasks.filter { $0.models.contains(name) }
            return ModelUsage(model: name, usage: tasks.reduce(TokenUsage()) { $0 + $1.usage }, responses: tasks.reduce(0) { $0 + $1.responses }, taskIDs: Set(tasks.map(\.id)))
        }
        return result
    }
}
