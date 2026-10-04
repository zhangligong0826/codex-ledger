#!/bin/zsh
# Verify the compiled app contains layered resources, not only flattened PNGs.
set -euo pipefail
APP="${1:?Pass the path to the built .app}"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIconName' "$APP/Contents/Info.plist")" == AppIcon ]]
[[ -s "$APP/Contents/Resources/AppIcon.icns" ]]
CATALOG="$APP/Contents/Resources/Assets.car"
xcrun assetutil --validate-file "$CATALOG"
ICON_INFO="$(mktemp /private/tmp/codex-ledger-icon-info.XXXXXX)"
trap 'rm -f "$ICON_INFO"' EXIT
xcrun assetutil --info "$CATALOG" > "$ICON_INFO"
# Read the entire output to avoid a SIGPIPE with set -o pipefail.
for REQUIRED_ASSET in IconImageStack IconGroup NSAppearanceNameAqua NSAppearanceNameDarkAqua ISAppearanceTintable; do
  [[ "$(/usr/bin/grep -c "\"$REQUIRED_ASSET\"" "$ICON_INFO")" -gt 0 ]]
done
print 'Verified layered native app icon with light, dark and tintable resources.'
