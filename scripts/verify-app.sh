#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?app path required}"
VERSION="${2:?version required}"
VARIANT="${3:-stable}"
case "$VARIANT" in
  stable) BUNDLE_ID="com.conure.app"; APP_NAME="Conure"; ICON="AppIcon" ;;
  dev) BUNDLE_ID="com.conure.app.dev"; APP_NAME="Conure Dev"; ICON="AppIcon-Dev" ;;
  *) echo "error: unknown app variant: $VARIANT" >&2; exit 1 ;;
esac
PLIST="$APP/Contents/Info.plist"
value() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }

plutil -lint "$PLIST"
test "$(value CFBundleIdentifier)" = "$BUNDLE_ID"
test "$(value CFBundleDisplayName)" = "$APP_NAME"
test "$(value CFBundleIconFile)" = "$ICON"
test "$(value CFBundleShortVersionString)" = "$VERSION"
test "$(value CFBundleVersion)" = "$VERSION"
test "$(value ConureSourceCommit)" = "$(git -C "$ROOT" rev-parse HEAD)"
test -n "$(value ConureSourceRef)"
if [ -n "${CONURE_BUILD_REF:-${GITHUB_REF:-}}" ]; then
  test "$(value ConureSourceRef)" = "${CONURE_BUILD_REF:-$GITHUB_REF}"
fi
if [ "${GITHUB_ACTIONS:-}" = true ]; then
  test "$(value ConureBuildURL)" = "${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
fi
test -x "$APP/Contents/MacOS/ConureApp"
test -x "$APP/Contents/Helpers/conure"
test -f "$APP/Contents/Resources/$ICON.icns"
codesign --verify --strict "$APP/Contents/Helpers/conure"
codesign --verify --deep --strict "$APP"
"$APP/Contents/Helpers/conure" --version
