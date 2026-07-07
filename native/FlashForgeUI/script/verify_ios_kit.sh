#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT_TARGET="FlashForgeNativeKit"
MOBILE_PRODUCT="FlashForgeMobile"

cd "$ROOT_DIR"

IOS_SIMULATOR_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"

run_swift_build() {
  local scratch_path="$1"
  shift

  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_PATH" swift build \
    --disable-sandbox \
    --triple arm64-apple-ios17.0-simulator \
    --sdk "$IOS_SIMULATOR_SDK" \
    --scratch-path "$scratch_path" \
    "$@"
}

run_swift_build "$ROOT_DIR/.build/ios-kit" --target "$KIT_TARGET"
run_swift_build "$ROOT_DIR/.build/ios-mobile" --product "$MOBILE_PRODUCT"

echo "iOS Simulator cross-compiles succeeded for $KIT_TARGET and $MOBILE_PRODUCT."
