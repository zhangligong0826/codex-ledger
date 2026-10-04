# Contributing

Run `zsh test.sh` and `zsh build.sh` on a Mac with Apple's Command Line Tools before submitting changes. Explain observable behavior and relevant validation.

`LedgerCore.swift` parses and deduplicates calls; `LedgerAnalytics.swift` resolves projects and summarizes chats; `LedgerStore.swift` owns background work/navigation/export; `LedgerViews.swift` and `CodexLedger.swift` implement native UI. Strings go through `Localization.swift` in English and Chinese.

Preserve input + output = total, equal project/conversation/task/model totals, cache/reasoning subsets, read-only metadata, and accounting when metadata/directories are missing. Use synthetic fixtures. Never commit real logs, exports, titles, credentials or personal paths.

For UI changes, inspect demo mode at minimum size in both languages and all appearances. Exercise loading/empty/error, navigation/search/clear/export/cancel and all five overview ranges. Document unverified behavior.

Report bugs with versions and sanitized reproduction steps. Do not attach personal logs publicly. For security issues, use private vulnerability reporting in the Security tab if available; otherwise contact the maintainer before sharing details.

## Windows and common accounting

Use .NET 10 and `dotnet run --project Windows/Ledger.Tests`; `dotnet build Windows/Ledger.App` requires Windows desktop targeting packs. Packaging requires Inno Setup on Windows. `--ui-smoke --output=<folder>` generates synthetic app renders with isolated state; it must never read real logs/preferences.

Every parser/pricing change must reconcile against both implementations through `Common/Fixtures`, including per-response costs, subsets, duplicate/child records and date boundaries. Price catalog values are decimal strings. Goal completion stores its original price date.

Keep share-card defaults free of names, paths and chat text. Capture only app content; do not add desktop capture permissions, upload services or analytics. Add actual evidence to QA.md, distinguishing generated views from interaction/physical-device testing.
