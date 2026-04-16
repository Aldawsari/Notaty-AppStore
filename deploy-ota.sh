#!/bin/bash
# Notaty OTA Deploy — pull from GitHub, build on Mac, push update to icamel
set -e

MAC="naif@100.122.115.71"
PROJ_DIR="/home/ft/apps/MacApps/Swalfy/Notaty"
MAC_PROJ="~/apps/Swalfy/Notaty"
ICAMEL_DIR="/home/ft/apps/MacApps/icamel/web/product/notaty"
SIGN_ID="Developer ID Application: Naif AlQazlan (9VRVCKY375)"
BUNDLE_ID="com.notaty.app"
SPARKLE_KEY="/tmp/notaty_ed_key.txt"
SPARKLE_ACCOUNT="notaty-ed25519"
PUBKEY="XtdBkj5GMxVlo1CnSXHUyrha0egSZLqrD3++JMW5l+k="
APP_NAME="Notaty"

echo "==> Pulling latest from GitHub..."
cd "$PROJ_DIR"
git fetch origin --tags
git stash 2>/dev/null || true
git pull --rebase origin main

VERSION=$(git tag --sort=-v:refname | head -1 | sed 's/^v//')
if [ -z "$VERSION" ]; then
    echo "ERROR: No version tag found"
    exit 1
fi
echo "  Version: $VERSION"

echo "==> Syncing to Mac via rsync..."
rsync -av --delete --exclude='.git' --exclude='.build' --exclude='build' \
  --exclude='DerivedData' --exclude='dist' --exclude='.DS_Store' \
  "$PROJ_DIR/" "$MAC:$MAC_PROJ/"

echo "==> Building on Mac..."
ssh "$MAC" "security unlock-keychain -p '989898' ~/Library/Keychains/login.keychain-db"
ssh "$MAC" "cd $MAC_PROJ && swift build -c release 2>&1 | tail -3"

echo "==> Assembling app bundle v${VERSION}..."
ssh "$MAC" "bash -s" << REMOTE
set -e
APP=/tmp/${APP_NAME}.app
PROJ=$MAC_PROJ
SPARKLE_FW="\$PROJ/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
BINARY="\$(cd \$PROJ && swift build -c release --show-bin-path 2>/dev/null)/${APP_NAME}"

rm -rf \$APP
mkdir -p \$APP/Contents/{MacOS,Resources,Frameworks}
cp "\$BINARY" \$APP/Contents/MacOS/${APP_NAME}
cp "\$PROJ/AppIcon.icns" \$APP/Contents/Resources/AppIcon.icns
cp -R "\$SPARKLE_FW" \$APP/Contents/Frameworks/

install_name_tool -add_rpath @executable_path/../Frameworks \$APP/Contents/MacOS/${APP_NAME} 2>/dev/null || true

cat > \$APP/Contents/Info.plist << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSScreenCaptureUsageDescription</key><string>Notaty needs Screen Recording permission to capture regions of the screen for OCR.</string>
    <key>SUFeedURL</key><string>https://icamel.app/product/notaty/appcast.xml</string>
    <key>SUPublicEDKey</key><string>$PUBKEY</string>
</dict>
</plist>
PLIST

security unlock-keychain -p '989898' ~/Library/Keychains/login.keychain-db
CODESIGN="codesign --force --options runtime --timestamp --sign \"$SIGN_ID\""
eval \$CODESIGN "\$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
eval \$CODESIGN "\$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
eval \$CODESIGN "\$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
eval \$CODESIGN "\$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
eval \$CODESIGN "\$APP/Contents/Frameworks/Sparkle.framework"
eval \$CODESIGN "\$APP"
codesign --verify --deep --strict \$APP
echo "Signed OK"

rm -f /tmp/${APP_NAME}-update.zip
cd /tmp && zip -r -y ${APP_NAME}-update.zip ${APP_NAME}.app

xcrun notarytool submit /tmp/${APP_NAME}-update.zip \
    --key ~/.appstore/AuthKey_A9C6Q7QRPY.p8 \
    --key-id A9C6Q7QRPY \
    --issuer f8bed33a-4194-4840-901c-beb0ed6c2817 \
    --wait

xcrun stapler staple \$APP
rm /tmp/${APP_NAME}-update.zip
cd /tmp && zip -r -y ${APP_NAME}-update.zip ${APP_NAME}.app
echo "Notarized & stapled"

cd \$PROJ
SIGN_OUT=\$(.build/artifacts/sparkle/Sparkle/bin/sign_update /tmp/${APP_NAME}-update.zip --account $SPARKLE_ACCOUNT --ed-key-file $SPARKLE_KEY 2>&1)
echo "SPARKLE_SIGN: \$SIGN_OUT"
REMOTE

echo "==> Downloading update zip..."
scp "$MAC":/tmp/${APP_NAME}-update.zip /tmp/${APP_NAME}-update.zip

echo "==> Getting Sparkle signature..."
SIGN_LINE=$(ssh "$MAC" "cd $MAC_PROJ && .build/artifacts/sparkle/Sparkle/bin/sign_update /tmp/${APP_NAME}-update.zip --account $SPARKLE_ACCOUNT --ed-key-file $SPARKLE_KEY 2>&1")
ED_SIG=$(echo "$SIGN_LINE" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGN_LINE" | grep -o 'length="[^"]*"' | cut -d'"' -f2)
echo "  Signature: $ED_SIG"
echo "  Length: $LENGTH"

if [ -z "$ED_SIG" ] || [ -z "$LENGTH" ]; then
    echo "ERROR: Failed to get Sparkle signature"
    exit 1
fi

echo "==> Deploying to icamel..."
cp /tmp/${APP_NAME}-update.zip "$ICAMEL_DIR/${APP_NAME}-${VERSION}.zip"

PUB_DATE=$(date -u '+%a, %d %b %Y %H:%M:%S +0000')

cat > "$ICAMEL_DIR/appcast.xml" << APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.sparkle-project.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>${APP_NAME} Updates</title>
    <link>https://icamel.app/product/notaty/appcast.xml</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <description><![CDATA[
        <ul>
          <li>New update v${VERSION}</li>
        </ul>
      ]]></description>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure
        url="https://icamel.app/product/notaty/${APP_NAME}-${VERSION}.zip"
        sparkle:version="${VERSION}"
        sparkle:shortVersionString="${VERSION}"
        sparkle:edSignature="${ED_SIG}"
        length="${LENGTH}"
        type="application/octet-stream"
      />
    </item>
  </channel>
</rss>
APPCAST

echo ""
echo "✓ ${APP_NAME} v${VERSION} deployed to icamel"
echo "  Update: https://icamel.app/product/notaty/${APP_NAME}-${VERSION}.zip"
echo "  Appcast: https://icamel.app/product/notaty/appcast.xml"
