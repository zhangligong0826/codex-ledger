import AppKit
import SwiftUI
import Vision

@main @MainActor struct ShareRenderTests {
    static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments.first { $0.hasPrefix("--output=") }.map { String($0.dropFirst(9)) } ?? "/private/tmp/ledger-share-previews")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = LedgerStore(); store.language = "en"; LedgerText.language = "en"; store.loadDemo()
        let project = store.snapshot.projects.first { $0.name == "Atlas" }!
        store.openProject(project); store.scope = .month
        var snapshot: ShareSnapshot?
        store.presentShare = { value in snapshot = value.snapshot }
        store.makeShareCard()
        let deadline = Date().addingTimeInterval(15)
        while snapshot == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        guard let value = snapshot else { fatalError("Share generation timed out") }
        precondition(value.usage == store.contextUsage && value.cost == store.contextCost, "Share/project totals must match UI")
        precondition(value.monthlyUsage == value.usage && value.monthlyCost == value.cost, "Same monthly scope must reconcile")
        store.navigate(.tasks); store.scope = .today
        precondition(value.range == L(DateScope.month.rawValue), "Frozen range survives navigation")
        // Public project summaries use the same listed projects as CSV, rather
        // than matching hidden turn titles when the project list is empty.
        store.openProject(project); store.scope = .today
        snapshot = nil; store.makeShareCard()
        let monthDeadline = Date().addingTimeInterval(15)
        while snapshot == nil && Date() < monthDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        precondition(snapshot?.monthlyUsage == value.monthlyUsage, "Project heatmap includes month conversations absent today")
        store.navigate(.projects); store.scope = .month; store.search = "nonexistent-project"
        snapshot = nil; store.makeShareCard()
        let projectDeadline = Date().addingTimeInterval(15)
        while snapshot == nil && Date() < projectDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        precondition(snapshot?.usage.total == 0 && snapshot?.monthlyUsage.total == 0, "Empty project search shares no hidden turns")
        precondition(store.csvExport().0.split(separator: "\n").count == 1, "Empty project CSV has only its header")
        store.clearFilters(); store.openProject(project)
        let chat = store.filteredConversations.first!
        store.openConversation(chat); store.search = "nonexistent-turn"
        snapshot = nil; store.makeShareCard()
        let filteredDeadline = Date().addingTimeInterval(15)
        while snapshot == nil && Date() < filteredDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        precondition(snapshot?.usage.total == 0 && store.csvExport().0.split(separator: "\n").count == 1, "Filtered chat CSV and share agree")
        print("Generating install QR"); fflush(stdout)
        precondition(ShareImages.qr() != nil, "Install QR must be generated")
        print("Install QR generated; rendering card"); fflush(stdout)
        for language in ["en", "zh"] {
            LedgerText.language = language
            for dark in [false, true] {
                guard let image = ShareImages.card(value, title: "", showName: false, language: language, dark: dark),
                      let png = ShareImages.png(image), let rep = NSBitmapImageRep(data: png) else { fatalError("No image") }
                precondition(rep.pixelsWide == 1080 && rep.pixelsHigh == 1440, "Share must have export dimensions")
                let file = directory.appendingPathComponent("share-\(language)-\(dark ? "dark" : "light").png")
                try png.write(to: file)
                print("Rendered \(language)/\(dark ? "dark" : "light") 1080x1440"); fflush(stdout)
                if ProcessInfo.processInfo.environment["CODEX_LEDGER_SKIP_VISION"] == "1" { continue }
                let cg = rep.cgImage!
                let qr = VNDetectBarcodesRequest(); qr.symbologies = [.qr]; qr.usesCPUOnly = true
                let text = VNRecognizeTextRequest(); text.recognitionLevel = .accurate; text.recognitionLanguages = ["en-US", "zh-Hans"]; text.usesCPUOnly = true
                try VNImageRequestHandler(cgImage: cg).perform([qr, text])
                precondition(qr.results?.contains { $0.payloadStringValue == ShareSnapshot.downloadURL } == true, "QR must decode to stable install entry")
                let labels = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                precondition(!labels.contains("Atlas") && !labels.contains("/Projects"), "Default card hides private identity")
                precondition(labels.contains("Codex Ledger"), "Card footer is visible")
                let publicTitle = "A finished goal"
                precondition(ShareImages.card(value, title: publicTitle, showName: false, language: language, dark: dark) != nil)
            }
        }
        print("Share checks passed: frozen scope/amount, 1080x1440, 4 EN/CN light/dark renders; Vision validation " + (ProcessInfo.processInfo.environment["CODEX_LEDGER_SKIP_VISION"] == "1" ? "disabled on GPU-less Intel CI" : "decoded QR and private defaults passed"))
    }
}
