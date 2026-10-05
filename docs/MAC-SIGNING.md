# Mac signing, notarization and “Move to Trash” alerts

The published Beta.4 has an intact ad-hoc signature, but no Developer ID certificate or Apple notarization ticket. Passing `codesign --verify` checks integrity; it does not establish Gatekeeper trust. On the development Mac, `spctl --assess` rejected this build, `stapler validate` found no ticket and the keychain contained zero valid code-signing identities. A warning offering Move to Trash can therefore occur without a corrupted download. The exact alert wording still matters; a malware warning must not be treated as this signing case.

Sources: [Apple safe opening instructions](https://support.apple.com/102445), [Developer ID](https://developer.apple.com/developer-id/), [Apple notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## A local development build

For the maintainer's own computer, build the trusted source using the installed Apple toolchain. Quit the running Ledger app before replacing it:

```sh
CODEX_LEDGER_NATIVE_ICON=required CODEX_LEDGER_INSTALL=1 zsh build.sh
open "$HOME/Applications/Codex Ledger.app"
```

The installer creates a fresh bundle and keeps the previous app in a private sibling recovery directory. It does not change preferences or goal books. This is a locally produced development app, not a notarized public installer. Downloaded release packages retain their quarantine attribute. Do not distribute this local workaround as a claim that public downloads are trusted; Homebrew updates still need properly signed releases.

## A public Developer ID release

An Apple Developer Program account with an authorized Developer ID Application certificate and its private key is required. Create/import the certificate using Xcode or Keychain on your own computer. Do not paste passwords, certificate private keys or API keys into chat or Git.

1. Check available certificate names with `security find-identity -v -p codesigning`.
2. Create a local notarytool Keychain profile. For Apple ID authentication, `xcrun notarytool store-credentials ledger-release` prompts for credentials in the local terminal. For App Store Connect team API authentication, use its `--key`, `--key-id` and `--issuer` options with a private local key file. The credentials must be validated by Apple before proceeding.
3. Select a new release version; never overwrite already-published Beta.4 assets or their checksums.
4. Build, notarize, staple, package and assess:

```sh
export CODEX_LEDGER_SIGNING_MODE=developer-id
export CODEX_LEDGER_SIGNING_IDENTITY='Developer ID Application: YOUR CERTIFICATE NAME (TEAMID)'
export CODEX_LEDGER_NOTARY_PROFILE=ledger-release
CODEX_LEDGER_NATIVE_ICON=required zsh build.sh
zsh distribution/notarize-mac.sh
CODEX_LEDGER_NATIVE_ICON=required zsh package.sh
```

The app uses hardened runtime and a secure signing timestamp. The signed universal ZIP is submitted to Apple; only an Accepted result proceeds to stapling and Gatekeeper assessment. The ZIP is recreated with the app's ticket. The DMG is signed, submitted, stapled, assessed and verified separately. SHA-256 is computed only after both containers are final. Failed signing, rejection, missing tickets or failed assessments stop packaging; there is no unsigned fallback in Developer ID mode.

## GitHub release credentials

Configure these repository Actions secrets through your own GitHub settings. Use a certificate and team API key authorized for this project, and limit repository access accordingly:

- `MAC_CERTIFICATE_P12_BASE64`: exported Developer ID Application certificate plus private key, encoded as base64.
- `MAC_CERTIFICATE_PASSWORD`: export password for the PKCS#12 file.
- `MAC_SIGNING_IDENTITY`: full Developer ID Application certificate name.
- `APPLE_NOTARY_PRIVATE_KEY`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID`: a team App Store Connect API key with notarization permission. Individual API keys are not handled by this workflow.

The workflow imports into an isolated temporary keychain on the hosted Mac and removes it and temporary key files on completion. Avoid echoing secrets or enabling shell tracing. The default `developer-id` release mode requires all secrets and stops before building when missing. `unsigned-beta` remains an explicit testing option and adds a warning to release notes; it does not solve Gatekeeper rejection.

After a genuine notarized release, test a fresh browser/Homebrew download on a separate Mac, retain quarantine, verify the app/DMG ticket and Gatekeeper assessment, then check launch and update behavior. Existing Beta.4 assets remain unnotarized until superseded by a new signed version.
