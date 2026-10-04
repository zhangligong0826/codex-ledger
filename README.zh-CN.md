# Codex Ledger · Codex 工作账本

原生 macOS 菜单栏应用，查看本机 Codex 的 token 用在了哪些项目、对话和工作上。

[English](README.md) · [下载安装包](https://github.com/zhangligong0826/codex-ledger/releases/latest)

## 安装

支持 macOS 14 及以上，通用包同时支持 Apple Silicon 和 Intel。

```sh
brew install --cask zhangligong0826/tap/codex-ledger
```

从“应用程序”打开 Codex Ledger，点击菜单栏图标查看紧凑总览，选择“查看项目与对话”打开账本。也可以下载 DMG，将应用拖入 Applications。

**首次打开：当前包使用 ad-hoc 签名，尚未经过 Apple 公证。** 如果 macOS 拦截，先尝试打开，再到“系统设置 → 隐私与安全性”选择“仍要打开”，确认信任来源后继续。安装器保留系统安全检查，不自动移除隔离属性。SHA-256 校验确认文件完整性，不能证明发布者身份。参见 [Apple 说明](https://support.apple.com/102445)。

```sh
brew upgrade --cask zhangligong0826/tap/codex-ledger
brew uninstall --cask zhangligong0826/tap/codex-ledger
```

卸载不会删除 Codex 日志。保留一份安装副本；从手动安装迁移到 Homebrew 时，先退出并移走旧应用，不要删除 `.codex` 数据。

## 查看与导出

- 今天、昨天、近 7 天、近 30 天、历史累计。
- **项目 → 对话 → 任务轮次**；同一 Git 仓库子目录和 worktree 合并，普通目录按完整路径区分。
- 每轮按目录归属，跨项目对话有标记。项目内只统计该项目消耗，全局统计所选日期内的完整对话消耗。缺少目录的记录放入“未识别项目”。
- **预估 API 花费（美元）**，覆盖总览、项目、对话、任务和模型，点击金额旁的信息按钮查看输入／缓存／输出金额和未计价用量。
- 每轮输入、缓存输入、输出、推理输出，以及对话模型和用途分布。搜索项目名、路径、对话标题、任务和模型。
- 导出项目／对话汇总 CSV；对话详情另可导出各轮 CSV。任务和模型页支持导出，表头跟随语言。
- 默认英文，可切换简体中文；支持系统、浅色、深色外观，登录启动、菜单栏数字、手动分类和打开原始聊天。

总览最大 340 × 460 点，标题、日期和底栏固定，内容可滚动。右键可刷新、打开账本、设置或退出；激活时 ⌘L 切换总览，Escape 收起，⌘Q 退出，总览中 ⌘R 刷新。

## 统计与隐私

总 token＝输入＋输出。缓存是输入子集，推理是输出子集，不额外相加。日期按响应时间和本机时区计算。现代记录按响应 ID 去重并排除继承副本，旧日志读取累计增量。匹配父轮次的子代理归入父任务及项目，其余后台活动保留。各层使用同一份去重调用汇总。

只覆盖本机仍保留的可读日志，不代表订阅额度或账单。用途由规则推断，可手动修正；关联文件只代表日志出现且本机存在。

金额使用已核对的 [OpenAI 官方 Standard API 单价](https://developers.openai.com/api/docs/pricing)（2026-10-04 快照），逐个去重响应计算。缓存单独计价，推理不重复收费；长上下文按单次响应判断，旧日志无法确认时按短上下文估算。未知模型不猜价：部分计价显示 `*`，全部未计价显示“单价未知”，不会当成零元。历史用量也使用当前价格快照，含促销价格。金额未含缓存写入溢价、Fast／Batch／Flex 档位差异、工具费和税费；**不代表订阅用户的实际扣款**。CSV 保留金额精度、计价覆盖和核对日期。详见 [PRICING.md](PRICING.md)。

应用不联网，不调用模型，不读取登录凭证，不上传聊天。只读兼容的本机 SQLite 标题，缺失时回退到日志；Git 识别使用只读命令。索引留在内存，设置保存在本机。CSV 仅在选择导出时写入，可能包含私人标题和路径，请自行选择分享对象。

默认读取 `CODEX_HOME` 或 `~/.codex`，含 `sessions` 和 `archived_sessions`，可在设置换目录。每 30 秒检查变化文件；长日期范围按需扫描，仓库识别和汇总在后台执行，首次历史扫描可能较久。

## 源码

MIT 开源，无第三方依赖。安装 Apple Command Line Tools 后：

```sh
git clone https://github.com/zhangligong0826/codex-ledger.git
cd codex-ledger
zsh test.sh
zsh build.sh
zsh package.sh
```

产物在 `dist/`。构建、诊断和演示模式见 [英文 README](README.md)，验证范围见 [QA.md](QA.md)。独立社区项目，与 OpenAI 和 Apple 无隶属关系。
