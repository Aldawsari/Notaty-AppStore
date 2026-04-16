#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

swift build

APP=".build/debug/Notaty-Debug.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Frameworks"

cp .build/debug/Notaty "$APP/Contents/MacOS/Notaty"

# Copy Sparkle framework
SPARKLE_FW=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
  cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
  install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Notaty" 2>/dev/null || true
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Notaty</string>
    <key>CFBundleIdentifier</key>
    <string>com.notaty.debug</string>
    <key>CFBundleName</key>
    <string>Notaty</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Notaty needs microphone access to record voice notes.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Notaty uses speech recognition to transcribe voice notes to text.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Notaty needs Screen Recording permission to capture regions of the screen for OCR.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Launching Notaty-Debug.app..."
open "$APP"
