# Codex Ledger

在 Mac 菜单栏和 Windows 系统托盘，查看每个目标、项目、对话及任务轮次用了多少 token、对应多少 API 成本估算，并展示近 30 天热力图。

[下载与安装](https://zhangligong0826.github.io/codex-ledger/) · [English](README.md) · [验证记录](QA.md) · [计价说明](PRICING.md)

## 安装免费测试版

**1.2.0-beta.1**：macOS 14 及以上（Apple 芯片／Intel），Windows 11（x64／ARM64）。

Mac：从[发布页](https://github.com/zhangligong0826/codex-ledger/releases/tag/v1.2.0-beta.1)下载 universal DMG，打开后把 Codex Ledger 拖到 Applications，启动后点击菜单栏图标。也可以使用 Homebrew：

```sh
brew install --cask zhangligong0826/tap/codex-ledger
```

Windows：下载对应架构的安装 EXE，或解压免安装 ZIP 后运行 `CodexLedger.exe`。点击系统托盘图标查看总览和详细账本。运行时已内置，默认按当前用户安装。升级和卸载保留本机设置及目标账本。

测试版的 Mac 使用临时签名、未完成 Apple 公证，Windows 尚未正式签名。首次打开请按 [Apple 官方步骤](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)及 Windows 设备策略确认，公司设备可能需要管理员批准。安装流程保留系统安全检查。

发布页 `CHECKSUMS.txt` 提供全部六个安装产物的 SHA-256。Windows ARM64 已交叉构建，尚未完成原生运行及 Windows 实机验收；具体范围见 [QA.md](QA.md)。

## 为具体目标记账

创建“完成论文”“做出这个 app”等目标，将相关项目、对话、轮次归入目标。归属优先级为轮次 → 对话 → 项目，每轮最多计入一个目标；明确“不归入目标”会停止继承。项目和对话规则覆盖既有及后续轮次。

累计金额不随日期筛选改变。标记完成保存当时的 token、估算金额和价格日期，后续工作不改写完成时记录。重新打开会清除完成记录，删除目标只移除归属规则，保留日志。

项目按仓库或工作目录区分，同一仓库 worktree 合并；同名文件夹显示路径。支持项目／目标 → 对话 → 轮次导航、跨项目对话、搜索和当前范围 CSV。提供中英文及跟随系统／浅色／深色外观。

## 截图与分享

分享菜单提供“生成分享卡片”“保存当前界面”“导出 CSV”。卡片为适合小红书的 **1080×1440 PNG**，展示估算美元金额、token、轮次、近 30 天热力图及安装二维码；已完成目标也显示完成时金额。

卡片默认隐藏名称、路径和对话标题，可填写公开标题，或选择显示原始名称。界面截图保留当前可见内容。先检查预览，再复制或保存。生成期间冻结统计，图片处理全部在本机完成；二维码指向固定下载入口，版本更新后仍然有效。

## 统计与隐私

总 token＝输入＋输出，缓存输入及推理输出分别为子集，不重复相加。响应 ID 跨归档副本去重，排除继承历史，将匹配的子代理调用归入父轮次；旧日志按累计增量及重置段计算。按本机时区逐次响应归到日期，处理夏令时边界。

金额使用共同的离线 Standard API 单价快照，逐次响应计算缓存及长上下文价格。未知模型保留为未计价，部分估算显示 `*`。**金额是 API 成本估算，不代表订阅扣款或实际账单。**价格日期及排除项详见 [PRICING.md](PRICING.md)。

应用不联网、不调用模型、不读取登录凭证、不上传聊天。对话标题 SQLite 为可选只读来源，缺失或不兼容时回退日志；仓库识别只读取有大小限制的 Git 指针文件，不执行 Git、钩子或配置。CSV 与界面截图可能包含私人名称和路径。

默认读取 `CODEX_HOME` 或用户目录的 `.codex`，包含 `sessions` 和 `archived_sessions`，可在设置中更换。每 30 秒后台检查变化，首次读取历史可能较慢。各数据目录独立保存目标账本；Mac 沿用 UserDefaults，Windows 保存在 `%LOCALAPPDATA%\CodexLedger`。

## 开发

MIT 开源。Mac 构建需要 Apple Command Line Tools；原生分层图标需要初始化的 Xcode 26 及以上。Windows 使用 .NET 10，安装包制作另需 Inno Setup。下载使用无需安装开发工具。

构建命令和依赖见 [英文 README](README.md)、[第三方说明](THIRD-PARTY.md)。两端使用 `Common/` 的共同价格目录及合成测试样本。发布与维护步骤见 [RELEASING.md](RELEASING.md)。

独立社区项目，与 OpenAI、Apple、Microsoft 无隶属关系。

## 分享预览

下图使用模拟数据。卡片在本机生成，默认隐藏名称和路径，二维码始终指向固定下载页。

![模拟数据分享卡片](docs/previews/share-card.png)
