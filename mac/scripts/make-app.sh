#!/usr/bin/env bash
# Build boxed.app — a menubar agent bundle (LSUIElement, no dock icon).
#
# LOCAL DEVELOPMENT ONLY. Signs with the self-signed `boxed-dev` identity (see
# setup-signing.sh). Distribution must use a real Developer ID + hardened runtime +
# notarization, not this.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▶ building (release)…"
swift build -c release

APP="boxed.app"
BIN=".build/release/boxed"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/boxed"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>boxed</string>
  <key>CFBundleDisplayName</key><string>boxed</string>
  <key>CFBundleIdentifier</key><string>org.yesslab.boxed</string>
  <key>CFBundleExecutable</key><string>boxed</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
PLIST

# Prefer the stable self-signed identity (so the Accessibility grant persists
# across rebuilds). Fall back to ad-hoc if setup-signing.sh hasn't been run.
IDENTITY="boxed-dev"
KEYCHAIN="$HOME/Library/Keychains/boxed-dev.keychain-db"
if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
  security unlock-keychain -p boxed "$KEYCHAIN" 2>/dev/null || true
  codesign --force --deep --sign "$IDENTITY" --keychain "$KEYCHAIN" "$APP" >/dev/null 2>&1
  echo "  signed with stable identity '$IDENTITY' (grant persists across rebuilds)"
else
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  echo "  ad-hoc signed — run scripts/setup-signing.sh once so the grant persists"
fi

echo "✓ built $(pwd)/$APP"
echo "  Run it:   open $APP"
echo "  Then grant Accessibility in System Settings → Privacy & Security → Accessibility."
