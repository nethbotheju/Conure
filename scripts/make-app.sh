#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build/release"
APP="$ROOT/dist/Conure.app"
VERSION="${1:-0.1.0}"

echo "Building release binaries…"
swift build -c release --package-path "$ROOT"

echo "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"

cp "$BUILD_DIR/ConureApp" "$APP/Contents/MacOS/ConureApp"
cp "$BUILD_DIR/conure" "$APP/Contents/Helpers/conure"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Conure</string>
    <key>CFBundleDisplayName</key>
    <string>Conure</string>
    <key>CFBundleIdentifier</key>
    <string>com.conure.app</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>ConureApp</string>
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
