#!/bin/bash
set -e

# Usage: ./release.sh 0.8.2 "Bug fixes and improvements"
VERSION="${1:?Usage: ./release.sh VERSION \"Release notes\"}"
NOTES="${2:-Bug fixes and improvements.}"

PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Notaty"
BUNDLE_ID="com.notaty.app"
APP_BUNDLE="/tmp/${APP_NAME}.app"
DMG_PATH="${PROJ_DIR}/dist/${APP_NAME}-${VERSION}.dmg"
APPCAST_PATH="${PROJ_DIR}/dist/appcast.xml"
DOWNLOAD_BASE="https://icamel.app/product/notaty"
SIGN_TOOL="${PROJ_DIR}/.build/artifacts/sparkle/Sparkle/bin/sign_update"
CERT_NAME="Notaty Local Dev"

echo "═══════════════════════════════════════"
echo "  Notaty Release v${VERSION}"
echo "═══════════════════════════════════════"

# Step 1: Build release binary
echo ""
echo "→ Building release binary..."
cd "$PROJ_DIR"
swift build -c release 2>&1

BINARY="$(swift build -c release --show-bin-path 2>/dev/null)/${APP_NAME}"

# Step 2: Assemble app bundle
echo "→ Assembling app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
if [[ -f "${PROJ_DIR}/AppIcon.icns" ]]; then
    cp "${PROJ_DIR}/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Bundle Sparkle.framework so the binary can find it at @rpath.
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
SPARKLE_FW="${PROJ_DIR}/.build/arm64-apple-macosx/release/Sparkle.framework"
if [[ ! -d "$SPARKLE_FW" ]]; then
    SPARKLE_FW="${PROJ_DIR}/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
fi
if [[ -d "$SPARKLE_FW" ]]; then
    cp -R "$SPARKLE_FW" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
fi

# Read the public EdDSA key from the Sparkle keychain item if available.
ED_KEY=$("$SIGN_TOOL" --ed-key-file - --account notaty-ed25519 < /dev/null 2>&1 | grep -o '^[A-Za-z0-9+/=]\{40,\}$' || true)
if [ -z "$ED_KEY" ]; then
    ED_KEY="NOTATY_ED_KEY_PLACEHOLDER"
    echo "⚠ Could not read EdDSA public key. Using placeholder."
fi

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Notaty needs Screen Recording permission to capture regions of the screen for OCR.</string>
    <key>SUFeedURL</key>
    <string>https://icamel.app/product/notaty/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>${ED_KEY}</string>
</dict>
</plist>
PLIST

# Step 3: Sign app bundle
echo "→ Signing app bundle..."
if security find-certificate -c "$CERT_NAME" 2>/dev/null | grep -q "$CERT_NAME"; then
    codesign --force --deep --sign "$CERT_NAME" --timestamp "$APP_BUNDLE"
else
    echo "  (ad-hoc — run ./setup-signing.sh for persistent identity)"
    codesign --force --deep --sign - --timestamp "$APP_BUNDLE"
fi

# Step 4: Create DMG
echo "→ Creating DMG..."
mkdir -p "$PROJ_DIR/dist"
rm -f "$DMG_PATH"
STAGE=$(mktemp -d)
cp -R "$APP_BUNDLE" "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG_PATH"
rm -rf "$STAGE"

# Step 5: Sign DMG with Sparkle EdDSA
echo "→ Signing DMG for Sparkle..."
if [ ! -f "$SIGN_TOOL" ]; then
    echo "⚠ sign_update not found at $SIGN_TOOL"
    echo "  Run 'swift package resolve' then check .build/artifacts/sparkle/Sparkle/bin/"
    exit 1
fi

SIGNATURE=$("$SIGN_TOOL" "$DMG_PATH" --account notaty-ed25519 2>&1 | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"//')
LENGTH=$(stat -f%z "$DMG_PATH")
PUB_DATE=$(date -R)

if [ -z "$SIGNATURE" ]; then
    echo "⚠ Failed to sign DMG. Check Sparkle keys in keychain."
    echo "  Generate keys: .build/artifacts/sparkle/Sparkle/bin/generate_keys"
    exit 1
fi

echo "  Signature: ${SIGNATURE:0:20}..."
echo "  Size: ${LENGTH} bytes"

# Step 6: Generate appcast.xml
echo "→ Generating appcast.xml..."
cat > "$APPCAST_PATH" << APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Notaty Updates</title>
        <link>https://icamel.app/product/notaty/appcast.xml</link>
        <description>Most recent updates for Notaty.</description>
        <language>en</language>
        <item>
            <title>Version ${VERSION}</title>
            <description><![CDATA[<p>${NOTES}</p>]]></description>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${DOWNLOAD_BASE}/${APP_NAME}-${VERSION}.dmg"
                length="${LENGTH}"
                type="application/octet-stream"
                sparkle:edSignature="${SIGNATURE}"
            />
        </item>
    </channel>
</rss>
APPCAST

# Step 7: Clean up temp app bundle
rm -rf "$APP_BUNDLE"

# Step 8: Summary
echo ""
echo "═══════════════════════════════════════"
echo "  ✓ Release v${VERSION} ready"
echo "═══════════════════════════════════════"
echo ""
echo "  DMG:      dist/${APP_NAME}-${VERSION}.dmg"
echo "  Appcast:  dist/appcast.xml"
echo ""
echo "  Upload to icamel.app/product/notaty/:"
echo "    1. ${APP_NAME}-${VERSION}.dmg"
echo "    2. appcast.xml"
echo ""
