import Foundation

// UI translation only. User-authored task titles and file names remain verbatim.
enum LedgerText {
    static var language = "en"
    static let english: [String: String] = [
        "项目": "Projects", "对话": "Conversations", "未识别项目": "Unidentified project", "缺少工作目录": "Working directory unavailable",
        "查看项目与对话": "View projects & conversations", "项目中的对话": "Conversations in this project", "返回": "Back",
        "仅当前项目": "This project only", "整个对话": "Entire conversation", "涉及多个项目": "Multiple projects", "最近活动": "Last active",
        "搜索项目、对话或模型": "Search projects, chats or models", "正在汇总用量…": "Summarizing usage…", "不上传聊天内容": "No chats uploaded",
        "项目路径": "Project path", "对话数": "Conversations", "统计范围": "Usage scope", "是": "Yes", "否": "No",
        "用途与模型": "Work categories & models", "工作目录": "Working directory", "导出轮次 CSV": "Export turns CSV",
        "项目按工作目录或 Git 仓库分组。对话标题只读本机元数据，缺失时使用用户请求。": "Projects follow working directories or Git repositories. Conversation titles come from local metadata, with user requests as a fallback.",
        "总 token = 输入 + 输出。缓存和推理分别是输入、输出的子集。日期按模型调用时间统计。项目内的对话只显示归属该项目的消耗；全局对话显示所选日期内的完整消耗。只覆盖本机可读日志，不代表订阅额度或账单。": "Total tokens = input + output. Cache and reasoning are subsets of input and output. Dates follow model call timestamps. Project conversations show only that project's usage; global conversations include all usage in the selected date range. Only readable local logs are covered, not subscription limits or billing.",
        "只读本机日志及对话索引，不联网、不调用模型、不读取登录凭证。CSV 仅在你选择导出时保存。": "Reads local logs and conversation metadata only. No network, model calls, or access to login credentials. CSV files are saved only when you export them.",
        "今天": "Today", "昨天": "Yesterday", "近 7 天": "Last 7 days", "近 30 天": "Last 30 days", "历史累计": "All time",
        "问答与学习": "Questions & learning", "研究与分析": "Research & analysis", "PPT 制作": "Presentations", "Word 与写作": "Documents & writing",
        "表格与数据": "Spreadsheets & data", "编程与调试": "Coding & debugging", "图片与设计": "Images & design", "混合任务": "Mixed work", "后台检查": "Background checks", "未分类": "Unclassified",
        "未知模型": "Unknown model", "Codex 后台检查": "Codex background check", "未记录用户请求": "User request unavailable",
        "把 token 对应到每一份工作": "See what your tokens worked on", "用量总览": "Usage overview", "本机 Codex 日志 · 输入 + 输出（包含缓存）": "Local Codex logs · input + output, including cached input",
        "导出 CSV": "Export CSV", "导出 CSV…": "Export CSV…", "时间": "Time range", "其他用途": "Other work", "正在整理日志…": "Reading logs…", "暂时没有用量记录": "No usage recorded yet",
        "任务用途": "Work categories", "本机": "Local", "首次扫描约需数秒": "Reading local logs…", "这个日期范围内暂无记录": "No records in this date range", "需要检查数据目录": "Check the data folder",
        "Codex 写入用量日志后会自动更新。": "Updates automatically when Codex records new usage.", "查看全部任务": "View all tasks", "部分日志不可读，账本内可查看详情": "Some logs could not be read. See the ledger for details.",
        "正在更新…": "Updating…", "立即刷新（⌘R）": "Refresh now (⌘R)", "选项": "Options", "打开工作账本": "Open work ledger", "设置…": "Settings…", "退出 Codex Ledger": "Quit Codex Ledger",
        "设置": "Settings", "你的工作，用量可见": "Your work, measured", "本地运行，按你的习惯记录。": "Local data. Your preferences.", "刷新": "Refresh", "总 token": "Total tokens", "输入 + 输出 · 含缓存": "Input + output · includes cache",
        "任务轮次": "Task turns", "关联文件": "Linked files", "已存在的本地文件": "Existing local files", "输入": "Input", "其中缓存": "Cached input", "输出": "Output", "其中推理": "Reasoning output",
        "全部任务": "All tasks", "按 token 消耗排序": "Sorted by token usage", "搜索任务或模型": "Search tasks or models", "正在整理日志，请稍候": "Reading logs, please wait", "这个范围内没有匹配的任务": "No matching tasks",
        "可以切换日期、清除筛选，或在设置中检查数据目录。": "Change the date range, clear filters, or check the data folder in Settings.", "知道了": "OK", "全部工作": "All work", "TOKEN 用在哪里": "WHERE TOKENS WENT",
        "仅在这台 Mac 上统计": "Measured on this Mac only", "v1.0 · 不上传聊天内容": "v1.0 · No chats uploaded", "数据来源": "Data source", "选择 Codex 数据目录…": "Choose Codex data folder…", "在 Finder 中显示": "Show in Finder",
        "选择包含 sessions 的 Codex 数据目录（通常为 ~/.codex）": "Choose the Codex folder containing sessions (usually ~/.codex)",
        "按需读取 sessions 和 archived_sessions 中的日志。每 30 秒检查一次，只重新解析发生变化的文件。": "Reads sessions and archived_sessions for the selected range. Checks every 30 seconds and reparses only changed files.",
        "菜单栏与启动": "Menu bar & startup", "菜单栏显示今日 token 数字": "Show today's tokens in the menu bar", "外观": "Appearance", "跟随系统": "System", "浅色": "Light", "深色": "Dark", "登录时启动": "Launch at login", "语言": "Language",
        "登录启动建议在将应用移动到固定位置后开启。右键点击菜单栏图标也可刷新、打开账本或退出。": "Enable launch at login after placing the app in its permanent location. Right-click the menu bar icon to refresh, open the ledger, or quit.",
        "如何理解数字": "Understanding the numbers", "已结束": "Finished", "未记录结束": "No end recorded", "分类": "Category", "自动分类": "Automatic", "打开聊天": "Open chat", "打开": "Open",
        "显示用量面板": "Show usage panel", "Codex 今日用量": "Codex usage today", "刷新用量": "Refresh usage", "Codex Ledger · 用量总览": "Codex Ledger · Usage", "Codex Ledger · 工作账本": "Codex Ledger · Work ledger",
        "请在系统设置 → 通用 → 登录项中允许 Codex Ledger。": "Allow Codex Ledger in System Settings → General → Login Items.",
        "模型用量": "Model usage", "使用模型": "Models used", "已识别的不同模型": "Distinct recorded models", "模型": "Models", "查看模型用量": "View model usage", "查看相关任务": "View related tasks", "清除筛选": "Clear filters",
        "模型名称缺失的调用单独列出，不计入已识别模型数量。": "Calls without a model name are shown separately and excluded from the distinct model count.",
        "Codex 内部检查或子代理记录": "Internal Codex check or subagent record", "提示词以询问、解释或方案讨论为主": "The request asks a question, explanation, or planning discussion", "关联了多种文档产物": "Linked to multiple document types",
        "依据关联的本地文件": "Inferred from linked local files", "提示词包含开发、修复或实现要求": "The request asks for development, fixes, or implementation", "提示词请求多种产物，尚未确认最终文件": "The request asks for multiple outputs; final files are unconfirmed",
        "依据提示词中的产物要求和关联文件": "Inferred from the requested output and linked files", "依据提示词中的产物要求，文件尚未确认": "Inferred from the requested output; files are unconfirmed", "依据产物要求和关联的本地文件": "Inferred from the output request and linked files",
        "提示词以研究或分析为主": "The request focuses on research or analysis", "提示词请求视觉创作": "The request asks for visual creation", "提示词涉及代码或调试": "The request involves code or debugging", "沿用同一聊天上一轮的工作类型": "Continues the preceding work category in this chat",
        "日志未记录可识别的用户请求": "No identifiable user request in the log", "一般问答；可在任务详情中修正": "General question; editable in task details", "你手动设置的分类": "Category set manually",
        "任务": "Task", "缓存输入tokens": "Cached input tokens", "输入tokens": "Input tokens", "输出tokens": "Output tokens", "推理输出tokens": "Reasoning output tokens", "总tokens": "Total tokens", "聊天ID": "Chat ID", "分类依据": "Classification basis", "调用次数": "Responses", "相关任务数": "Task turns",
        "• 总 token = 输入 + 输出。缓存是输入的一部分，推理是输出的一部分，不重复相加。\n• 优先按 response_id 统计，并跳过同时出现的累计记录。旧日志使用累计用量的增量。\n• 日期按此 Mac 的时区，以模型调用记录时间划分。跨日任务只统计所选范围内的调用。\n• 分类来自本地规则和可识别的产物，属于推断。展开任务后可以改分类。\n• 关联文件表示日志中提及且当前存在的文件，不代表已经验收。\n• 后台检查单独列出；能对应到用户任务的子代理消耗会并入任务。\n• 只覆盖可读的本机日志，不代表所有设备、云端消耗或订阅账单。\n• 本应用不联网、不调用模型，也不读取 Codex 登录凭证。": "• Total tokens = input + output. Cached tokens are part of input; reasoning tokens are part of output. Neither is counted twice.\n• Responses are deduplicated by response_id. Older logs use changes in cumulative counters.\n• Dates use this Mac's time zone and each model call's timestamp. Cross-day tasks contribute only calls in the selected range.\n• Categories are inferred locally and can be edited in task details.\n• Linked files were mentioned in logs and exist locally; this does not verify completion.\n• Matched subagent usage is included in the parent task. Other internal checks are listed separately.\n• Only readable local logs are covered, not other devices, cloud usage, or billing.\n• No network, model calls, or access to Codex login credentials."
    ]
    static func string(_ value: String) -> String {
        guard language == "en" else { return value }
        if let exact = english[value] { return exact }
        let patterns: [(String, String)] = [
            (#"^(\d+) 个对话$"#, "$1 conversations"),
            (#"^(\d+) 个任务$"#, "$1 tasks"), (#"^(\d+) 轮已结束$"#, "$1 finished"), (#"^(\d+) 次响应$"#, "$1 responses"),
            (#"^(.*)，(\d+) 个任务，(.*) token$"#, "$1, $2 tasks, $3 tokens"),
            (#"^(\d+) 秒后更新$"#, "Updates in $1s"), (#"^正在扫描 (\d+)/(\d+) 份日志$"#, "Scanning $1/$2 logs"),
            (#"^查看全部任务 · 另 (\d+) 类用途$"#, "View all tasks · $1 more categories"),
            (#"^跳过 (\d+) 条无法解析的记录。$"#, "Skipped $1 unreadable records."),
            (#"^(\d+) 份日志 · 分类可手动修正$"#, "$1 log files · editable categories"),
            (#"^总用量 (.*) token$"#, "Total usage $1 tokens"),
            (#"^(\d+) 个任务 · (.*) token$"#, "$1 tasks · $2 tokens"),
            (#"^输入 (.*) · 输出 (.*)$"#, "Input $1 · Output $2"),
            (#"^(\d+) 个模型$"#, "$1 models"), (#"^(\d+) 个任务 · (\d+) 次调用$"#, "$1 tasks · $2 responses"),
            (#"^Codex Ledger · 今日 (.*) token · (\d+) 个任务$"#, "Codex Ledger · Today $1 tokens · $2 tasks")
        ]
        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern), regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil {
                let translated = regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: replacement)
                return translated.replacingOccurrences(of: #"\b1 tasks\b"#, with: "1 task", options: .regularExpression)
                    .replacingOccurrences(of: #"\b1 conversations\b"#, with: "1 conversation", options: .regularExpression)
                    .replacingOccurrences(of: #"\b1 responses\b"#, with: "1 response", options: .regularExpression)
                    .replacingOccurrences(of: #"\b1 models\b"#, with: "1 model", options: .regularExpression)
            }
        }
        var result = value
        let fragments: [String: String] = ["读取失败：": "Read failed: ", "无法读取 ": "Cannot read ", "没有找到 sessions 或 archived_sessions。请在设置中选择 Codex 数据目录。": "No sessions or archived_sessions folder found. Choose the Codex data folder in Settings.", "正在查找日志…": "Finding logs…", "登录项设置失败：": "Login item failed: ", "导出失败：": "Export failed: ", "按模型调用发生时间归属日期": "Dates follow model call timestamps", "更新于 ": "Updated ", "模型：": "Models: ", " · 含 ": " · Includes ", " 次子代理响应": " subagent responses", "上次扫描 %.2f 秒 · %d 份日志": "Last scan %.2fs · %d log files"]
        for (key, text) in fragments { result = result.replacingOccurrences(of: key, with: text) }
        return result
    }
}

func L(_ value: String) -> String { LedgerText.string(value) }
