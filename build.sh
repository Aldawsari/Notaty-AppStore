#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-1.0}"
APP_NAME="NotatyAppstore"
BUNDLE_ID="com.aldawsari.NotatyAppstore"
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
APP="$DIST/${APP_NAME}-${VERSION}.app"
ENTITLEMENTS="$ROOT/NotatyAppstore.entitlements"

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
mkdir -p "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/${APP_NAME}"
if [[ -f "$ROOT/AppIcon.icns" ]]; then
  cp "$ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

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
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Notaty needs Screen Recording permission to capture regions of the screen for OCR.</string>
</dict>
</plist>
PLIST

CERT_NAME="${APPSTORE_SIGN_IDENTITY:-Apple Distribution}"

if security find-certificate -c "$CERT_NAME" 2>/dev/null | grep -q "$CERT_NAME"; then
  echo "Signing ${APP} with ${CERT_NAME}..."
  codesign --force --deep --sign "$CERT_NAME" --timestamp --entitlements "$ENTITLEMENTS" "$APP"
else
  echo "Ad-hoc signing ${APP} for local validation..."
  codesign --force --deep --sign - --timestamp --entitlements "$ENTITLEMENTS" "$APP"
fi

echo "Built ${APP}"
echo "For App Store upload, archive/export with the Apple Distribution identity and App Store Connect provisioning profile."
