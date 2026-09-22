#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Conure.app"
VERSION="${1:-0.1.0}"
DMG="$ROOT/dist/Conure-$VERSION.dmg"

if [ ! -d "$APP" ]; then
  echo "error: $APP not found — run make-app.sh first" >&2
  exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/Conure.app"
ln -s /Applications "$STAGING/Applications"

echo "Creating ${DMG}…"
rm -f "$DMG"
hdiutil create -volname "Conure" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

echo
echo "Done: $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
