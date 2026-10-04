#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
OUTPUT_DIR="${CODEX_LEDGER_OUTPUT_DIR:-$PROJECT_DIR/dist}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PROJECT_DIR/Info.plist")"
ZIP_NAME="Codex-Ledger-$VERSION-macOS-universal.zip"
DMG_NAME="Codex-Ledger-$VERSION-macOS-universal.dmg"
[[ -f "$OUTPUT_DIR/$ZIP_NAME" ]] || { print -u2 'Run zsh build.sh with the default universal architecture first.'; exit 1; }
STAGING_DIR="$(mktemp -d /private/tmp/codex-ledger-dmg.XXXXXX)"
trap 'rm -rf "$STAGING_DIR"' EXIT
# Package the verified archive in a physical temporary directory. File providers
# can add Finder metadata to a workspace .app after it was built.
ditto -x -k "$OUTPUT_DIR/$ZIP_NAME" "$STAGING_DIR"
APP="$STAGING_DIR/Codex Ledger.app"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$APP_VERSION" == "$VERSION" ]] || { print -u2 'Build version does not match Info.plist.'; exit 1; }
APP_ARCHS=" $(lipo -archs "$APP/Contents/MacOS/CodexLedger") "
[[ "$APP_ARCHS" == *' arm64 '* && "$APP_ARCHS" == *' x86_64 '* ]] || { print -u2 'Packaging requires both arm64 and x86_64.'; exit 1; }
codesign --verify --deep --strict "$APP"
if [[ -f "$APP/Contents/Resources/Assets.car" || "${CODEX_LEDGER_NATIVE_ICON:-auto}" == required ]]; then
  zsh "$PROJECT_DIR/verify-native-icon.sh" "$APP"
fi
ln -s /Applications "$STAGING_DIR/Applications"
cp "$PROJECT_DIR/LICENSE" "$STAGING_DIR/LICENSE.txt"
cp "$PROJECT_DIR/README.zh-CN.md" "$STAGING_DIR/README.zh-CN.md"
cp "$PROJECT_DIR/README.md" "$STAGING_DIR/README.md"
cp "$PROJECT_DIR/PRICING.md" "$STAGING_DIR/PRICING.md"
hdiutil create -ov -format UDZO -volname "Codex Ledger $VERSION" -srcfolder "$STAGING_DIR" "$OUTPUT_DIR/$DMG_NAME"
hdiutil verify "$OUTPUT_DIR/$DMG_NAME"
(cd "$OUTPUT_DIR" && shasum -a 256 "$ZIP_NAME" "$DMG_NAME" > CHECKSUMS.txt)
print "Packaged: $OUTPUT_DIR/$DMG_NAME"
