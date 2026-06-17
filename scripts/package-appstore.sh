#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.1}"
APP_NAME="NotatyAppstore"
DISPLAY_NAME="Notaty"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/${APP_NAME}-${VERSION}.app"
PKG="$DIST/${DISPLAY_NAME}-${VERSION}.pkg"
ENTITLEMENTS="$ROOT/NotatyAppstore.entitlements"

APP_SIGN_IDENTITY="${APPSTORE_SIGN_IDENTITY:-Apple Distribution}"
INSTALLER_SIGN_IDENTITY="${APPSTORE_INSTALLER_IDENTITY:-3rd Party Mac Developer Installer}"

cd "$ROOT"

if ! security find-certificate -c "$APP_SIGN_IDENTITY" >/dev/null 2>&1; then
  echo "Error: app signing identity not found: $APP_SIGN_IDENTITY" >&2
  echo "Set APPSTORE_SIGN_IDENTITY to the exact Apple Distribution certificate name." >&2
  exit 1
fi

if ! security find-certificate -c "$INSTALLER_SIGN_IDENTITY" >/dev/null 2>&1; then
  echo "Error: installer signing identity not found: $INSTALLER_SIGN_IDENTITY" >&2
  echo "Set APPSTORE_INSTALLER_IDENTITY to the exact 3rd Party Mac Developer Installer certificate name." >&2
  exit 1
fi

if [[ ! -d "$APP" ]]; then
  ./build.sh "$VERSION"
fi

if [[ -e "$PKG" ]]; then
  echo "Error: $PKG already exists. Remove it or choose another version." >&2
  exit 1
fi

echo "Signing $APP with $APP_SIGN_IDENTITY..."
codesign --force --deep --sign "$APP_SIGN_IDENTITY" --timestamp --entitlements "$ENTITLEMENTS" "$APP"

echo "Verifying app signature..."
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Packaging $PKG..."
productbuild \
  --component "$APP" /Applications \
  --sign "$INSTALLER_SIGN_IDENTITY" \
  "$PKG"

echo "Verifying package signature..."
pkgutil --check-signature "$PKG"

echo "Built $PKG"
echo "Upload with Transporter or App Store Connect upload tooling after the app record exists."
