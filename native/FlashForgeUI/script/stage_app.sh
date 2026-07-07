#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-debug}"
APP_NAME="FlashForgeNative"
DISPLAY_NAME="FlashForgeUI"
BUNDLE_ID="com.ghosttypes.flashforgeui.native"
MIN_SYSTEM_VERSION="14.0"
MARKETING_VERSION="0.1.0"
BUILD_VERSION="${BUILD_VERSION:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"

case "$CONFIGURATION" in
  debug)
    SWIFT_CONFIGURATION="debug"
    ;;
  release)
    SWIFT_CONFIGURATION="release"
    ;;
  *)
    echo "usage: $0 [debug|release]" >&2
    exit 2
    ;;
esac

cd "$ROOT_DIR"

swift build --disable-sandbox --configuration "$SWIFT_CONFIGURATION" --product "$APP_NAME" >&2
BUILD_BINARY="$(swift build --disable-sandbox --configuration "$SWIFT_CONFIGURATION" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
  </dict>
  <key>NSLocalNetworkUsageDescription</key>
  <string>FlashForgeUI discovers and controls FlashForge printers on your local network.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

printf 'APPL????' >"$APP_CONTENTS/PkgInfo"

/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
test -x "$APP_BINARY"

echo "$APP_BUNDLE"
