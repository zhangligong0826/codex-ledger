# Releasing

1. Update versions in `Info.plist` and notes in `CHANGELOG.md`.
2. Run tests, `CODEX_LEDGER_NATIVE_ICON=required zsh build.sh` with initialized Xcode 26+, `CODEX_LEDGER_NATIVE_ICON=required zsh package.sh`, and native UI checks in `QA.md`. Verify the extracted app with `zsh verify-native-icon.sh`; a release must retain the layered icon catalog.
3. Commit reviewed source, tag `v<version>`, push main/tag. Dispatch the release workflow **on the tag**. It creates a draft release after checking the version and packages.
4. Review assets, notes and CI; publish the draft. Never claim notarization for ad-hoc builds.
5. Update version and universal ZIP SHA-256 in `zhangligong0826/homebrew-tap/Casks/codex-ledger.rb` after assets are public. Run Homebrew style/audit and isolated install/uninstall.

A local release may use `gh release create` with the verified tag, actual notes file and ZIP/DMG/CHECKSUMS.txt from `dist/`. Source archives are automatic. Download both binaries and run `shasum -a 256 -c CHECKSUMS.txt`.

If Developer ID becomes available, sign/notarize/staple before packaging and hash the final assets. Do not remove quarantine, disable Gatekeeper or embed credentials.
