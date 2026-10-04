# Validation record

Version 1.1.0 · 2026-10-04

## Automated checks

- 152 accounting/classification/analytics/pricing/activity checks and 12 navigation/scope/activity-state regressions pass locally.
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

## Slim overview and activity grid

- The overview is 300 points wide and at most 560 points tall, with three category rows and a visible goal-ledger action. Header and footer stay fixed; overview scroll indicators are hidden, including when the screen forces a shorter panel.
- Daily accounting shares response deduplication with the ledger. Checks cover exactly 30 calendar days, start/end boundaries, duplicates/archived copies, cross-day tasks, child calls, absent days, monthly subset equality and the 23-hour daylight-saving day in Los Angeles. Demo monthly totals equal its heatmap.
- Offscreen native view rendering with synthetic data was inspected in English/Chinese, Light/Dark, loading, empty and error states. These are generated previews, not screenshots of the installed app. Failed reads use unknown values rather than zero in the overview.
- The taller overview was also rendered at 420 points with the always-show-scrollbars preference registered in the preview process; no right-side track appeared. English/Chinese and light/dark previews, plus loading/empty/error states, were reinspected after the height change.
- Hover interactions, click-through and installed window placement remain pending native app operation authorization.

## Named goals and outcome costs

- Goal attribution uses the deduplicated parent-attributed turns, independent of inferred categories. Checks cover overlapping project/chat/turn rules, cross-project chats, explicit unassignment, inherited restoration, token subsets and exact Decimal cost reconciliation with unassigned usage.
- Store checks cover independent lifetime totals across date changes, goal/chat/back navigation, search, persistence, rename/delete safety and unreadable-book preservation. Completion captures cost, tokens and the price date, survives restart and remains unchanged by later assignments; reopening clears it. Unreadable source data cannot be marked as zero-cost completion.
- Goal CSV shares view summaries and exports range/lifetime/completion values and pricing coverage. Turn CSV includes the goal name and retains formula/quote/newline escaping.
- New views are checked using offscreen native SwiftUI renders with synthetic data, including English/Chinese, light/dark, empty goals, completed goals, three-level navigation, assignment entry points and the 880 × 580 minimum. Actual app menu/sheet interactions remain pending the existing native app operation authorization.

## Prominent overview cost and daily monetary activity

- The 300-point overview shows the selected range's estimated USD cost as its primary number; the ring and token/turn figures remain visible. The 30-day card shows estimated USD cost, tokens and active days beside its contribution-style grid. Cell tooltips include date, cost, exact tokens and responses; color remains relative daily token intensity.
- Daily costs accumulate per deduplicated response, preserving cache/output components, unknown-model coverage and long-context request pricing. Regression checks reconcile daily money and pricing subsets with the monthly ledger, mixed parent/child models, inactive days, unknown prices, long context and duplicate records. The demo heatmap's monetary total matches its monthly snapshot.
- Native offscreen previews are checked in English/Chinese, light/dark and loading/empty/error states at 300 points, plus a 420-point height to force overflow without a scrollbar track. These checks do not replace the still-pending installed app interaction acceptance.

