# Releasing

1. Update `LedgerReleaseVersion` (asset/tag version), numeric `CFBundleShortVersionString` and `CFBundleVersion` in Info.plist. Match the Windows project/package version and the download-page version. For this beta the asset/tag version is `1.2.0-beta.2` and numeric app version is `1.2.0`.
2. Run `zsh test.sh` and `dotnet run --project Windows/Ledger.Tests`; update the actual validation record. Test sharing, date/context scopes, title privacy, unknown costs and completion baselines. No personal logs, exports or screenshots may be committed.
3. Push reviewed source. Require all three macOS CI jobs and the Windows workflow to succeed. Windows validates native x64 execution, synthetic UI, install/upgrade/uninstall and cross-builds ARM64. Physical-device checks are recorded separately.
4. Tag the checked commit `v<LedgerReleaseVersion>`, push the tag, then dispatch **Draft cross-platform release** on that tag. It runs both platforms, requires native Mac icon compilation, produces explicit assets and verifies each producer's checksums before generating a combined CHECKSUMS.txt.
5. Download and verify all six exact assets, review generated views, package contents and release notes. Publish the draft as a **prerelease** for beta versions. Never claim formal Windows signing or Apple notarization for these builds.
6. Update the Homebrew tap version/ZIP SHA after the assets are public. Run style/audit plus isolated install/uninstall. Preserve existing user data.
7. Enable GitHub Pages using Actions and dispatch **Download page** after links have been verified. The card QR always points to the project Pages root, not a version-specific asset. Confirm both language modes and all six download formats at the public endpoint.
8. Generate winget manifests from verified installer hashes with `distribution/make-winget.py`. They remain prepared manifests until accepted by the community repository; do not advertise a winget command prematurely.

Exact binary inventory: universal macOS ZIP and DMG, Windows x64 installer/portable ZIP and Windows ARM64 installer/portable ZIP. `distribution/release-assets.py` rejects missing or additional Codex-Ledger files. Never upload `dist/*` blindly: local development folders can contain older builds.

Formal signing/notarization can be added later. Credentials belong in local keychains or repository secrets, never source, screenshots or logs. Free-beta installation must respect Gatekeeper/SmartScreen/device policy.
