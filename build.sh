#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
OUTPUT_DIR="${CODEX_LEDGER_OUTPUT_DIR:-$PROJECT_DIR/dist}"
BUILD_ARCH="${CODEX_LEDGER_ARCH:-universal}"
STAGING_DIR="$(mktemp -d /private/tmp/codex-ledger-build.XXXXXX)"
STAGED_APP="$STAGING_DIR/Codex Ledger.app"
trap 'rm -rf "$STAGING_DIR"' EXIT
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources" "$PROJECT_DIR/.build/swift-cache" "$OUTPUT_DIR"
SOURCES=("$PROJECT_DIR/Sources/LedgerPricing.swift" "$PROJECT_DIR/Sources/LedgerCore.swift" "$PROJECT_DIR/Sources/LedgerAnalytics.swift" "$PROJECT_DIR/Sources/LedgerDemo.swift" "$PROJECT_DIR/Sources/LedgerStore.swift" "$PROJECT_DIR/Sources/LedgerViews.swift" "$PROJECT_DIR/Sources/Localization.swift" "$PROJECT_DIR/Sources/CodexLedger.swift")
case "$BUILD_ARCH" in
  universal) ARCHS=(arm64 x86_64) ;;
  arm64|x86_64) ARCHS=("$BUILD_ARCH") ;;
  *) print -u2 'CODEX_LEDGER_ARCH must be universal, arm64, or x86_64'; exit 1 ;;
esac
for BUILD_CPU in $ARCHS; do
  xcrun swiftc -O -swift-version 5 -module-cache-path "$PROJECT_DIR/.build/swift-cache" -target "$BUILD_CPU-apple-macosx14.0" $SOURCES \
    -framework AppKit -framework SwiftUI -framework ServiceManagement -lsqlite3 -o "$STAGING_DIR/CodexLedger-$BUILD_CPU"
done
if [[ "$BUILD_ARCH" == universal ]]; then
  lipo -create "$STAGING_DIR/CodexLedger-arm64" "$STAGING_DIR/CodexLedger-x86_64" -output "$STAGED_APP/Contents/MacOS/CodexLedger"
else
  cp "$STAGING_DIR/CodexLedger-$BUILD_ARCH" "$STAGED_APP/Contents/MacOS/CodexLedger"
fi
cp "$PROJECT_DIR/Info.plist" "$STAGED_APP/Contents/Info.plist"
cp "$PROJECT_DIR/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
xattr -cr "$STAGED_APP"
codesign --force --sign - "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PROJECT_DIR/Info.plist")"
ZIP_NAME="Codex-Ledger-$VERSION-macOS-$BUILD_ARCH.zip"
ditto --norsrc --noextattr -c -k --keepParent "$STAGED_APP" "$OUTPUT_DIR/$ZIP_NAME"
ditto --norsrc --noextattr "$STAGED_APP" "$OUTPUT_DIR/Codex Ledger.app"
if [[ "${CODEX_LEDGER_INSTALL:-0}" == 1 ]]; then
  INSTALL_PATH="$HOME/Applications/Codex Ledger.app"
  if [[ -e "$INSTALL_PATH" ]]; then
    INSTALLED_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$INSTALL_PATH/Contents/Info.plist")"
    [[ "$INSTALLED_ID" == local.codexledger.app ]] || { print -u2 'Refusing to overwrite an unrelated app'; exit 1; }
  fi
  mkdir -p "$HOME/Applications"
  ditto --norsrc --noextattr "$STAGED_APP" "$INSTALL_PATH"
  codesign --verify --deep --strict "$INSTALL_PATH"
  print "Installed: $INSTALL_PATH"
fi
print "Built: $OUTPUT_DIR/$ZIP_NAME"