- The overview-cost and named-goal code passed all 208 checks, app compilation, signature verification and empty-source diagnostics on macOS 14 Apple Silicon, latest macOS Apple Silicon and macOS 15 Intel ([run 37190793982](https://github.com/zhangligong0826/codex-ledger/actions/runs/37190793982), source `47b7451`). Long goal CSV and view expressions were split to support older Swift compilers. A fully unpriced overview was also rendered and inspected; it shows Unpriced rather than zero money.

## 1.2.0-beta.1 cross-platform sharing

- Local Swift validation: 197 accounting/classification/pricing/shared-fixture checks, 12 store navigation/state checks, and 38 goal checks. Windows core initially passes 85 checks on the development Mac; Windows-only path checks run on the hosted Windows runner.
- The same synthetic modern/legacy/forked long-context records reconcile exact Decimal costs, token/cache/reasoning subsets, dates, duplicate copies, child attribution and model coverage on both implementations. Scoped daily amounts reconcile with their corresponding turns.
- Synthetic macOS share renders cover English/Chinese and light/dark, 1080 × 1440 output, frozen project/month scope and default name/path privacy. Apple Vision decodes all four QR codes to the stable download page. Visual inspection corrected clipping caused by the seven-row heatmap.
- Windows uses isolated `--ui-smoke` state, generating six pages × two languages × three appearance modes, plus overview/share cards. Navigation, search/clear, scope, CSV and freeze/dimensions are asserted. Hosted-runner results and inspected artifacts will be recorded with the final passing run.
- The Windows pipeline validates x64 installer/upgrade/uninstall and installed empty-source diagnostics; ARM64 is cross-built, not executed on native ARM64 hardware. No physical Windows device is available.
- macOS previews are offscreen views owned by the test process. Installed-app sharing menus, save panels and clipboard interactions have not been independently controlled/verified. Generated images do not count as that interaction acceptance.
- Free-beta packages do not have formal publisher signing or Apple notarization. No public package is described as fully verified on physical Windows hardware.

- Windows hosted CI first passed at [run 37200823066](https://github.com/zhangligong0826/codex-ledger/actions/runs/37200823066): core tests, 36 localized/appearance/page renders, navigation/search, frozen share/CSV, both packages, and x64 per-user install/upgrade/uninstall. Its images were inspected; corrections include an opaque app-content capture background, a two-row narrow overview header, and heatmap date-label spacing.
- The default SwiftUI offscreen image target aborted in the GPU-less Intel VM. Using an explicit CPU bitmap context fixes this. All three macOS environments now render cards and pass Vision QR/OCR tests; no image validation is skipped in CI ([run 37202615017](https://github.com/zhangligong0826/codex-ledger/actions/runs/37202615017)). This does not claim Intel physical UI acceptance.
- Local dependency audit after replacing the old SQLite bundle reports no known vulnerable packages. Windows distributes .NET/library licenses and notices alongside the app.
- Download page was rendered at 1440-pixel desktop and 390-pixel phone widths in light/dark, with EN/CN toggle and asset links checked; no horizontal overflow.

- Final functional checks before packaging: [macOS run 37202817230](https://github.com/zhangligong0826/codex-ledger/actions/runs/37202817230) and [Windows run 37202817190](https://github.com/zhangligong0826/codex-ledger/actions/runs/37202817190) passed. macOS has 247 core/store/goal checks plus sharing checks; Windows has 87 accounting/shared-fixture checks, 36 minimum-window renders and sharing/navigation assertions. Windows additionally verifies image clipboard roundtrip, expected save failure, x64 portable execution with an invalid global runtime path, per-user install/upgrade/uninstall, and a user-data sentinel that survives uninstall.
- Hosted Windows images were inspected in both languages and light/dark; an independent Vision check on the development Mac decoded all four card QR codes and confirmed private titles were absent. Large/completed/unpriced and 120-character-title fixtures are generated separately. A clipping issue found in the Mac completion fixture was fixed using a fixed card layout; release CI reruns these checks on the tagged source.
- Scope regressions cover empty project search, filtered conversation CSV/share equality, metadata-only chat title search, and project monthly activity from conversations absent in Today. The download page is tested using real Mac/Windows/iPhone user agents, including the phone-only installation instruction and system-specific recommended panel.


## Beta.2 error-state correction

Follow-up review found that readable source logs could make an unreadable goal book appear as a zero-cost sharing context. Beta.2 makes goal-dependent amounts unknown, blocks their card/CSV generation, and preserves independent raw usage. Swift and Windows regression checks exercise these gates and the raw-overview fallback. Existing Beta.1 binary assets/checksums are retained; the correction has a separate version/tag. Windows share snapshots copy daily data into a read-only collection, and CSV freezes before opening its save dialog.

The custom Homebrew tap deliberately distributes a prerelease. Syntax/style and online audits pass with only `github_prerelease_version` excluded; the default upstream audit rejects a prerelease on policy grounds. Beta livecheck is explicitly skipped, and verified versions/checksums are maintained in the tap. No signing, quarantine or checksum check is disabled.


## Published Beta.2 acceptance record

- Tagged source `9936cab3c454f053c75222bdb628415fcd9ece50` passed the complete [release workflow 37207518909](https://github.com/zhangligong0826/codex-ledger/actions/runs/37207518909): macOS 14 Apple Silicon, current macOS Apple Silicon, macOS 15 Intel, Windows x64 execution/tests, x64/ARM64 Windows packaging and universal Mac packaging. The corrupted-goal-book regression uses isolated storage, rather than changing a private production flag.
- Both Beta.1 and the separate Beta.2 are public prereleases. Beta.2 has exactly six binaries plus `CHECKSUMS.txt`. All six public assets were downloaded and their full SHA-256 values matched. ZIP integrity, DMG verification, universal architectures, Windows PE architectures, bundled runtime and licenses were checked. A pristine Mac archive extraction passed strict ad-hoc signature verification. Finder/FileProvider metadata added by the development machine to copies under Documents is not part of the archive.
- The [fixed download page](https://zhangligong0826.github.io/codex-ledger/) was deployed by [Pages workflow 37208424764](https://github.com/zhangligong0826/codex-ledger/actions/runs/37208424764). Public Mac/Windows/iPhone user-agent checks passed localized navigation, recommended platform, phone instructions, light/dark layout and horizontal-overflow checks. Its version is Beta.2, and all six binary URLs plus the checksum URL return HTTP 200.
- The Homebrew tap points to the verified Beta.2 universal ZIP. On the development Mac, an isolated custom-app-directory install passed signature verification; uninstall removed its app. A subsequent install into the user's Applications folder reports `1.2.0-beta.2`, app build 11. The preferences file hash recorded after quitting the prior app remained identical after install/uninstall/reinstall, including the existing goal book. The previous app is retained locally as a recovery copy outside the repository.
- The installed Mac package retains its quarantine attribute and passes strict signature verification. The OS security service reports that first-launch confirmation is awaiting the user; a running installed-app UI and its share-dialog/clipboard interactions are therefore not accepted as verified. No first-launch approval was automated and no security policy was disabled.
- Prepared Beta.2 winget manifests use the actual published x64/ARM64 installer hashes. They have not been submitted to or accepted by the community repository; no winget installation command is advertised as available.

Windows validation remains hosted x64 CI, including UI rendering, installer/upgrade/uninstall and data preservation. ARM64 is packaged and architecture-checked, without native ARM64 execution. Physical Windows hardware, real tray placement across monitors, login/reboot startup and installed Mac share interactions remain outside verified acceptance. See the preceding sections for test details.


## Beta.3 reliability and goal-budget validation (2026-10-05)

- Local macOS: 272 accounting/shared-fixture checks, 12 navigation/state checks, 42 goal attribution/completion/persistence/CSV checks, plus EN/CN light/dark 1080×1440 sharing renders and Vision QR/privacy checks. These use synthetic logs and isolated preferences/backup directories.
- Windows accounting core passes 210 checks on the development Mac; Windows-only path checks and WPF execution are reserved for hosted CI. C# → Swift and Swift → C# portable archives retain exact decimal amounts, budget, bindings and historical price date.
- New fixtures cover legacy-only turns followed by modern responses, same-turn transitions, ambiguous intervals, delayed duplicate counters, malformed complete final lines and pending unfinished writes. Incomplete coverage blocks new completion snapshots; existing frozen amounts are retained.
- Scope checks cover model sample-only cost, whole entity metadata search, goal conversation filtering, CSV/share equality and frozen capture/date context.
- Storage checks cover structurally invalid/null settings/books, invalid-import preservation, byte-exact corrupt-data recovery, rotation, nonnegative budgets, formula-safe numeric negative budget differences and historical completion pricing.
- Version metadata is validated from Common/version.json. Windows CI now installs the checksum-pinned public Beta.2 package before the new installer and checks retained preferences, goal assignment and frozen completion amount, followed by portable execution and uninstall retention.
- Hosted CI, final binary checksums, download-page update and tap acceptance will be recorded after they complete; this local record does not claim those pending checks or physical-device acceptance.
