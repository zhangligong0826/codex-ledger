import AppKit
import SwiftUI

@main @MainActor struct NativeLayoutTests {
    static func main() throws {
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        let directory = URL(fileURLWithPath: CommandLine.arguments.first { $0.hasPrefix("--output=") }.map { String($0.dropFirst(9)) } ?? "/private/tmp/ledger-native-layout")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "local.codexledger.layout-" + UUID().uuidString)!
        let store = LedgerStore(defaults: defaults); store.loadDemo()
        var count = 0
        for language in ["en", "zh"] {
            store.language = language; LedgerText.language = language
            for theme in ["system", "light", "dark"] {
                store.appearance = theme
                for page in [LedgerPage.goals, .tasks, .projects, .conversations, .models, .settings] {
                    store.navigate(page)
                    let view = DashboardView(store: store).environment(\.colorScheme, theme == "dark" ? .dark : .light)
                    let controller = NSHostingController(rootView: view); controller.sizingOptions = []
                    let size = NSSize(width: 760, height: 560)
                    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                    window.contentViewController = controller; window.setContentSize(size)
                    controller.view.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.04))
                    precondition(abs(window.contentLayoutRect.width-size.width)<1 && abs(window.contentLayoutRect.height-size.height)<1, "Content must not grow the window")
                    guard let image = ShareImages.capture(controller.view), let png = ShareImages.png(image) else { fatalError("Native layout capture failed") }
                    try png.write(to: directory.appendingPathComponent("\(language)-\(theme)-\(page.rawValue).png")); count += 1
                    window.contentViewController = nil
                }
            }
        }
        store.language = "en"; LedgerText.language = "en"; store.scope = .today
        var goal = LedgerGoal(name: "Synthetic completed goal")
        goal.budgetUSD = 400
        store.goalBook.goals.append(goal)
        store.goalBook.assign(GoalTarget(kind: .conversation, id: store.lifetime.tasks.first!.sessionID), to: goal.id)
        store.goalBook.complete(goal.id, tasks: store.lifetime.tasks, now: Date(), capturedAt: store.lifetime.refreshedAt, coverage: AccountingCoverage(status: .complete))
        store.openGoal(goal.id)
        let goalController = NSHostingController(rootView: DashboardView(store: store)); goalController.sizingOptions = []
        let goalWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
        goalWindow.contentViewController = goalController; goalWindow.setContentSize(NSSize(width: 760, height: 560))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1)); goalController.view.layoutSubtreeIfNeeded()
        try ShareImages.png(ShareImages.capture(goalController.view)!)!.write(to: directory.appendingPathComponent("completed-goal.png"))
        var preview: SharePreview?
        store.presentShare = { preview = $0 }; store.makeShareCard(overview: true)
        let deadline = Date().addingTimeInterval(15)
        while preview == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        guard let preview else { fatalError("Share preview timed out") }
        let controller = NSHostingController(rootView: SharePreviewView(preview: preview, language: "en", close: {})); controller.sizingOptions = []
        let size = NSSize(width: 430, height: 640)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = controller; window.setContentSize(size)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1)); controller.view.layoutSubtreeIfNeeded()
        precondition(controller.view.bounds.height >= 600 && controller.view.bounds.width >= 400, "Share preview must retain visible bounds")
        guard let image = ShareImages.capture(controller.view), let png = ShareImages.png(image) else { fatalError("Preview capture failed") }
        try png.write(to: directory.appendingPathComponent("share-preview.png"))
        print("Native layouts: \(count) localized/theme/page renders at 760x560; window bounds retained")
    }
}
