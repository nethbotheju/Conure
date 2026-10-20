#!/bin/bash
set -euo pipefail

MODE="${CONURE_SIGNING_MODE:-adhoc}"
case "$MODE" in
  adhoc|developer-id) ;;
  *) echo "error: CONURE_SIGNING_MODE must be adhoc or developer-id" >&2; exit 1 ;;
esac

CREDENTIALS=(
  CONURE_SIGNING_IDENTITY
  CONURE_APPLE_TEAM_ID
  CONURE_DEVELOPER_ID_P12_BASE64
  CONURE_DEVELOPER_ID_P12_PASSWORD
  CONURE_NOTARY_KEY_ID
  CONURE_NOTARY_ISSUER_ID
  CONURE_NOTARY_PRIVATE_KEY
)
CONFIGURED=0
MISSING=()
for name in "${CREDENTIALS[@]}"; do
  if [ -n "${!name:-}" ]; then
    CONFIGURED=$((CONFIGURED + 1))
  else
    MISSING+=("$name")
  fi
done

if [ "$CONFIGURED" -gt 0 ] && [ "$CONFIGURED" -lt "${#CREDENTIALS[@]}" ]; then
  echo "error: partial Apple signing configuration; missing: ${MISSING[*]}. No ad-hoc fallback. See validation/signing-and-notarization.md" >&2
  exit 1
fi
if [ "$MODE" = developer-id ] || [ "$CONFIGURED" -gt 0 ]; then
  echo "error: Developer ID signing and notarization are disabled pending validation with project-controlled credentials. See validation/signing-and-notarization.md" >&2
  exit 1
fi

echo "Apple signing: ad-hoc (no Apple credentials required)."
