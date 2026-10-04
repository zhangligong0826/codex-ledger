Beta.2 fixes unreadable goal-book handling: goal-dependent amounts become unknown and sharing/export is disabled instead of producing a zero-cost goal card. Independent source usage remains available. CSV is frozen before the save dialog, and share snapshots own immutable daily data. Beta.1 assets remain unchanged.

Codex Ledger 1.2.0-beta.2 brings native macOS menu-bar and Windows system-tray accounting together.

- Privacy-first 1080 × 1440 share cards with estimated USD cost, tokens, 30-day heatmap, completion snapshot and installation QR. Names and paths are hidden by default; preview before sharing.
- Capture the current app content, copy/save PNG, or export scoped CSV.
- Windows 11 x64 and ARM64 self-contained installers and portable ZIPs. Includes goals, projects, conversations, turns, models, search, bilingual UI and system/light/dark appearance.
- Shared offline price catalog and synthetic accounting fixtures; logs and title metadata are read-only. Costs are API estimates, not subscription bills.

Install: https://zhangligong0826.github.io/codex-ledger/

Mac: open the universal DMG and drag Codex Ledger to Applications, or use `brew install --cask zhangligong0826/tap/codex-ledger` once the tap has been updated for this release.
Windows: download the installer for your architecture. Installation is per-user; no separate .NET installation is required. Portable ZIPs are also available.

This free beta is ad-hoc signed on macOS and unsigned on Windows, without Apple notarization. Follow the documented first-launch steps and your device's policy. Never disable system security checks to install it.

Validation: 247 macOS accounting/goal/navigation checks plus synthetic share renders and QR/privacy checks on all three Mac CI environments; 87 Windows x64 hosted-runner accounting checks, localized UI renders, clipboard/save checks, portable execution and installer/upgrade/uninstall/data-retention tests. Windows ARM64 is cross-built, without native ARM64 execution. Physical Windows hardware acceptance and installed Mac share-dialog/clipboard interaction are not verified. See QA.md for the full evidence and limits.

SHA-256 checksums for all six binary assets are in CHECKSUMS.txt. Existing logs, preferences and goal attribution are preserved by upgrades; uninstall preserves user data.
