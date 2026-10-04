# Validation record

Version 1.1.0 · 2026-10-04

## Automated checks

- 134 accounting/classification/analytics/pricing checks and 9 navigation/scope regressions pass locally.
- Fixtures cover multi-turn and multi-chat projects, identical folder names, repository subdirectories, symlink aliases, linked worktrees, cross-project conversations, missing/deleted directories, duplicate/archived copies, per-response date boundaries, legacy counters and parent/subagent attribution.
- Price checks cover cached/reasoning subsets, exact Decimal arithmetic, short/long thresholds, legacy context uncertainty, unknown aliases, duplicate/date/subagent records and project/conversation/model/CSV equality. All 25 bundled rates were compared against official Standard prices and the documented snapshot alias.
- All token fields agree across task/project/conversation summaries. Per-conversation models preserve accounting, including child agents and project scopes. Read-only metadata lookup leaves fixture databases unchanged; missing/incompatible schemas fall back safely.
- CSV checks include escaping, formula neutralization, UTF-8 BOM, localization and scope. Native save dialogs exported a 3-chat project summary, a 1-chat scoped summary and its 2 turns. Python CSV parsing confirmed totals and paths match the UI.
- Real local logs were checked with read-only diagnostics for Today, Last 30 days and All time; project/conversation/task totals and subset relationships agreed. No personal logs or exports are included in this repository. On the development Mac, cold scans took approximately 6, 10 and 97 seconds respectively; timing is data-dependent.
- Universal binary builds for arm64 and x86_64. The archived app passes strict ad-hoc signature verification; ZIP and DMG integrity checks pass.

## Native UI checks

Checked on Apple Silicon, macOS 27.0.1, with synthetic data and isolated preferences:

- Project → scoped conversation → task turns; global conversations; cross-project badges. Example: 4.66M in the Atlas project versus 5.58M across the full conversation.
- Back navigation, no-result search, clear filters, model/category distribution and project/conversation/turn export.
- Minimum 880-point content width; fixed-size summary cards; long English category labels wrap; content scroll position resets when navigating.
- English/Chinese settings and Light/Dark rendering; all five overview date choices; fixed overview header/footer, keyboard/menu opening and dismissal.
- Loading states show ellipsis/dashes rather than false zero counts, keep Settings/navigation usable, and disable exports until data is ready.
- Empty/error, the newly added cost UI and final installation visual checks remain pending tool authorization at this checkpoint.

## Corrections found during validation

Fixed clipping in the overview, loading counters, uneven summary cards, English category truncation, stale scroll offsets, export scope and per-model detail accounting. A date change that removes the selected project now keeps an empty project scope rather than falling back to global conversation data. Conversation distribution scrolls within a capped area so many models cannot consume the entire task list.

## Limits

Login startup has not been tested by logging out/rebooting. Physical multi-display arrangements and an independent other-Mac Gatekeeper first launch have not been tested. Releases are ad-hoc signed, not Apple notarized. The pre-cost build passed native CI on macOS 14 Apple Silicon, current Apple Silicon and macOS 15 Intel. The cost addition requires another CI run; current status is visible in GitHub Actions. Headless native tests do not validate Intel UI appearance. The ICNS provides a static glass-style icon, not a native dynamic Icon Composer icon.
