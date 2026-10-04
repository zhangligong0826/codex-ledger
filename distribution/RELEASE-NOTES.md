Codex Ledger 1.2.0-beta.3 improves the reliability of local goal-cost accounting on macOS and Windows.

- Mixed-format log reconciliation and explicit incomplete-record warnings; incomplete sources cannot freeze a goal completion amount.
- Consistent project/conversation/model search scope across summaries, CSV and share cards. Captured date ranges, timezone and historical completion price dates are retained.
- Optional USD goal budgets, cost/token heatmap intensity and prominent frozen completion amounts.
- Validated goal-book backup/import with recovery copies and exact-decimal portable archives.
- Windows repeated launch opens the existing instance. Genuine Beta.2 upgrade tests preserve preferences, assignments and frozen completion costs.

Download: https://zhangligong0826.github.io/codex-ledger/

Mac: universal DMG/ZIP or `brew install --cask zhangligong0826/tap/codex-ledger`. Windows 11: self-contained x64/ARM64 installers and portable ZIPs.

API cost estimates are not subscription bills. Data and share rendering stay local. This free beta is ad-hoc signed on macOS and unsigned on Windows, without Apple notarization; follow system first-launch confirmations. Do not disable system security protections.

Verification details are in QA.md. Windows runtime/UI/install checks use hosted x64 CI; ARM64 is cross-built, without native ARM64 execution. Physical Windows device acceptance and installed Mac share-dialog interaction remain unverified. All six binary SHA-256 values are in CHECKSUMS.txt.
