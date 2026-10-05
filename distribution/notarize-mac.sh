#!/bin/zsh
# Submit the signed ZIP, attach its Apple ticket to the app, then rebuild the ZIP.
# No Gatekeeper/quarantine preferences are changed. Never amend published assets.
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
OUTPUT_DIR="${CODEX_LEDGER_OUTPUT_DIR:-$PROJECT_DIR/dist}"
PROFILE="${CODEX_LEDGER_NOTARY_PROFILE:?Set an existing notarytool Keychain profile}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print LedgerReleaseVersion' "$PROJECT_DIR/Info.plist")"
ZIP="$OUTPUT_DIR/Codex-Ledger-$VERSION-macOS-universal.zip"
[[ -f "$ZIP" ]] || { print -u2 'Build the Developer ID signed universal ZIP first.'; exit 1; }
STAGING_DIR="$(mktemp -d /private/tmp/codex-ledger-notary.XXXXXX)"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto -x -k "$ZIP" "$STAGING_DIR"
APP="$STAGING_DIR/Codex Ledger.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print LedgerReleaseVersion' "$APP/Contents/Info.plist")" == "$VERSION" ]] || { print -u2 'ZIP release version mismatch'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")" == "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PROJECT_DIR/Info.plist")" ]] || { print -u2 'ZIP build mismatch'; exit 1; }
codesign --verify --deep --strict "$APP"
DETAILS="$(codesign -d --verbose=4 "$APP" 2>&1)"
[[ "$DETAILS" == *'Authority=Developer ID Application:'* && "$DETAILS" == *'runtime'* ]] || { print -u2 'Refusing to notarize an ad-hoc build. Developer ID with hardened runtime is required.'; exit 1; }
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait --output-format json > "$STAGING_DIR/result.json"
python3 - "$STAGING_DIR/result.json" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
if result.get('status')!='Accepted':
    sys.exit('Apple notarization was not accepted. Inspect the notarytool submission log; packages remain unpublished.')
print('Apple notarization accepted:', result['id'])
PY
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
# Stapling changes archive bytes. Recreate before checksums and DMG packaging.
ditto --norsrc --noextattr -c -k --keepParent "$APP" "$STAGING_DIR/notarized.zip"
mv "$STAGING_DIR/notarized.zip" "$ZIP"
print "Notarized and stapled: $ZIP"
