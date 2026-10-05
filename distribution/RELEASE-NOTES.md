Codex Ledger 1.2.0-beta.4 (build 16) centers the ledger on the cost of completing an outcome.

- Connected goal creation, work selection and attribution preview. Selected historical work is fixed to explicit turns; dated and ongoing project/chat rules remain available. Preview shows the actual transferred turns, cost and displaced goals; attribution changes can be undone.
- Scoped accounting coverage separates loading, record problems and unknown pricing. Related or unscoped errors prevent a new completion snapshot; unknown prices retain unpriced usage without pretending it costs zero.
- Version 2 goal books preserve immutable completion history, membership, exact Decimal amounts, record coverage and price catalog identity. New ongoing rules stop accepting newly started work at completion. Reopening preserves history and does not silently resume rules. Legacy rules keep their original behavior.
- Independent menu-bar/dashboard dates, restored navigation/search/filter/sort/scroll state, daily heatmap filtering and aligned CSV/share contexts. Completed goals emphasize frozen cost while selected-date and post-completion response usage remain separate.
- Compact 300-point Mac overview and bounded detail windows, interactive token/cost ring and heatmap, standard editing/navigation shortcuts, bilingual appearance support and visible sharing scope. Share the last published snapshot during refresh; CSV does not wait for the heatmap.
- Raw v1 recovery copies and separate atomic v2 storage. Cross-platform portable backups use exact decimal strings. Unknown or damaged books are retained and writes stop.

Download: https://zhangligong0826.github.io/codex-ledger/

Mac: universal DMG/ZIP or `brew install --cask zhangligong0826/tap/codex-ledger`. Windows 11: self-contained x64/ARM64 installers and portable ZIPs.

API cost estimates are not subscription bills. Logs, bookkeeping and card rendering stay local. The release workflow records Mac signing/notarization status below. Windows builds are unsigned; follow system first-launch confirmations. Do not disable system security protections.

Verification evidence is recorded in QA.md. Windows runtime/UI/install/upgrade checks run on hosted x64 CI; ARM64 is built and architecture checked, without native ARM64 execution. Physical Windows devices, monitor placement and login/reboot checks remain outside acceptance. All six binary hashes are listed in CHECKSUMS.txt. Older releases remain unchanged.
