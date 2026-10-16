#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?stable version required}"
NOTES="${2:?release notes file required}"
if ! [[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "error: only stable semantic versions can be published to the update feed" >&2
  exit 1
fi
: "${SPARKLE_PRIVATE_KEY:?configure the repository update-signing secret}"
: "${CONURE_UPDATE_PUBLIC_KEY:?configure the repository update-signing public key}"
TOOLS="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
DMG="$ROOT/dist/Conure-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp "$DMG" "$STAGING/"
cp "$NOTES" "$STAGING/Conure-$VERSION.txt"
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$TOOLS/generate_appcast" --ed-key-file - \
  --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix "https://github.com/nethbotheju/Conure/releases/download/v$VERSION/" \
  --link "https://github.com/nethbotheju/Conure/releases/tag/v$VERSION" \
  -o "$STAGING/appcast.xml" "$STAGING"
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$TOOLS/sign_update" --verify --ed-key-file - "$STAGING/appcast.xml"
swift "$ROOT/scripts/verify-update.swift" "$STAGING/appcast.xml" "$DMG" "$VERSION" "$CONURE_UPDATE_PUBLIC_KEY"
cp "$STAGING/appcast.xml" "$ROOT/dist/appcast.xml"
