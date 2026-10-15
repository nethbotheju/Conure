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

"$ROOT/scripts/verify-app.sh" "$APP" "$VERSION" stable

STAGING="$(mktemp -d)"
MOUNT="$(mktemp -d)"
MOUNTED=false
cleanup() {
  if [ "$MOUNTED" = true ]; then hdiutil detach "$MOUNT" >/dev/null; fi
  rm -rf "$STAGING" "$MOUNT"
}
trap cleanup EXIT

cp -R "$APP" "$STAGING/Conure.app"
ln -s /Applications "$STAGING/Applications"

echo "Creating ${DMG}…"
rm -f "$DMG"
hdiutil create -volname "Conure" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG" >/dev/null
MOUNTED=true
"$ROOT/scripts/verify-app.sh" "$MOUNT/Conure.app" "$VERSION" stable
diff -qr "$APP" "$MOUNT/Conure.app"
test "$(readlink "$MOUNT/Applications")" = /Applications
hdiutil detach "$MOUNT" >/dev/null
MOUNTED=false

echo
echo "Done: $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
