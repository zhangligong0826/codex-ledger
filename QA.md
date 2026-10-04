# Validation record

Version 1.1.0 · 2026-10-04

## Automated checks

- 142 accounting/classification/analytics/pricing checks and 9 navigation/scope regressions pass locally.
- Fixtures cover multi-turn and multi-chat projects, identical folder names, repository subdirectories, symlink aliases, linked worktrees, cross-project conversations, missing/deleted directories, duplicate/archived copies, per-response date boundaries, legacy counters and parent/subagent attribution.
- Additional file-created repository/worktree fixtures cover relative and absolute Git pointers, subdirectories, missing metadata, malformed/oversized pointers and invalid common directories. Production discovery runs no Git executable and cannot invoke the macOS developer tools installer.
- Price checks cover cached/reasoning subsets, exact Decimal arithmetic, short/long thresholds, legacy context uncertainty, unknown aliases, duplicate/date/subagent records and project/conversation/model/CSV equality. All 25 bundled rates were compared against official Standard prices and the documented snapshot alias.
- All token fields agree across task/project/conversation summaries. Per-conversation models preserve accounting, including child agents and project scopes. Read-only metadata lookup leaves fixture databases unchanged; missing/incompatible schemas fall back safely.
- CSV checks include escaping, formula neutralization, UTF-8 BOM, localization and scope. Native save dialogs exported a 3-chat project summary, a 1-chat scoped summary and its 2 turns. Python CSV parsing confirmed totals and paths match the UI.
- Real local logs were checked with read-only diagnostics for Today, Last 30 days and All time; project/conversation/task totals and subset relationships agreed. No personal logs or exports are included in this repository. On the development Mac, cold scans took approximately 6, 10 and 97 seconds respectively; timing is data-dependent.
- After adding pricing, Today and All time were checked again: all project/conversation/task/model cost totals and priced/unpriced token coverage agreed. Cold scans took approximately 6 and 94 seconds.
- Homebrew Cask syntax and `brew style` pass; its SHA-256 matches the verified universal ZIP. Public asset download and isolated Homebrew install/uninstall remain pending publication.
- Universal binary builds for arm64 and x86_64. The archived app passes strict ad-hoc signature verification; ZIP and DMG integrity checks pass.

## Native icon checks

- Official Icon Composer 1.2 and Xcode 27.0 are installed on the development Mac. The original `.icon` document renders successfully through Apple's `ictool` in Default, Dark, ClearLight and TintedDark, with no baked glass effects in the SVG layers. All four 1024-pixel previews were visually inspected.
- Exports at two light angles differ, confirming that the renderer uses the document's lighting. Preview exports are static images, not evidence of a Finder/Dock animation.
- Xcode `actool` compiles the document for a macOS 14 deployment target without warnings or errors. The generated Info.plist supplies `CFBundleIconName=AppIcon`; `Assets.car` contains three native appearance stacks and three-vector-layer groups with lighting and specular material. `assetutil` validates its structural integrity.
- Small generated compatibility icons were visually inspected at 32 and 128 pixels. Universal native builds and Command Line Tools-only fallback builds are checked separately; required-native mode rejects a Command Line Tools-only toolchain.
- The release workflow requires native compilation, and packaging rechecks the extracted signed app's native assets before creating the DMG. End users do not need Xcode or Icon Composer.
- The native icon commit passed all three macOS CI jobs, including required native compilation on the latest runner ([run 37186588211](https://github.com/zhangligong0826/codex-ledger/actions/runs/37186588211)). Installed Finder/Dock rendering and the final app UI remain unverified because native app control was not authorized. CLI rendering and catalog validation do not replace those checks.

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

Login startup has not been tested by logging out/rebooting. Physical multi-display arrangements and an independent other-Mac Gatekeeper first launch have not been tested. Releases are ad-hoc signed, not Apple notarized. The cost build passed all three native CI jobs on macOS 14 Apple Silicon, current Apple Silicon and macOS 15 Intel ([run 37184143925](https://github.com/zhangligong0826/codex-ledger/actions/runs/37184143925)). Headless native tests do not validate Intel UI appearance. Native icon support depends on the OS; older systems use flattened compatibility representations.
