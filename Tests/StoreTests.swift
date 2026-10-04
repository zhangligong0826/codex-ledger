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
        print("9/9 navigation and scope regression checks passed")
    }
}
