import Foundation
import CryptoKit

@main struct CoreTests {
    static var failures = 0
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { failures += 1; print("FAIL: " + message) }
    }
    static func line(_ type: String, _ payload: [String: Any], _ timestamp: String = "2026-10-03T23:59:00Z") -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["type": type, "payload": payload, "timestamp": timestamp])
        return String(data: data, encoding: .utf8)! + "\n"
    }
    static func usage(_ input: Int, _ output: Int, cached: Int = 0, reasoning: Int = 0) -> [String: Any] {
        ["input_tokens": input, "output_tokens": output, "cached_input_tokens": cached, "reasoning_output_tokens": reasoning, "total_tokens": input + output]
    }
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CodexLedger-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let parser = LogParser()
        let midnight = parser.date("2026-10-04T00:00:00Z")!
        let timezone = TimeZone(secondsFromGMT: 0)!
        let scanner = LedgerScanner(timezone: timezone)
        let nextDay = midnight.addingTimeInterval(86400)
        let meta = line("session_meta", ["id": "session-a", "source": "vscode"])
        let start = line("event_msg", ["type": "task_started", "turn_id": "turn-a", "root_turn_id": "turn-a"])
        let prompt = line("response_item", ["type": "message", "role": "user", "content": [["type": "input_text", "text": "帮我制作一个 PPT"]]])
        let context = line("turn_context", ["turn_id": "turn-a", "model": "model-test"])
        func response(_ id: String, _ input: Int, _ output: Int, _ timestamp: String, owner: String = "session-a") -> String {
            line("token_usage_record", ["thread_id": owner, "turn_id": "turn-a", "root_turn_id": "turn-a", "response_id": id, "usage": usage(input, output, cached: input / 2, reasoning: output / 2)], timestamp)
        }
        let legacy = line("event_msg", ["type": "token_count", "info": ["total_token_usage": usage(300, 30)]], "2026-10-04T00:01:00Z")
        let modern = meta + start + prompt + context + response("r1", 100, 10, "2026-10-03T23:59:00Z") + response("r2", 200, 20, "2026-10-04T00:01:00Z") + response("r2", 200, 20, "2026-10-04T00:01:00Z") + legacy + response("inherited", 9000, 900, "2026-10-04T00:02:00Z", owner: "parent-session")
        let file = folder.appendingPathComponent("modern.jsonl")
        try modern.write(to: file, atomically: true, encoding: .utf8)
        let parsed = try parser.parse(url: file)
        expect(parsed.samples.count == 2, "prefer response records; deduplicate response id; ignore inherited thread")
        expect(parsed.samples.reduce(TokenUsage()) { $0 + $1.usage }.total == 330, "cache/reasoning tokens are subsets, not additional tokens")
        let today = scanner.snapshot(logs: [parsed, parsed], start: midnight, end: nextDay)
        expect(today.usage.total == 220, "date attribution and duplicate-file deduplication")
        expect(today.usage.cached == 100 && today.usage.reasoning == 10, "retain subset details")
        expect(today.tasks.first?.category == .slides, "artifact request classification")
        let yesterday = scanner.snapshot(logs: [parsed], start: midnight.addingTimeInterval(-86400), end: midnight)
        expect(yesterday.usage.total == 110, "cross-midnight task splits by response time")
        expect(today.tasks.first?.models == ["model-test"], "per-turn model attribution")
        expect(today.tasks.first?.finished == false, "running turn is not marked completed")
        let corrected = scanner.snapshot(logs: [parsed], start: midnight, end: nextDay, overrides: ["session-a:turn-a": "coding"])
        expect(corrected.tasks.first?.category == .coding && corrected.usage.total == 220, "manual correction preserves accounting")

        let legacyFile = folder.appendingPathComponent("legacy.jsonl")
        func count(_ input: Int, _ output: Int, _ time: String) -> String { line("event_msg", ["type": "token_count", "info": ["total_token_usage": usage(input, output)]], time) }
        let oldText = meta + start + prompt + context + count(100, 10, "2026-10-03T23:58:00Z") + count(200, 20, "2026-10-04T00:01:00Z") + count(200, 20, "2026-10-04T00:02:00Z") + count(50, 5, "2026-10-04T00:03:00Z")
        try oldText.write(to: legacyFile, atomically: true, encoding: .utf8)
        let old = try parser.parse(url: legacyFile, cutoff: midnight)
        expect(old.samples.count == 2, "legacy repeated cumulative counters are skipped")
        expect(old.samples.reduce(TokenUsage()) { $0 + $1.usage }.total == 165, "legacy midnight baseline and counter reset")

        let agentFile = folder.appendingPathComponent("agent.jsonl")
        let child = line("session_meta", ["id": "child", "source": ["subagent": ["other": "worker"]], "parent_thread_id": "session-a"]) + line("event_msg", ["type": "task_started", "turn_id": "child-turn", "root_turn_id": "turn-a"], "2026-10-04T00:02:00Z") + line("token_usage_record", ["thread_id": "child", "turn_id": "child-turn", "root_turn_id": "turn-a", "response_id": "r-child", "usage": usage(50, 5)], "2026-10-04T00:02:00Z")
        try child.write(to: agentFile, atomically: true, encoding: .utf8)
        let childLog = try parser.parse(url: agentFile)
        let combined = scanner.snapshot(logs: [parsed, childLog], start: midnight, end: nextDay)
        expect(combined.tasks.count == 1 && combined.usage.total == 275, "subagent response joins the matching root task")
        expect(combined.tasks.first?.subagentResponses == 1, "subagent attribution remains visible")
        let alone = scanner.snapshot(logs: [childLog], start: midnight, end: nextDay)
        expect(alone.tasks.first?.category == .background, "unmatched internal work has explicit category")

        expect(TaskClassifier.classify(prompt: "有什么工具可以制作 ppt 和 Word？有现成的吗？").0 == .question, "discussing PPT/Word is a question, not completed production")
        expect(TaskClassifier.classify(prompt: "好的，帮我设计并且完成，我需要一个 mac应用").0 == .coding, "explicit macOS build is coding")
        expect(TaskClassifier.classify(prompt: "继续", inherited: .document).0 == .document, "continuation inherits prior type")
        expect(TaskClassifier.classify(prompt: "帮我制作 PPT 和 Word").0 == .mixed, "multi-output task is mixed")
        expect(TaskClassifier.classify(prompt: "", artifacts: ["/tmp/test.docx"]).0 == .document, "document artifact evidence")
        expect(TaskClassifier.cleanPrompt("<environment_context>code</environment_context>你好") == "你好", "client metadata does not classify as human work")
        expect(TaskClassifier.classify(prompt: "").0 == .unknown, "missing prompt is unknown")
        expect(TaskClassifier.classify(prompt: "给我举真实详细例子", artifacts: ["/tmp/referenced.csv"]).0 == .question, "referenced datasets cannot override explanation intent")
        expect(TaskClassifier.classify(prompt: "如何代码生成，怎么样生成。公开数据库是否有真实案例？").0 == .question, "questions about code generation remain questions")
        expect(TaskClassifier.cleanPrompt("# Selected text:\n论文中的代码\n## My request:\n为什么需要6个窗口") == "为什么需要6个窗口", "selected-document wrapper is removed")
        expect(TaskClassifier.cleanPrompt("<heartbeat><instructions>总结工作</instructions></heartbeat>") == "定时任务：总结工作", "scheduled task gets a readable title")
        expect(LedgerCSV.field("a,\"b\"\n中文") == "\"a,\"\"b\"\"\n中文\"", "CSV quotes commas, newlines and quotes")
        expect(LedgerCSV.field("=SUM(A1)") == "\"'=SUM(A1)\"", "CSV neutralizes formula-like titles")
        expect(LedgerCSV.render(today.tasks).hasPrefix("\u{feff}时间,任务"), "CSV has UTF-8 BOM for Chinese Excel")
        expect(LedgerCSV.render(today.tasks).contains("\"220\""), "CSV export carries real task total")
        expect(TaskClassifier.classify(prompt: "根据讨论内容设计一页ppt").0 == .slides, "designing a PPT is production")
        expect(TaskClassifier.classify(prompt: "根据研究进展帮我设计下周工作，精读两篇文章并做实验", artifacts: ["/tmp/plan.docx"]).0 == .research, "research planning is not document production from incidental file")
        expect(TaskClassifier.cleanPrompt("\n# Selected text:\n代码\n## My request:\n为什么") == "为什么", "leading whitespace in editor wrapper")
        expect(TaskClassifier.cleanPrompt("# Response annotations:\n<response-annotations>\n[{\"text\":\"研究\",\"annotation\":\"解释一下\"}]\n</response-annotations>\n## My request:\n") == "解释一下", "annotation comment becomes human request")
        expect(TaskClassifier.classify(prompt: "给我做个PPT", artifacts: ["/tmp/irrelevant.docx", "/tmp/slide.pptx"]).0 == .slides, "unrelated files do not override explicit PPT request")
        expect(!TaskClassifier.associatedFile("/Users/test/.codex/plugins/skill/SKILL.md"), "plugin instructions are not associated work files")
        expect(!TaskClassifier.associatedFile("/Users/test/Documents/Codex/project/work/reference.jpg"), "app development scratch reference is excluded")
        expect(TaskClassifier.associatedFile("/Users/test/Documents/Codex/project/outputs/Report.pptx"), "delivered user file is retained")

        let partialFile = folder.appendingPathComponent("partial.jsonl")
        let conflictFile = folder.appendingPathComponent("conflict.jsonl")
        try (meta + start + context + response("conflict-r", 100, 10, "2026-10-03T23:59:00Z") + count(50, 5, "2026-10-03T23:59:01Z")).write(to: conflictFile, atomically: true, encoding: .utf8)
        let conflict = try parser.parse(url: conflictFile)
        let affected = scanner.snapshot(logs: [conflict], start: midnight.addingTimeInterval(-86400), end: midnight)
        let unaffected = scanner.snapshot(logs: [conflict], start: midnight, end: nextDay)
        expect(!affected.isComplete && affected.logIssues.count == 1 && !affected.hasReadFailures, "counter conflicts disclose the affected log without claiming a read failure")
        expect(affected.warningSummary == "用量记录存在异常，点击查看详情" && affected.usage.total == 110, "conflicts preserve modern usage without adding a smaller counter twice")
        expect(unaffected.isComplete && unaffected.logIssues.isEmpty, "historical accounting conflicts do not taint an unrelated date range")
        var undated = conflict; undated.integrityDates = nil
        expect(!scanner.snapshot(logs: [undated], start: midnight, end: nextDay).isComplete, "unknown issue dates remain conservative")
        let unreadable = scanner.snapshot(logs: [], start: midnight, end: nextDay, warnings: ["读取失败"])
        expect(unreadable.hasReadFailures && unreadable.warningSummary == "部分日志无法读取，点击查看详情" && !unreadable.isComplete, "actual read failures keep an actionable distinct warning")
        let warningRoot = folder.appendingPathComponent("warning-source")
        let warningSessions = warningRoot.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: warningSessions, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: conflictFile, to: warningSessions.appendingPathComponent("conflict.jsonl"))
        try FileManager.default.copyItem(at: file, to: warningSessions.appendingPathComponent("clean.jsonl"))
        let warningIndex = folder.appendingPathComponent("warning-index")
        _ = LedgerScanner(timezone: timezone, cacheDirectory: warningIndex).scan(root: warningRoot, now: midnight, days: nil)
        for case let url as URL in FileManager.default.enumerator(at: warningIndex, includingPropertiesForKeys: nil)! where url.pathExtension == "plist" {
            var entry = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as! [String: Any]
            var payload = try PropertyListSerialization.propertyList(from: entry["payload"] as! Data, format: nil) as! [String: Any]
            payload.removeValue(forKey: "integrityDates")
            let bytes = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
            entry["payload"] = bytes
            entry["digest"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            try PropertyListSerialization.data(fromPropertyList: entry, format: .binary, options: 0).write(to: url)
        }
        let migrated = LedgerScanner(timezone: timezone, cacheDirectory: warningIndex)
        let migratedLogs = migrated.scan(root: warningRoot, now: midnight, days: nil).logs
        expect(migrated.parsedFileCount == 1 && migrated.diskCacheHits == 1, "old warning entries are reparsed while clean cached logs remain reusable")
        expect(migrated.snapshot(logs: migratedLogs, start: midnight, end: nextDay).isComplete && migrated.snapshot(logs: migratedLogs, start: .distantPast, end: nextDay).logIssues.count == 1, "cache migration restores dated completeness without hiding historical conflicts")
        try (modern + "{\"timestamp\":").write(to: partialFile, atomically: true, encoding: .utf8)
        let partial = try parser.parse(url: partialFile)
        expect(partial.samples.count == 2 && partial.malformed == 0, "trailing partial write is ignored until next scan")
        let badFile = folder.appendingPathComponent("bad-line.jsonl")
        try (modern + "{bad}\n").write(to: badFile, atomically: true, encoding: .utf8)
        let badLog = try parser.parse(url: badFile)
        expect(badLog.malformed == 1 && !scanner.snapshot(logs: [badLog], start: midnight, end: nextDay).isComplete, "complete corrupt lines are surfaced as incomplete accounting")
        let emptyFolder = folder.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)
        let missing = scanner.scan(root: emptyFolder)
        expect(!missing.warnings.isEmpty, "missing source has actionable warning")
        expect(TaskClassifier.cleanPrompt("# Files mentioned by the user:\nimage.png\n## My request:\n太大了") == "太大了", "attachment wrapper does not become the task title")
        expect(TaskClassifier.cleanPrompt("缩小面板\n<image name=example path=file.png>\n</image>") == "缩小面板", "image attachment markup is removed from titles")
        var multiModel = parsed
        multiModel.samples[0].model = "model-a"; multiModel.samples[1].model = "model-b"
        let multi = scanner.snapshot(logs: [multiModel, multiModel], start: .distantPast, end: nextDay)
        expect(multi.modelUsage.count == 2, "two models within one task stay separate")
        expect(multi.modelUsage.reduce(TokenUsage()) { $0 + $1.usage } == multi.usage, "model totals equal task totals including deduplication")
        expect(multi.modelUsage.first(where: { $0.model == "model-a" })?.usage.total == 110, "per-model tokens attributed by response")
        expect(multi.modelUsage.allSatisfy { $0.responses == 1 && $0.taskIDs.count == 1 }, "model response counts and unique tasks")
        expect(combined.modelUsage.reduce(TokenUsage()) { $0 + $1.usage } == combined.usage, "subagent model usage preserves parent accounting")
        let historyRoot = folder.appendingPathComponent("history")
        let sessions = historyRoot.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let recentFile = sessions.appendingPathComponent("recent.jsonl")
        try (modern + response("r-month", 20, 2, "2026-09-15T12:00:00Z")).write(to: recentFile, atomically: true, encoding: .utf8)
        let historicalFile = sessions.appendingPathComponent("historical.jsonl")
        try (meta + start + context + response("r-history", 70, 7, "2026-08-01T12:00:00Z")).write(to: historicalFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: parser.date("2026-08-02T12:00:00Z")!], ofItemAtPath: historicalFile.path)
        let historyScanner = LedgerScanner(timezone: timezone)
        let weekLogs = historyScanner.scan(root: historyRoot, now: midnight, days: 7)
        expect(weekLogs.logs.count == 1 && weekLogs.logs[0].samples.count == 2, "week scan excludes old files and old responses")
        let monthLogs = historyScanner.scan(root: historyRoot, now: midnight, days: 30)
        expect(monthLogs.logs.count == 1 && monthLogs.logs[0].samples.count == 3 && historyScanner.parsedFileCount == 0, "expanding range retains older responses without reparsing")
        var complete = 0, totalFiles = 0
        let allLogs = historyScanner.scan(root: historyRoot, now: midnight, days: nil) { complete = $0; totalFiles = $1 }
        expect(allLogs.logs.count == 2, "all-time scan includes files older than 30 days")
        expect(complete == 2 && totalFiles == 2, "scan progress reports completion")
        let lifetime = historyScanner.snapshot(logs: allLogs.logs, start: .distantPast, end: nextDay)
        expect(lifetime.usage.total == 429, "all-time accounting includes historical responses")
        let index = folder.appendingPathComponent("private-cache")
        let cold = LedgerScanner(timezone: timezone, cacheDirectory: index)
        let cachedMonth = cold.scan(root: historyRoot, now: midnight, days: 30)
        let warm = LedgerScanner(timezone: timezone, cacheDirectory: index)
        _ = warm.scan(root: historyRoot, now: midnight, days: nil)
        expect(cold.parsedFileCount == 1 && warm.diskCacheHits == 1 && warm.parsedFileCount == 1, "a new process reuses complete cached files across ranges")
        let restored = LedgerScanner(timezone: timezone, cacheDirectory: index)
        let restoredAll = restored.scan(root: historyRoot, now: midnight, days: nil)
        let restoredSnapshot = restored.snapshot(logs: restoredAll.logs, start: .distantPast, end: nextDay)
        expect(restored.diskCacheHits == 2 && restored.parsedFileCount == 0 && restoredSnapshot.usage == lifetime.usage && restoredSnapshot.cost == lifetime.cost, "disk restoration preserves exact token subsets and Decimal amounts")
        expect(restored.dailyUsage(logs: restoredAll.logs, now: midnight).reduce(TokenUsage()) { $0 + $1.usage } == cold.dailyUsage(logs: cachedMonth.logs, now: midnight).reduce(TokenUsage()) { $0 + $1.usage }, "cache restoration preserves the heatmap scope")
        let noChange = restored.scan(root: historyRoot, now: midnight, days: nil)
        expect(noChange.revision == restoredAll.revision && restored.memoryCacheHits == 2 && restored.parsedFileCount == 0, "unchanged scans keep their revision and never parse logs")
        try (modern + response("r-month", 20, 2, "2026-09-15T12:00:00Z") + response("r-extra", 44, 4, "2026-10-04T12:00:00Z")).write(to: recentFile, atomically: true, encoding: .utf8)
        let changed = restored.scan(root: historyRoot, now: midnight, days: nil)
        expect(changed.revision != noChange.revision && restored.parsedFileCount == 1 && restored.memoryCacheHits == 1 && restored.snapshot(logs: changed.logs, start: .distantPast, end: nextDay).usage.total == 477, "only a changed file is parsed and its new response is included")
        try FileManager.default.removeItem(at: historicalFile)
        let deleted = restored.scan(root: historyRoot, now: midnight, days: nil)
        expect(deleted.logs.count == 1 && restored.snapshot(logs: deleted.logs, start: .distantPast, end: nextDay).usage.total == 400, "a deleted source cannot reappear from a disk cache")
        let cacheFiles = (FileManager.default.enumerator(at: index, includingPropertiesForKeys: nil)!.allObjects as! [URL]).filter { $0.pathExtension == "plist" }
        expect(cacheFiles.allSatisfy { ((try? FileManager.default.attributesOfItem(atPath: $0.path)[.posixPermissions]) as? NSNumber)?.intValue == 0o600 }, "private cache files have owner-only permissions")
        for url in cacheFiles { try Data("broken index".utf8).write(to: url) }
        let broken = LedgerScanner(timezone: timezone, cacheDirectory: index)
        let rebuilt = broken.scan(root: historyRoot, now: midnight, days: nil)
        expect(broken.parsedFileCount == 1 && broken.diskCacheHits == 0 && broken.snapshot(logs: rebuilt.logs, start: .distantPast, end: nextDay).usage.total == 400 && rebuilt.warnings.isEmpty, "a corrupt disposable index is rebuilt instead of displaying zero")
        let existingCache = (FileManager.default.enumerator(at: index, includingPropertiesForKeys: nil)!.allObjects as! [URL]).filter { $0.pathExtension == "plist" }
        for url in existingCache {
            guard var value = try? PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any] else { continue }
            value["version"] = 999
            try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0).write(to: url)
        }
        let incompatible = LedgerScanner(timezone: timezone, cacheDirectory: index)
        _ = incompatible.scan(root: historyRoot, now: midnight, days: nil)
        expect(incompatible.parsedFileCount == 1 && incompatible.diskCacheHits == 0, "an incompatible parser cache cannot be reused")
        let cannotWrite = folder.appendingPathComponent("cache-is-a-file")
        try Data().write(to: cannotWrite)
        let fallback = LedgerScanner(timezone: timezone, cacheDirectory: cannotWrite).scan(root: historyRoot, now: midnight, days: nil)
        expect(fallback.logs.count == 1 && fallback.warnings.isEmpty, "cache write failures never prevent reading source usage")
        let otherSource = broken.scan(root: emptyFolder, now: midnight, days: nil)
        expect(otherSource.logs.isEmpty && !otherSource.warnings.isEmpty, "switching sources cannot inherit a previous source's cache")
        var utcCalendar = Calendar(identifier: .gregorian); utcCalendar.timeZone = timezone
        let monthRange = DateScope.month.interval(now: midnight, calendar: utcCalendar)
        expect(monthRange.start == parser.date("2026-09-05T00:00:00Z")! && monthRange.end == nextDay, "30-day range includes today and preceding 29 days")
        expect(DateScope.history.interval(now: midnight, calendar: utcCalendar).start == .distantPast, "history has no artificial start cutoff")
        LedgerText.language = "en"
        expect(L("近 30 天") == "Last 30 days" && L("模型用量") == "Model usage", "English date and model labels")
        expect(L("10 个任务") == "10 tasks" && L("正在扫描 20/100 份日志") == "Scanning 20/100 logs", "English dynamic counts and progress")
        expect(L("1 个任务") == "1 task" && L("1 次响应") == "1 response", "English singular count grammar")
        expect(L("陌生用户原文") == "陌生用户原文", "unknown text is not rewritten")
        expect(LedgerCSV.render(multi.tasks, translate: L).contains("Presentations"), "task CSV uses selected language for categories")
        let modelCSV = LedgerCSV.renderModels(multi.modelUsage, translate: L)
        expect(modelCSV.hasPrefix("\u{feff}Models,Responses,Task turns") && modelCSV.contains("model-a"), "model CSV exports named model usage")
        LedgerText.language = "zh"
        expect(L("近 30 天") == "近 30 天" && L("10 个任务") == "10 个任务", "Chinese language restores static and dynamic labels")
        try analyticsChecks(folder: folder)
        try pricingChecks(folder: folder)
        try activityChecks(folder: folder)
        expect(LedgerCSV.field("-25.00") == "\"-25.00\"", "negative budget differences remain numeric and formulas remain escaped")
        try sharedChecks(folder: folder)
        print("\(checks - failures)/\(checks) accounting and classification checks passed")
        if failures > 0 { exit(1) }
    }
}
