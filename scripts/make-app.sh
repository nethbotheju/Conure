#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build/release"
VERSION="${1:-0.1.0}"
VARIANT="${2:-stable}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "error: invalid version: $VERSION" >&2
  exit 1
fi
SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
SOURCE_REF="${CONURE_BUILD_REF:-${GITHUB_REF:-$(git -C "$ROOT" symbolic-ref -q HEAD || echo detached)}}"
BUILD_URL=""
if [ "${GITHUB_ACTIONS:-}" = true ]; then
  BUILD_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
fi
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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Frameworks"

cp "$BUILD_DIR/ConureApp" "$APP/Contents/MacOS/ConureApp"
cp "$BUILD_DIR/conure" "$APP/Contents/Helpers/conure"
ditto "$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" \
    "$APP/Contents/Frameworks/Sparkle.framework"

mkdir -p "$APP/Contents/Resources"
cp "$ROOT/App/Resources/$ICON" "$APP/Contents/Resources/$ICON"
cp "$ROOT/.build/artifacts/sparkle/Sparkle/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"

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

PLIST="$APP/Contents/Info.plist"
if [ "$VARIANT" = stable ] && [ -n "${CONURE_UPDATE_PUBLIC_KEY:-}" ]; then
  python3 -c 'import base64, os; assert len(base64.b64decode(os.environ["CONURE_UPDATE_PUBLIC_KEY"], validate=True)) == 32'
  plutil -insert SUPublicEDKey -string "$CONURE_UPDATE_PUBLIC_KEY" "$PLIST"
  plutil -insert SUFeedURL -string "https://github.com/nethbotheju/Conure/releases/latest/download/appcast.xml" "$PLIST"
elif [ "${CONURE_REQUIRE_UPDATE_KEY:-false}" = true ] && [ "$VARIANT" = stable ]; then
  echo "error: CONURE_UPDATE_PUBLIC_KEY must be configured for stable releases" >&2
  exit 1
fi
plutil -insert SUEnableAutomaticChecks -bool false "$PLIST"
plutil -insert SUAutomaticallyUpdate -bool false "$PLIST"
plutil -insert SUAllowsAutomaticUpdates -bool false "$PLIST"
plutil -insert SUEnableSystemProfiling -bool false "$PLIST"
plutil -insert SURequireSignedFeed -bool true "$PLIST"
plutil -insert SUVerifyUpdateBeforeExtraction -bool true "$PLIST"
plutil -insert SUSignedFeedFailureExpirationInterval -integer 0 "$PLIST"
plutil -insert ConureSourceCommit -string "$SOURCE_COMMIT" "$PLIST"
plutil -insert ConureSourceRef -string "$SOURCE_REF" "$PLIST"
plutil -insert ConureBuildURL -string "$BUILD_URL" "$PLIST"

echo "Ad-hoc codesigning…"
codesign --force --sign - "$APP/Contents/Helpers/conure"
codesign --force --sign - "$APP"
"$ROOT/scripts/verify-app.sh" "$APP" "$VERSION" "$VARIANT"

echo
echo "Done: $APP"
echo "Run it with: open $APP"
