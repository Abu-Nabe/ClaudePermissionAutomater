#!/bin/bash
# Double-click or run from Terminal to start the menu-bar app.
cd "$(dirname "$0")"
APP="ClaudePermissionAutomater.app"
if [[ ! -x "$APP/Contents/MacOS/ClaudePermissionAutomater" ]]; then
  echo "App missing — building…"
  ./build.sh
fi
open "$APP" 2>/dev/null || "$APP/Contents/MacOS/ClaudePermissionAutomater"
