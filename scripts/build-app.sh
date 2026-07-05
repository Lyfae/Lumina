#!/usr/bin/env bash
# Quick rebuild of dist/Lumina.app for testing (no DMG)
# Usage: ./scripts/build-app.sh

set -euo pipefail

APP_NAME="Lumina"
BUNDLE_ID="com.lumina.studio"
VERSION="0.2.0"
BUILD_NUMBER="2"
ARCH="arm64"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT"

BUILD_DIR=".build"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
BINARY="$BUILD_DIR/arm64-apple-macosx/release/$APP_NAME"
RESOURCES_BUNDLE="$BUILD_DIR/arm64-apple-macosx/release/${APP_NAME}_${APP_NAME}.bundle"

echo "→ Building release binary..."
swift build -c release --arch "$ARCH"

echo "→ Assembling $APP_BUNDLE ..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [[ -d "$RESOURCES_BUNDLE" ]]; then
  cp -R "$RESOURCES_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

# Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleVersion</key>         <string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Lumina Contributors. MIT License.</string>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>com.apple.security.files.user-selected.read-write</key><true/>
    <key>com.apple.security.files.bookmarks.app-scope</key><true/>
</dict>
</plist>
PLIST

# Icon
ICON_PNG="Sources/Lumina/Resources/Icons/LuminaAppIcon.png"
if [[ -f "$ICON_PNG" ]]; then
  ICONSET="$DIST_DIR/Lumina.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 64 128 256 512; do
    sips -z $size $size "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" &>/dev/null || true
    double=$((size * 2))
    sips -z $double $double "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" &>/dev/null || true
  done
  iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
  rm -rf "$ICONSET"
fi

# Ad-hoc sign
codesign --force --sign - --timestamp=none "$APP_BUNDLE" 2>/dev/null || true

echo "✓ dist/Lumina.app updated"
echo ""
echo "To test: open dist/Lumina.app"
echo ""
