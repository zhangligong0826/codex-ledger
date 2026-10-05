## Unreleased — macOS performance (build 13)

- Persist a private, checksummed, disposable parsed-log index across launches; reparse changed logs and rebuild incompatible/corrupt entries.
- Load recent usage before historical accounting, with separate scan and analytics queues so history parsing does not block date navigation.
- Skip unchanged timer aggregations; reuse today, lifetime and heatmap data for date changes while invalidating at day/timezone boundaries and refreshing optional metadata periodically.
- Cache goal summaries and their Decimal totals, throttle progress updates, and avoid parsing timestamps on unrelated records.
- Add cache and asynchronous startup/refresh regression tests and optional diagnostic cache/timing counters. Public Beta.3 release assets remain build 12.

## 1.2.0-beta.3 — 2026-10-05

- Reconcile mixed counter/response logs; flag incomplete records and block completion snapshots when coverage is incomplete.
- Align search scope across projects, conversations, models, summaries, shares and CSV.
- Preserve capture time, actual dates, timezone and historical completion-price provenance.
- Validate storage, retain recovery copies and support portable goal-book export/import with exact decimal strings.
- Add optional goal budgets and cost/token heatmap intensity; prioritize completed outcome amounts.
- Restore the running Windows instance on repeat launch. Centralize version metadata and test a genuine Beta.2 upgrade with retained settings and frozen amounts.

# Changelog

## 1.2.0-beta.2

- Unreadable goal books display unknown amounts and block goal-dependent card/CSV generation; raw usage remains available.
- Freeze CSV before its save dialog and copy share activity into an immutable collection.
- Existing Beta.1 packages and checksums remain unchanged.

## 1.2.0-beta.1

- Native Windows tray app, x64/ARM64 self-contained installers and portable packages.
- Local share cards, current-view captures, copy/save PNG, scoped CSV and stable install QR.
- Shared offline prices and synthetic accounting fixtures; preserve goal completion estimates.
- Public download page, Homebrew tap and explicit cross-platform release asset validation.
- Free beta: no formal publisher signing/notarization; physical Windows acceptance pending.

## 1.1.0

- Slimmer 300-point overview with a calendar-aligned 30-day token heatmap, exact daily tooltips, monthly totals and active days. Response-level deduplication and local calendar boundaries match the ledger.

- Offline Standard API cost estimates in USD across all scopes, per-response long-context pricing, cache-aware accounting, unpriced coverage and matching CSV fields.

- Project → conversation → task-turn accounting, repository/worktree grouping, cross-project scopes, local titles, search and CSV summaries.
- Repository/worktree discovery reads metadata directly, avoiding Git and developer-tools installation prompts on end users' Macs.
- Per-conversation model and category distribution; turn CSV includes project and working-directory paths.
- Fixed overview clipping, loading counters, page scroll restoration, minimum-window layout, card alignment and English labels.
- Original ice-blue and silver Icon Composer document with native layered Liquid Glass, dark/tintable resources, compatible ICNS and a matching monochrome menu bar silhouette.
- Universal macOS 14+ builds, MIT source, Homebrew Cask, DMG/ZIP/checksums and native CI.

## 1.0.0 (local development)

- Menu bar overview, work classification, task/model accounting, five ranges, English/Chinese, appearances and CSV.
