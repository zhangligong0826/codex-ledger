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
        print("Native layouts: \(count) localized/theme/page renders at 760x560; window bounds retained")
    }
}
