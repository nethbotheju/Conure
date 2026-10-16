#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
TEST_DIR="$(mktemp -d)"
SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT
chmod 700 "$TEST_DIR"

swift - "$TEST_DIR" <<'SWIFT'
import Foundation
import CryptoKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let key = Curve25519.Signing.PrivateKey()
try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: directory.appendingPathComponent("private-key"))
try Data(key.publicKey.rawRepresentation.base64EncodedString().utf8).write(to: directory.appendingPathComponent("public-key"))
let other = Curve25519.Signing.PrivateKey()
try Data(other.publicKey.rawRepresentation.base64EncodedString().utf8).write(to: directory.appendingPathComponent("wrong-public-key"))
SWIFT
chmod 600 "$TEST_DIR/private-key"
PUBLIC_KEY="$(< "$TEST_DIR/public-key")"
APP="$TEST_DIR/source/Conure.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$TEST_DIR/feed"
if [ "${1:-}" = --install ]; then
  swiftc -swift-version 6 -parse-as-library \
    -F "$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64" -framework Sparkle \
    -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
    "$ROOT/App/Sources/ConureApp/UpdatePolicy.swift" "$ROOT/App/Sources/ConureApp/UpdateStore.swift" \
    "$ROOT/Tests/UpdateHarness/UpdateHarness.swift" -o "$APP/Contents/MacOS/ConureApp"
else
  cp /usr/bin/true "$APP/Contents/MacOS/ConureApp"
fi
ditto "$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" \
  "$APP/Contents/Frameworks/Sparkle.framework"
python3 - "$APP/Contents/Info.plist" "$PUBLIC_KEY" "$TEST_DIR" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({
        'CFBundleIdentifier': 'com.conure.updatertest', 'CFBundleName': 'Conure',
        'ConureFixtureRoot': sys.argv[3],
        'SUEnableAutomaticChecks': False, 'SUAutomaticallyUpdate': False,
        'SUEnableSystemProfiling': False, 'SUAllowsAutomaticUpdates': False,
        'SUSignedFeedFailureExpirationInterval': 0,
        'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True},
        'CFBundleExecutable': 'ConureApp', 'CFBundlePackageType': 'APPL',
        'CFBundleVersion': '1.2.3', 'CFBundleShortVersionString': '1.2.3',
        'LSMinimumSystemVersion': '15.0', 'SUPublicEDKey': sys.argv[2],
        'SUFeedURL': 'https://github.com/nethbotheju/Conure/releases/latest/download/appcast.xml',
        'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True,
    }, output)
PY
codesign --force --sign - "$APP" >/dev/null
hdiutil create -volname ConureUpdateTest -srcfolder "$TEST_DIR/source" -format UDZO \
  "$TEST_DIR/feed/Conure-1.2.3.dmg" >/dev/null
printf 'Test-only release notes. No application will be executed or installed.\n' > "$TEST_DIR/feed/Conure-1.2.3.txt"
"$TOOLS/generate_appcast" --ed-key-file "$TEST_DIR/private-key" --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix 'https://github.com/nethbotheju/Conure/releases/download/v1.2.3/' \
  -o "$TEST_DIR/feed/appcast.xml" "$TEST_DIR/feed"
"$TOOLS/sign_update" --verify --ed-key-file "$TEST_DIR/private-key" "$TEST_DIR/feed/appcast.xml"
swift "$ROOT/scripts/verify-update.swift" "$TEST_DIR/feed/appcast.xml" "$TEST_DIR/feed/Conure-1.2.3.dmg" 1.2.3 "$PUBLIC_KEY"
if [ "${1:-}" = --install ]; then
  python3 - "$TEST_DIR" > "$TEST_DIR/server.log" 2>&1 <<'PY' &
