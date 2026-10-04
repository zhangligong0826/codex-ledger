# 1.2.0-beta.3 reliability and goal accounting plan

Date: 2026-10-05 (Asia/Shanghai). The owner delegated routine design choices. Preserve local-only operation, existing preferences and goal books, native Mac UI/icon, current Windows tray architecture, and existing published assets.

## 1. Accounting integrity
- Reconcile legacy cumulative usage and modern response records by turn. Preserve legacy-only turns; replace fully covered duplicate legacy turns; retain an explicit completeness warning when overlap cannot be established without guessing.
- Treat malformed complete lines, I/O failures and ambiguous reconciliation separately from unknown model prices. Pending trailing writes remain retryable and are not corruption.
- Block goal completion when lifetime records are incomplete. Preserve previously saved completion snapshots. Show coverage warnings consistently in both apps, exports and cards.
- Acceptance: mixed-format transition and overlap fixtures agree on Swift/C# Decimal totals; incomplete source cannot become a definitive completion amount.

## 2. One accounting scope
- Entity search finds whole projects/conversations. Model search selects model samples, not complete mixed-model turns.
- Share, UI summaries and CSV consume the same selected records, including goal-detail search and no-match cases. Completion CSV uses its frozen price date.
- Acceptance: filtered UI/card/CSV quantities reconcile; clearing search and back navigation retain explicit scope.

## 3. Time and price provenance
- Store a captured timestamp and exact selected interval in sharing snapshots; derive selected and monthly activity from that same timestamp.
- Show calendar dates/year, completion date and completion price date on cards. Preserve 1080x1440 output, QR and privacy defaults.
- Acceptance: midnight/DST/frozen-date regressions; localized large/completed cards remain readable and QR-decodable.

## 4. Recovery and structural validation
- Validate Windows preference and goal-book structure before use. Loading/errors never display unknown monthly use as zero.
- Introduce portable versioned goal-book backup JSON, with ISO dates and Decimal money, shared across platforms. Import replaces only after validation and confirmation and first saves a recovery copy.
- Keep rotating local recovery copies before mutations; provide export/import in settings. Normalize source aliases/case and migrate the currently selected existing book without deleting its original.
- Acceptance: cross-platform roundtrip, invalid/null schema rejection, rollback preservation, path aliases and historical completion retention.

## 5. Goal-first product presentation
- Windows goal rows prioritize frozen completion/lifetime money; date-range consumption is secondary.
- Add optional USD goal budgets with remaining/over-budget status, and cost/token heatmap mode. Unknown price coverage remains visible; budget arithmetic is an estimate.
- Acceptance: completed/no-today-use goal remains informative; bilingual and three appearances, long names, sub-cent and large totals.

## 6. Installation and maintenance
- Bring the existing Windows tray instance forward on repeated launch without creating duplicate processes.
- Add a clear user-initiated update/download entry; retain fully offline background operation.
- CI exercises prior Beta.2 -> Beta.3 upgrade using isolated app/data state and verifies real book/settings retention, plus existing portable/uninstall checks.
- Centralize release version validation and keep all published old assets immutable. Continue ad-hoc/unsigned beta distribution; formal publisher signing requires owner identity/account credentials and is not fabricated.

## 7. Validation and delivery
- Run accounting/store/goal/share regression suites and both client builds. Use synthetic data only for previews/tests; never commit personal logs/titles/paths.
- Require three Mac CI environments and Windows hosted execution/installer tests before publishing a replacement prerelease. Do not describe ARM64 cross-builds as native execution or generated UI previews as physical-device acceptance.
- Update release notes, docs, tap/checksums/download page only against verified new artifacts. If network/approval/physical-device limitations prevent an action, preserve a reviewable local build and state the exact limit.
- Deliver a Chinese change report listing actual completed work, evidence, artifacts, upgrade/restore instructions and remaining limits. No security checks are disabled.
