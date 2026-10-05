#!/bin/zsh
# Local builds remain possible without a paid certificate. Public release builds
# must opt into Developer ID; a failed formal signature never falls back to ad-hoc.
set -euo pipefail
APP="${1:?Pass the staged app path}"
SIGNING_MODE="${CODEX_LEDGER_SIGNING_MODE:-local}"
case "$SIGNING_MODE" in
  local)
    codesign --force --sign - "$APP"
    ;;
  developer-id)
    IDENTITY="${CODEX_LEDGER_SIGNING_IDENTITY:?Set a Developer ID Application identity}"
    [[ "$IDENTITY" == 'Developer ID Application: '* ]] || { print -u2 'A Developer ID Application certificate is required.'; exit 1; }
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    DETAILS="$(codesign -d --verbose=4 "$APP" 2>&1)"
    [[ "$DETAILS" == *'Authority=Developer ID Application:'* && "$DETAILS" == *'runtime'* && "$DETAILS" != *'TeamIdentifier=not set'* ]] || { print -u2 'Developer ID / hardened runtime verification failed.'; exit 1; }
    ;;
  *) print -u2 'CODEX_LEDGER_SIGNING_MODE must be local or developer-id'; exit 1 ;;
esac
codesign --verify --deep --strict "$APP"
