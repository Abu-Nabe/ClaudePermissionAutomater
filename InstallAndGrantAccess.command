#!/usr/bin/env bash
# Installs the app to a stable path and opens Accessibility settings.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/ClaudePermissionAutomater.app"
DEST="/Applications/ClaudePermissionAutomater.app"

if [[ ! -d "$SRC" ]]; then
  echo "Building first…"
  "$ROOT/build.sh"
fi

echo "→ Quitting old instance (if any)"
pkill -x ClaudePermissionAutomater 2>/dev/null || true
sleep 0.5

echo "→ Installing to $DEST"
rm -rf "$DEST"
ditto "$SRC" "$DEST"
xattr -cr "$DEST" 2>/dev/null || true
codesign --force --deep --sign - "$DEST" 2>/dev/null || true

echo "→ Opening Accessibility settings"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null \
  || open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility" 2>/dev/null \
  || true

echo "→ Launching app"
open "$DEST"

cat <<'EOF'

════════════════════════════════════════════════════════
REQUIRED — otherwise detection will never work:

1. In System Settings → Privacy & Security → Accessibility
2. Click the + button (or find Claude Permission Automation)
3. Select: /Applications/ClaudePermissionAutomater.app
4. Turn the toggle ON
5. Also enable Screen Recording for the same app (OCR fallback)
6. Quit and reopen the app from /Applications if the toggle was just enabled

Then open the menu bar shield icon — Status must say
  ● Running
NOT
  ● Needs Accessibility
════════════════════════════════════════════════════════
EOF
