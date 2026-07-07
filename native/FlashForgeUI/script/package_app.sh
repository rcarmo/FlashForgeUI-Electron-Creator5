#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-package}"
APP_NAME="FlashForgeUI"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
ARCHIVE_DIR="$DIST_DIR/archive"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

cd "$ROOT_DIR"

APP_BUNDLE="$("$ROOT_DIR/script/stage_app.sh" release)"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
APP_ICON="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
ZIP_PATH="$ARCHIVE_DIR/$APP_NAME.zip"
INSTALL_APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"

validate_bundle() {
  test -d "$APP_BUNDLE"
  test -x "$APP_BINARY"
  /usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$INFO_PLIST" | grep -q "^AppIcon$"
  test -s "$APP_ICON"
  /usr/bin/file "$APP_BINARY" | grep -q "Mach-O"
}

sign_bundle() {
  if [[ "$SIGN_IDENTITY" == "none" ]]; then
    return
  fi

  /usr/bin/codesign \
    --force \
    --deep \
    --options runtime \
    --sign "$SIGN_IDENTITY" \
    "$APP_BUNDLE"

  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
}

create_zip() {
  rm -rf "$ARCHIVE_DIR"
  mkdir -p "$ARCHIVE_DIR"
  /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
  test -s "$ZIP_PATH"
}

install_bundle() {
  if [[ -e "$INSTALL_APP_BUNDLE" && "${INSTALL_REPLACE:-0}" != "1" ]]; then
    echo "$INSTALL_APP_BUNDLE already exists; set INSTALL_REPLACE=1 to replace it" >&2
    exit 3
  fi

  mkdir -p "$INSTALL_DIR"

  if [[ -e "$INSTALL_APP_BUNDLE" ]]; then
    rm -rf "$INSTALL_APP_BUNDLE"
  fi

  /usr/bin/ditto "$APP_BUNDLE" "$INSTALL_APP_BUNDLE"
  test -d "$INSTALL_APP_BUNDLE"
  test -x "$INSTALL_APP_BUNDLE/Contents/MacOS/$APP_NAME"
}

case "$MODE" in
  package)
    validate_bundle
    sign_bundle
    create_zip
    echo "$ZIP_PATH"
    ;;
  --verify|verify)
    validate_bundle
    sign_bundle
    echo "$APP_BUNDLE"
    ;;
  install)
    validate_bundle
    sign_bundle
    install_bundle
    echo "$INSTALL_APP_BUNDLE"
    ;;
  *)
    echo "usage: $0 [package|--verify|install]" >&2
    echo "set SIGN_IDENTITY=none to skip signing or SIGN_IDENTITY='Developer ID Application: ...' for distribution signing" >&2
    echo "set INSTALL_DIR=/Applications and INSTALL_REPLACE=1 when replacing an installed app" >&2
    exit 2
    ;;
esac
