#!/usr/bin/env bash
# One-time setup: creates a self-signed code-signing certificate called
# "Notaty Local Dev" in the user's login keychain, so that subsequent
# `./build.sh` runs can sign Notaty with a stable identity.
#
# Why: without a stable signature, macOS TCC treats every rebuild as a new
# app and forgets Screen Recording permission. With a stable self-signed
# identity, TCC remembers.
#
# This script must run INTERACTIVELY. macOS will pop up a dialog asking you
# to allow codesign to use the new private key — click "Always Allow".

set -euo pipefail

CERT_NAME="Notaty Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
  echo "\"$CERT_NAME\" is already installed. Nothing to do."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.conf" <<CONF
[req]
distinguished_name = req_dn
x509_extensions = v3_req
prompt = no
[req_dn]
CN = $CERT_NAME
[v3_req]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF

echo "Generating key + certificate..."
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -config "$TMP/cert.conf" 2>/dev/null

openssl pkcs12 -export -legacy \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$CERT_NAME" \
  -out "$TMP/bundle.p12" -passout pass:notaty 2>/dev/null

echo "Importing into login keychain (you may see a keychain password prompt)..."
security import "$TMP/bundle.p12" -k "$KEYCHAIN" -P notaty -A

echo "Adding trust for code signing (you may see an admin password prompt)..."
sudo security add-trusted-cert -d -r trustRoot -p codeSign \
  -k /Library/Keychains/System.keychain "$TMP/cert.pem"

echo
echo "Done. Now run:"
echo "  ./build.sh 0.7"
echo
echo "The FIRST time you launch the freshly signed app you will still have to grant Screen Recording permission once. After that, all subsequent rebuilds will keep the permission."
