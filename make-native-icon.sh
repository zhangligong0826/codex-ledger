#!/bin/zsh
# Render the editable Icon Composer document with Apple's own renderer.
# The checked-in ICNS lets contributors build with Command Line Tools alone.
set -euo pipefail
PROJECT_DIR="${0:A:h}"
ICON_TOOL="${CODEX_LEDGER_ICTOOL:-/Applications/Icon Composer.app/Contents/Executables/ictool}"
[[ -x "$ICON_TOOL" ]] || { print -u2 'Install Apple Icon Composer, or set CODEX_LEDGER_ICTOOL to its ictool executable.'; exit 1; }
DOCUMENT="$PROJECT_DIR/Assets/AppIcon.icon"
ICON_SET="$(mktemp -d /private/tmp/codex-ledger-icon.XXXXXX)/AppIcon.iconset"
trap 'rm -rf "${ICON_SET:h}"' EXIT
mkdir -p "$ICON_SET"
"$ICON_TOOL" "$DOCUMENT" --export-image --output-file "$PROJECT_DIR/Assets/AppIcon-1024.png" --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
for RENDITION in Dark ClearLight TintedDark; do
  OPTIONS=()
  if [[ "$RENDITION" == TintedDark ]]; then
    OPTIONS=(--tint-color 0.56 --tint-strength 0.7)
  fi
  "$ICON_TOOL" "$DOCUMENT" --export-image --output-file "$PROJECT_DIR/Assets/AppIcon-Native-$RENDITION.png" --platform macOS --rendition "$RENDITION" --width 1024 --height 1024 --scale 1 $OPTIONS
done
for ICON_SIZE in 16 32 128 256 512; do
  for ICON_SCALE in 1 2; do
    ICON_NAME="icon_${ICON_SIZE}x${ICON_SIZE}"
    [[ "$ICON_SCALE" == 1 ]] || ICON_NAME+='@2x'
    "$ICON_TOOL" "$DOCUMENT" --export-image --output-file "$ICON_SET/$ICON_NAME.png" --platform macOS --rendition Default --width "$ICON_SIZE" --height "$ICON_SIZE" --scale "$ICON_SCALE"
  done
done
/usr/bin/iconutil -c icns "$ICON_SET" -o "$PROJECT_DIR/AppIcon.icns"
print 'Rendered native previews and compatible ICNS from Assets/AppIcon.icon.'
