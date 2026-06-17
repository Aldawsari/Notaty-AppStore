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
    <string>Notaty</string>
    <key>CFBundleDisplayName</key>
    <string>Notaty</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Notaty needs Screen Recording permission to capture regions of the screen for OCR.</string>
</dict>
</plist>
PLIST

# Use sandbox-only entitlements for the local debug build. The App Store
# entitlements (application-identifier / team-identifier) require a matching
# provisioning profile and make an ad-hoc-signed debug bundle fail to launch.
codesign --force --deep --sign - --entitlements NotatyAppstore-Debug.entitlements "$APP"
echo "Launching NotatyAppstore-Debug.app..."
open "$APP"
