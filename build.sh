#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudePermissionAutomater"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "→ Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS" "$RESOURCES"

echo "→ Compiling Swift sources"
# Collect sources in stable order
SOURCES=(
  "$ROOT/Sources/DialogModels.swift"
  "$ROOT/Sources/ConfigStore.swift"
  "$ROOT/Sources/AXHelpers.swift"
  "$ROOT/Sources/DialogDetector.swift"
  "$ROOT/Sources/KeystrokeApprover.swift"
  "$ROOT/Sources/ScreenOCRDetector.swift"
  "$ROOT/Sources/PolicyEngine.swift"
  "$ROOT/Sources/PermissionMonitor.swift"
  "$ROOT/Sources/StatusItemController.swift"
  "$ROOT/Sources/main.swift"
)

swiftc -O \
  -target arm64-apple-macosx13.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  -framework AppKit \
  -framework ApplicationServices \
  -framework Cocoa \
  -framework Vision \
  -o "$MACOS/$APP_NAME" \
  "${SOURCES[@]}"

echo "→ Copying Info.plist / PkgInfo"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Ad-hoc sign so Accessibility TCC prompts against a stable identity when possible
echo "→ Ad-hoc codesign"
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

# Convenience copy at project root
ROOT_APP="$ROOT/$APP_NAME.app"
rm -rf "$ROOT_APP"
ditto "$APP_DIR" "$ROOT_APP"
xattr -cr "$ROOT_APP" 2>/dev/null || true
codesign --force --deep --sign - "$ROOT_APP" 2>/dev/null || true

# Optional: install a copy under ~/Applications for easier Launch Services registration
USER_APP="$HOME/Applications/$APP_NAME.app"
if mkdir -p "$HOME/Applications" 2>/dev/null \
  && rm -rf "$USER_APP" \
  && ditto "$ROOT_APP" "$USER_APP" 2>/dev/null; then
  xattr -cr "$USER_APP" 2>/dev/null || true
  codesign --force --deep --sign - "$USER_APP" 2>/dev/null || true
  echo ""
  echo "Built: $ROOT_APP"
  echo "Also:  $USER_APP"
  echo ""
  echo "To run:"
  echo "  open \"$USER_APP\""
else
  echo ""
  echo "Built: $ROOT_APP"
  echo ""
  echo "To run:"
  echo "  open \"$ROOT_APP\""
fi
echo ""
echo "Then grant Accessibility:"
echo "  System Settings → Privacy & Security → Accessibility → enable Claude Permission Automation"
echo ""
