#!/usr/bin/env bash
# Builds keepMacClear and installs it as a proper .app bundle in /Applications.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "▸ Building release binary..."
swift build -c release

BINARY=".build/release/keepMacClear"
APP_DIR="/Applications/keepMacClear.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "▸ Creating .app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BINARY" "$MACOS/keepMacClear"

cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>keepMacClear</string>
    <key>CFBundleIdentifier</key>
    <string>com.keepmacclear.app</string>
    <key>CFBundleName</key>
    <string>keepMacClear</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
PLIST

echo "▸ Done!  Opening keepMacClear…"
open "$APP_DIR"
echo "   Look for 'RAM XX%' in your menu bar."