import functools, http.server, pathlib, sys
root = pathlib.Path(sys.argv[1])
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root / 'feed'))
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
(root / 'port').write_text(str(server.server_port))
server.serve_forever()
PY
  SERVER_PID=$!
  for ((attempt=0; attempt<50; attempt++)); do
    if [ -s "$TEST_DIR/port" ]; then break; fi
    sleep 0.1
  done
  test -s "$TEST_DIR/port"
  TARGET="$TEST_DIR/installed/Conure.app"
  for MODE in cancel-early cancel-extract cancel install; do
    rm -rf "$TEST_DIR/installed"
    rm -f "$TEST_DIR/failed" "$TEST_DIR/relaunched" "$TEST_DIR/cancelled"
    mkdir -p "$TEST_DIR/installed"
    ditto "$APP" "$TARGET"
    plutil -replace CFBundleVersion -string 1.0.0 "$TARGET/Contents/Info.plist"
    plutil -replace CFBundleShortVersionString -string 1.0.0 "$TARGET/Contents/Info.plist"
    codesign --force --sign - "$TARGET" >/dev/null
    printf '%s' "$MODE" > "$TEST_DIR/mode"
    "$TARGET/Contents/MacOS/ConureApp" > "$TEST_DIR/harness.log" 2>&1 &
    PID=$!
    for ((attempt=0; attempt<60; attempt++)); do
      if [ -f "$TEST_DIR/failed" ]; then
        echo "error: update harness: $(< "$TEST_DIR/failed")" >&2
        LOG=$(mktemp -t conure-update-harness-log)
        cp "$TEST_DIR/harness.log" "$LOG"
        echo "Diagnostics: $LOG" >&2
        kill "$PID" 2>/dev/null || true
        exit 1
      fi
      if [ "$MODE" = install ] && [ -f "$TEST_DIR/relaunched" ]; then break; fi
      if [ "$MODE" != install ] && [ -f "$TEST_DIR/cancelled" ] && ! kill -0 "$PID" 2>/dev/null; then break; fi
      sleep 1
    done
    if kill -0 "$PID" 2>/dev/null; then
      kill "$PID" 2>/dev/null || true
      echo "error: update harness timed out in $MODE mode (state: $(< "$TEST_DIR/last-state"))" >&2
      LOG=$(mktemp -d -t conure-update-harness-logs)
      cp "$TEST_DIR/harness.log" "$TEST_DIR/server.log" "$LOG/"
      echo "Diagnostics: $LOG" >&2
      exit 1
    fi
    wait "$PID"
    if [ "$MODE" = install ]; then
      test -f "$TEST_DIR/relaunched"
      test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$TARGET/Contents/Info.plist")" = 1.2.3
    else
      sleep 2
      test ! -f "$TEST_DIR/relaunched"
      test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$TARGET/Contents/Info.plist")" = 1.0.0
    fi
    codesign --verify --deep --strict "$TARGET"
  done
  echo 'Disposable application cancellation, replacement, and relaunch tests passed.'
fi
if swift "$ROOT/scripts/verify-update.swift" "$TEST_DIR/feed/appcast.xml" "$TEST_DIR/feed/Conure-1.2.3.dmg" 1.2.3 \
    "$(< "$TEST_DIR/wrong-public-key")" >/dev/null 2>&1; then
  echo 'error: accepted an archive signed by the wrong publisher' >&2
  exit 1
fi
printf 'tampered' >> "$TEST_DIR/feed/Conure-1.2.3.dmg"
if swift "$ROOT/scripts/verify-update.swift" "$TEST_DIR/feed/appcast.xml" "$TEST_DIR/feed/Conure-1.2.3.dmg" 1.2.3 \
    "$PUBLIC_KEY" >/dev/null 2>&1; then
  echo 'error: accepted a tampered archive' >&2
  exit 1
fi
python3 - "$TEST_DIR/feed/appcast.xml" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
path.write_bytes(path.read_bytes().replace(b'Test-only', b'Tampered!'))
PY
if "$TOOLS/sign_update" --verify --ed-key-file "$TEST_DIR/private-key" "$TEST_DIR/feed/appcast.xml" >/dev/null 2>&1; then
  echo 'error: accepted a tampered feed' >&2
  exit 1
fi
echo 'Update signing tests passed: valid feed/archive, wrong key, tampered archive, tampered feed.'
