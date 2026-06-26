#!/usr/bin/env bash
# Create a stable, self-signed code-signing identity for local development.
#
# Why: an ad-hoc-signed app gets a new identity on every rebuild, so macOS
# forgets its Accessibility grant each time. A stable identity means you grant
# Accessibility ONCE and it survives every future rebuild.
#
# Run this once. It's safe and reversible (security delete-keychain "$KEYCHAIN").
#
# LOCAL DEVELOPMENT ONLY. The keychain password is hardcoded, the key is importable
# by any tool, and the cert is self-signed/untrusted by Gatekeeper — fine for a dev
# box, NOT for distribution. Ship with a real Developer ID + notarization instead.
set -euo pipefail

IDENTITY="boxed-dev"
KEYCHAIN="$HOME/Library/Keychains/boxed-dev.keychain-db"
KC_PASS="boxed"

# Note: a self-signed identity is untrusted by Gatekeeper, so it never shows up
# under `-v` (valid only) — but codesign can still sign with it, and that's all we
# need. Match without `-v`.
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "✓ signing identity '$IDENTITY' already exists — nothing to do"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = boxed-dev
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

echo "▶ generating self-signed code-signing certificate…"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" 2>/dev/null

# macOS `security import` only reads legacy PKCS12 MAC/PBE algorithms; OpenSSL 3
# defaults to newer ones it can't verify, so force -legacy there. Use a password
# (empty-password p12s also trip up the importer).
P12_LEGACY=()
if openssl version 2>/dev/null | grep -qi "openssl 3"; then P12_LEGACY=(-legacy); fi
openssl pkcs12 -export "${P12_LEGACY[@]}" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/$IDENTITY.p12" -passout pass:"$KC_PASS" -name "$IDENTITY" 2>/dev/null

echo "▶ creating dedicated keychain…"
security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"            # disable auto-lock timeout
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"

echo "▶ importing identity…"
security import "$TMP/$IDENTITY.p12" -k "$KEYCHAIN" -P "$KC_PASS" -T /usr/bin/codesign -A
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null 2>&1

# Keep the new keychain in the user search list alongside the existing ones.
EXISTING=$(security list-keychains -d user | sed -e 's/"//g' -e 's/^[[:space:]]*//')
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN" $EXISTING

echo "✓ created signing identity '$IDENTITY':"
security find-identity -p codesigning "$KEYCHAIN" | grep "$IDENTITY" || true
