#!/usr/bin/env bash
# Build boxed.app — a menubar agent bundle (LSUIElement, no dock icon).
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

# Ad-hoc sign so the bundle has a stable identity for the Accessibility grant.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "✓ built $(pwd)/$APP"
echo "  Run it:   open $APP"
echo "  Then grant Accessibility in System Settings → Privacy & Security → Accessibility."
