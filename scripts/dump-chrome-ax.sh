#!/usr/bin/env bash
# Dump Chrome accessibility tree while a Claude permission dialog is visible.
# Usage: ./scripts/dump-chrome-ax.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/chrome-ax-dump.txt"
mkdir -p "$ROOT/build"

swift - <<'SWIFT' > "$OUT"
import AppKit
import ApplicationServices
import Foundation

func attr(_ el: AXUIElement, _ name: String) -> String {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success, let v else { return "" }
    return "\(v)"
}

func dump(_ el: AXUIElement, depth: Int, budget: inout Int) {
    if budget <= 0 || depth > 20 { return }
    budget -= 1
    let indent = String(repeating: "  ", count: depth)
    let role = attr(el, kAXRoleAttribute as String)
    let title = attr(el, kAXTitleAttribute as String)
    let value = attr(el, kAXValueAttribute as String)
    let desc = attr(el, kAXDescriptionAttribute as String)
    let bits = [role, title, value, desc].filter { !$0.isEmpty }.joined(separator: " | ")
    print("\(indent)\(bits)")
    var children: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children) == .success,
          let kids = children as? [AXUIElement] else { return }
    for c in kids { dump(c, depth: depth + 1, budget: &budget) }
}

guard AXIsProcessTrusted() else {
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(opts)
    fputs("Grant Accessibility to this process (Terminal/swift), then re-run.\n", stderr)
    exit(1)
}

let chrome = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.google.Chrome" }
guard let chrome else {
    fputs("Google Chrome is not running.\n", stderr)
    exit(1)
}

let app = AXUIElementCreateApplication(chrome.processIdentifier)
var budget = 2500
dump(app, depth: 0, budget: &budget)
print("\n--- done (nodes visited up to budget) ---")
SWIFT

echo "Wrote $OUT"
