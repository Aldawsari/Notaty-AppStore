#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

swift build

APP=".build/debug/NotatyAppstore-Debug.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/debug/NotatyAppstore "$APP/Contents/MacOS/NotatyAppstore"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NotatyAppstore</string>
    <key>CFBundleIdentifier</key>
    <string>com.aldawsari.NotatyAppstore.debug</string>
    <key>CFBundleName</key>
    <string>NotatyAppstore</string>
    <key>CFBundleDisplayName</key>
    <string>NotatyAppstore</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Notaty needs Screen Recording permission to capture regions of the screen for OCR.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - --entitlements NotatyAppstore.entitlements "$APP"
echo "Launching NotatyAppstore-Debug.app..."
open "$APP"
