#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build/release"
VERSION="${1:-0.1.0}"
VARIANT="${2:-stable}"
case "$VARIANT" in
  stable)
    APP_NAME="Conure"
    BUNDLE_ID="com.conure.app"
    ICON="AppIcon.icns"
    ;;
  dev)
    APP_NAME="Conure Dev"
    BUNDLE_ID="com.conure.app.dev"
    ICON="AppIcon-Dev.icns"
    ;;
  *)
    echo "error: unknown app variant: $VARIANT (expected stable or dev)" >&2
    exit 1
    ;;
esac
APP="$ROOT/dist/$APP_NAME.app"
if [ ! -f "$ROOT/App/Resources/$ICON" ]; then
  echo "error: missing icon: $ICON" >&2
  exit 1
fi

echo "Building release binaries…"
swift build -c release --package-path "$ROOT"

echo "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"

cp "$BUILD_DIR/ConureApp" "$APP/Contents/MacOS/ConureApp"
cp "$BUILD_DIR/conure" "$APP/Contents/Helpers/conure"

mkdir -p "$APP/Contents/Resources"
cp "$ROOT/App/Resources/$ICON" "$APP/Contents/Resources/$ICON"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>ConureApp</string>
    <key>CFBundleIconFile</key>
    <string>${ICON%.icns}</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
EOF

echo "Ad-hoc codesigning…"
codesign --force --sign - "$APP/Contents/Helpers/conure"
codesign --force --sign - "$APP"

echo
echo "Done: $APP"
echo "Run it with: open $APP"
