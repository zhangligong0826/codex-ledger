# Contributing

Run `zsh test.sh` and `zsh build.sh` on a Mac with Apple's Command Line Tools before submitting changes. Explain observable behavior and relevant validation.

`LedgerCore.swift` parses and deduplicates calls; `LedgerAnalytics.swift` resolves projects and summarizes chats; `LedgerStore.swift` owns background work/navigation/export; `LedgerViews.swift` and `CodexLedger.swift` implement native UI. Strings go through `Localization.swift` in English and Chinese.

Preserve input + output = total, equal project/conversation/task/model totals, cache/reasoning subsets, read-only metadata, and accounting when metadata/directories are missing. Use synthetic fixtures. Never commit real logs, exports, titles, credentials or personal paths.

For UI changes, inspect demo mode at minimum size in both languages and all appearances. Exercise loading/empty/error, navigation/search/clear/export/cancel and all five overview ranges. Document unverified behavior.

Report bugs with versions and sanitized reproduction steps. Do not attach personal logs publicly. For security issues, use private vulnerability reporting in the Security tab if available; otherwise contact the maintainer before sharing details.
