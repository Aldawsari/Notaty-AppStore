#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-1.0}"
APP_NAME="Notaty"
BUNDLE_ID="com.notaty.app"
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
APP="$DIST/${APP_NAME}-${VERSION}.app"

if [[ -e "$APP" ]]; then
  echo "Error: $APP already exists. Bump the version." >&2
  exit 1
fi

echo "Building release binary..."
cd "$ROOT"
swift build -c release

BIN="$ROOT/.build/release/${APP_NAME}"
if [[ ! -x "$BIN" ]]; then
  echo "Error: release binary not found at $BIN" >&2
  exit 1
fi

echo "Assembling ${APP}..."
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/${APP_NAME}"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "Built ${APP}"
