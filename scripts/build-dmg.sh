#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Lumina — Build + Package DMG
#
# Usage:
#   ./scripts/build-dmg.sh [--arch arm64|x86_64|universal] [--version X.Y.Z]
#
# What it does:
#   1. Builds a release binary with swift build
#   2. Assembles a proper .app bundle
#   3. Signs it (skipped if no Developer ID is set)
#   4. Creates a drag-to-install DMG with hdiutil
#
# Requirements: macOS 15+, Xcode CLT, Swift 6+
#   Optional: codesign (Developer ID cert), notarytool (notarization)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
APP_NAME="Lumina"
BUNDLE_ID="com.lumina.studio"
VERSION="${VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
ARCH="${ARCH:-arm64}"           # arm64 | x86_64 | universal
SIGN_IDENTITY="${SIGN_IDENTITY:-}" # set to "Developer ID Application: ..." to sign

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
BUILD_DIR="$ROOT/.build"
DIST_DIR="$ROOT/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
STAGING="$DIST_DIR/dmg-staging"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'
step() { echo -e "${CYAN}▶ $1${RESET}"; }
ok()   { echo -e "${GREEN}✓ $1${RESET}"; }
err()  { echo -e "${RED}✗ $1${RESET}" >&2; exit 1; }

# ── 1. Build ──────────────────────────────────────────────────────────────────
step "Building $APP_NAME $VERSION ($ARCH)"
cd "$ROOT"

if [[ "$ARCH" == "universal" ]]; then
  swift build -c release --arch arm64 --arch x86_64 2>&1 | grep -E "error:|Build complete" || true
  BINARY="$BUILD_DIR/apple/Products/Release/$APP_NAME"
  if [[ ! -f "$BINARY" ]]; then
    # Fallback: lipo arm64 + x86_64 manually
    swift build -c release --arch arm64  2>&1 | tail -1
    swift build -c release --arch x86_64 2>&1 | tail -1
    mkdir -p "$BUILD_DIR/universal"
    lipo -create \
      "$BUILD_DIR/arm64-apple-macosx/release/$APP_NAME" \
      "$BUILD_DIR/x86_64-apple-macosx/release/$APP_NAME" \
      -output "$BUILD_DIR/universal/$APP_NAME"
    BINARY="$BUILD_DIR/universal/$APP_NAME"
    RESOURCES_BUNDLE="$BUILD_DIR/arm64-apple-macosx/release/${APP_NAME}_${APP_NAME}.bundle"
  fi
elif [[ "$ARCH" == "x86_64" ]]; then
  swift build -c release --arch x86_64 2>&1 | grep -E "error:|Build complete" || true
  BINARY="$BUILD_DIR/x86_64-apple-macosx/release/$APP_NAME"
  RESOURCES_BUNDLE="$BUILD_DIR/x86_64-apple-macosx/release/${APP_NAME}_${APP_NAME}.bundle"
else
  swift build -c release --arch arm64 2>&1 | grep -E "error:|Build complete" || true
  BINARY="$BUILD_DIR/arm64-apple-macosx/release/$APP_NAME"
  RESOURCES_BUNDLE="$BUILD_DIR/arm64-apple-macosx/release/${APP_NAME}_${APP_NAME}.bundle"
fi

[[ -f "$BINARY" ]] || err "Binary not found at $BINARY. Did the build fail?"
ok "Binary built: $(du -sh "$BINARY" | cut -f1)"

# ── 2. Assemble .app bundle ───────────────────────────────────────────────────
step "Assembling $APP_NAME.app"
rm -rf "$APP_BUNDLE" "$STAGING"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# SPM resource bundle
if [[ -d "$RESOURCES_BUNDLE" ]]; then
  cp -R "$RESOURCES_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

# App icon — convert PNG to ICNS if iconutil available
ICON_PNG="$ROOT/Sources/$APP_NAME/Resources/Icons/LuminaAppIcon.png"
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
    <key>CFBundleSignature</key>       <string>????</string>
    <key>LSMinimumSystemVersion</key>  <string>15.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Lumina Contributors. MIT License.</string>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <!-- Security-scoped bookmark access for wallpaper files -->
    <key>com.apple.security.files.user-selected.read-write</key><true/>
    <key>com.apple.security.files.bookmarks.app-scope</key><true/>
</dict>
</plist>
PLIST
ok "Bundle assembled at $APP_BUNDLE"

# ── 3. Code Sign ──────────────────────────────────────────────────────────────
if [[ -n "$SIGN_IDENTITY" ]]; then
  step "Signing with: $SIGN_IDENTITY"

  # Entitlements
  ENTITLEMENTS="$DIST_DIR/Lumina.entitlements"
  cat > "$ENTITLEMENTS" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.files.user-selected.read-write</key><true/>
    <key>com.apple.security.files.bookmarks.app-scope</key><true/>
    <key>com.apple.security.cs.allow-jit</key><true/>
</dict>
</plist>
ENT

  codesign --force --options runtime \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp \
    "$APP_BUNDLE"
  ok "Signed"
else
  # Ad-hoc sign so the app has a stable code identity. This is required for
  # SMAppService (Launch at login) to work even without a Developer ID, and avoids
  # the unsigned-binary failures that silently break login-item registration.
  step "Ad-hoc signing (no Developer ID set)"
  codesign --force --sign - --timestamp=none "$APP_BUNDLE" \
    && ok "Ad-hoc signed (Launch at login will work locally)" \
    || echo "  (ad-hoc signing failed — Launch at login may not register)"
fi

# ── 4. Create DMG ─────────────────────────────────────────────────────────────
step "Creating DMG: $APP_NAME-$VERSION.dmg"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
# Applications symlink so users can drag-install
ln -sf /Applications "$STAGING/Applications"

# Write a small README inside the DMG
cat > "$STAGING/Install Lumina.txt" <<TXT
Thank you for downloading Lumina!

To install:
  1. Drag Lumina into the Applications folder
  2. Open Lumina from Launchpad or Spotlight
  3. Look for the Lumina icon in your menu bar

Lumina is a menu-bar app — it has no Dock icon by design.
TXT

hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH" >/dev/null

ok "DMG created: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"

# ── 5. Notarization hint ──────────────────────────────────────────────────────
if [[ -n "$SIGN_IDENTITY" ]]; then
  echo ""
  echo "  To notarize (requires Apple Developer account):"
  echo "  xcrun notarytool submit \"$DMG_PATH\" --keychain-profile AC_PASSWORD --wait"
  echo "  xcrun stapler staple \"$DMG_PATH\""
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}  $APP_NAME $VERSION ready for distribution${RESET}"
echo -e "${GREEN}  $DMG_PATH${RESET}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
