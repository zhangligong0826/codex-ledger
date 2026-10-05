import Foundation

@main @MainActor struct StoreTests {
    static func main() {
        let store = LedgerStore(), demo = LedgerDemo.snapshot()
        store.snapshot = demo
        let atlas = demo.projects.first { $0.name == "Atlas" }!
        let chat = atlas.conversations.first { $0.id == "demo-chat-1" }!
        store.openProject(atlas); store.openConversation(chat)
        precondition(store.contextUsage.total == 4_660_000, "project chat must show its own share")
        store.back()
        precondition(store.selectedProjectID == atlas.id && store.selectedConversationID == nil, "back retains project context")
        store.back(); store.navigate(.conversations); store.openConversation(demo.conversations.first { $0.id == chat.id }!)
        precondition(store.contextUsage.total == 5_580_000, "global chat includes all projects")
        store.openProject(atlas); store.openConversation(chat)
        var nextRange = demo
        nextRange.tasks = demo.tasks.filter { $0.projectName == "Research" }
        nextRange.projects = demo.projects.filter { $0.name == "Research" }
        nextRange.conversations = LedgerAnalytics.conversations(nextRange.tasks, titles: [:])
        store.snapshot = nextRange
        precondition(store.project == nil && store.conversation == nil && store.contextUsage.total == 0, "a disappearing project cannot fall back to global chat tokens")
        store.back()
        precondition(store.filteredConversations.isEmpty, "a disappearing project keeps its empty scope")
        store.back(); store.navigate(.conversations); store.search = "/Projects/Research"
        precondition(store.filteredConversations.count == 2, "conversation search includes project paths")
        store.search = "no-match"
        precondition(store.filteredConversations.isEmpty)
        store.clearFilters()
        precondition(store.filteredConversations.count == 2)
        store.navigate(.projects); store.search = "no-match"; store.navigate(.models)
        precondition(store.search.isEmpty && store.selectedProjectID == nil && store.selectedConversationID == nil)
        store.loadDemo()
        precondition(store.activityReady && store.activity.count == 30, "activity is independently ready with a full month")
        store.snapshot = LedgerSnapshot(warnings: ["Fixture read error"])
        store.activity = LedgerDemo.activity(empty: true)
        precondition(store.dataUnavailable, "failed data must not be presented as known zero usage")
        store.snapshot = LedgerSnapshot()
        precondition(!store.dataUnavailable, "a valid empty source remains known zero usage")
        store.loadDemo(); store.overviewScope = .history; store.scope = .today
        store.openOverviewRecords(category: .coding)
        precondition(store.scope == .history && store.categoryFilter == .coding, "ring navigation retains overview dates")
        store.navigate(.models)
        var turn = store.snapshot.tasks.first!
        let original = turn.samples.first!
        var extra = original; extra.id = "other-model-sample"; extra.model = "unrelated-synthetic-model"
        turn.samples.append(extra); turn.usage = turn.usage + extra.usage
        turn.modelUsage.append(ModelUsage(model: extra.model, usage: extra.usage, responses: 1, taskIDs: [turn.id]))
        store.snapshot.tasks = [turn]; store.search = original.model
        store.selectedDay = Calendar.current.startOfDay(for: original.date)
        let expected = turn.samples.filter { $0.model.contains(original.model) && Calendar.current.isDate($0.date, inSameDayAs: original.date) }.reduce(TokenUsage()) { $0 + $1.usage }
        precondition(store.contextUsage == expected && !store.selectedTasks.flatMap(\.samples).contains { $0.model == extra.model }, "daily model search cannot reintroduce other model samples")
        print("14/14 navigation, scope and activity-state regression checks passed")
    }
}
