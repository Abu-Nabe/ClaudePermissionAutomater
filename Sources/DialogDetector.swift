import ApplicationServices
import AppKit
import Foundation

enum ChromeFinder {
    static let bundleIDs = ["com.google.Chrome"]

    static func runningChromeApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard let bid = app.bundleIdentifier else { return false }
            return bundleIDs.contains(bid)
        }
    }

    static func axApplications() -> [AXUIElement] {
        runningChromeApps().map { AXUIElementCreateApplication($0.processIdentifier) }
    }
}

final class DialogDetector {
    private let maxDepth = 40
    private let maxNodes = 8_000

    /// Strong markers from the real Claude for Chrome overlay.
    private let strongMarkers = [
        "new permissions required",
        "claude wants to",
        "always allow actions on this site",
        "allow this action",
    ]

    private let claudeContext = [
        "claude for chrome",
        "claude wants to",
        "new permissions required",
        "revoke site permissions",
    ]

    func findDialogs(in app: AXUIElement) -> [ClaudePermissionDialog] {
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement], !list.isEmpty else {
            // Still try the app root — some overlays attach oddly.
            var visited = 0
            if let d = search(element: app, depth: 0, visited: &visited) {
                return [d]
            }
            return []
        }

        var ordered = list
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
           CFGetTypeID(focused!) == AXUIElementGetTypeID() {
            let focusedEl = focused as! AXUIElement
            ordered = [focusedEl] + list.filter { !CFEqual($0, focusedEl) }
        }

        for window in ordered {
            var visited = 0
            if let dialog = search(element: window, depth: 0, visited: &visited) {
                return [dialog]
            }
        }
        return []
    }

    /// Lightweight presence check used for keystroke approval.
    func dialogLikelyPresent(in app: AXUIElement) -> (present: Bool, site: String, action: String, source: String) {
        if let d = findDialogs(in: app).first {
            return (true, d.site, d.actionText, d.sourceText)
        }
        // Broader text harvest if structured parse failed.
        var texts: [String] = []
        var visited = 0
        harvestText(app, depth: 0, texts: &texts, visited: &visited)
        let joined = texts.joined(separator: "\n")
        let lower = joined.lowercased()
        let hasStrong = strongMarkers.filter { lower.contains($0) }.count >= 2
            || (lower.contains("new permissions required") && lower.contains("allow this action"))
            || (lower.contains("claude wants to") && lower.contains("allow this action"))
        if hasStrong {
            return (
                true,
                extractSite(from: joined) ?? "",
                extractActionPhrase(from: joined) ?? "unknown",
                joined
            )
        }
        return (false, "", "", "")
    }

    private func search(element: AXUIElement, depth: Int, visited: inout Int) -> ClaudePermissionDialog? {
        if depth > maxDepth || visited > maxNodes { return nil }
        visited += 1

        let label = AXHelpers.labelText(element).lowercased()
        let hit = strongMarkers.contains { label.contains($0) }
            || claudeContext.contains { label.contains($0) }

        if hit, let dialog = inspectCandidate(element) {
            return dialog
        }

        // Prefer scanning children of likely containers first.
        let kids = AXHelpers.children(element)
        for child in kids {
            let childLabel = AXHelpers.labelText(child).lowercased()
            let childHit = strongMarkers.contains { childLabel.contains($0) }
                || childLabel.contains("claude")
                || childLabel.contains("permission")
            if childHit, let found = search(element: child, depth: depth + 1, visited: &visited) {
                return found
            }
        }
        for child in kids {
            if let found = search(element: child, depth: depth + 1, visited: &visited) {
                return found
            }
        }
        return nil
    }

    private func inspectCandidate(_ root: AXUIElement) -> ClaudePermissionDialog? {
        // Walk up a few parents so we capture the full dialog card.
        var node: AXUIElement? = root
        for _ in 0..<6 {
            guard let current = node else { break }
            var texts: [String] = []
            var buttons: [DetectedButton] = []
            collectShallow(current, depth: 0, maxDepth: 10, texts: &texts, buttons: &buttons)

            let joined = texts.joined(separator: "\n")
            let lower = joined.lowercased()

            let hasClaude = claudeContext.contains { lower.contains($0) }
                || lower.contains("claude wants to")
            let hasAllow = lower.contains("allow this action") || lower.contains("always allow")
            let hasHeader = lower.contains("new permissions required")

            if (hasClaude || hasHeader) && hasAllow {
                let site = extractSite(from: joined) ?? ""
                let actionText = extractActionPhrase(from: joined) ?? "unknown action"
                return ClaudePermissionDialog(
                    site: site,
                    actionText: actionText,
                    actionKind: classifyAction(actionText),
                    buttons: buttons,
                    sourceText: joined
                )
            }

            var parent: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
               let parent {
                node = (parent as! AXUIElement)
            } else {
                break
            }
        }
        return nil
    }

    private func harvestText(_ element: AXUIElement, depth: Int, texts: inout [String], visited: inout Int) {
        if depth > 35 || visited > maxNodes { return }
        visited += 1
        let label = AXHelpers.labelText(element).trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { texts.append(label) }
        // Early exit once we have enough signal.
        let lower = texts.suffix(80).joined(separator: " ").lowercased()
        if lower.contains("new permissions required") && lower.contains("allow this action") {
            return
        }
        for child in AXHelpers.children(element) {
            harvestText(child, depth: depth + 1, texts: &texts, visited: &visited)
            let check = texts.suffix(120).joined(separator: " ").lowercased()
            if check.contains("new permissions required") && check.contains("allow this action") {
                return
            }
        }
    }

    private func collectShallow(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        texts: inout [String],
        buttons: inout [DetectedButton]
    ) {
        if depth > maxDepth { return }
        let role = AXHelpers.role(element)
        let label = AXHelpers.labelText(element).trimmingCharacters(in: .whitespacesAndNewlines)

        if !label.isEmpty {
            texts.append(label)
            let lower = label.lowercased()
            let isAllowish = lower.contains("allow this action")
                || lower.contains("always allow")
                || lower == "allow"
                || lower.contains("decline")
            let isButton = role == (kAXButtonRole as String)
                || role.lowercased().contains("button")
                || role == "AXButton"

            if isAllowish {
                if !buttons.contains(where: { $0.title.caseInsensitiveCompare(label) == .orderedSame }) {
                    buttons.append(DetectedButton(title: label, element: element))
                }
            } else if isButton && (lower.contains("allow") || lower.contains("decline")) {
                if !buttons.contains(where: { $0.title.caseInsensitiveCompare(label) == .orderedSame }) {
                    buttons.append(DetectedButton(title: label, element: element))
                }
            }
        }

        for child in AXHelpers.children(element) {
            collectShallow(child, depth: depth + 1, maxDepth: maxDepth, texts: &texts, buttons: &buttons)
        }
    }

    private func extractSite(from text: String) -> String? {
        let patterns = [
            #"on:\s*((?:www\.)?[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})"#,
            #"on\s+((?:www\.)?[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})"#,
            #"(https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(?:/[^\s]*)?)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range),
                   match.numberOfRanges > 1,
                   let r = Range(match.range(at: 1), in: text) {
                    return DomainMatcher.normalize(String(text[r]))
                }
            }
        }
        return nil
    }

    private func extractActionPhrase(from text: String) -> String? {
        let lower = text.lowercased()
        let markers = ["claude wants to ", "claude in chrome wants to ", "allow claude to "]
        for marker in markers {
            if let range = lower.range(of: marker) {
                let after = text[range.upperBound...]
                let line = after.split(whereSeparator: { $0 == "\n" || $0 == "." }).first.map(String.init) ?? String(after)
                let cleaned = line
                    .replacingOccurrences(of: #"\bon:.*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        if lower.contains("read page content") { return "read page content" }
        return nil
    }

    private func classifyAction(_ phrase: String) -> String {
        let p = phrase.lowercased()
        if p.contains("read") || p.contains("page content") || p.contains("content") { return "read page content" }
        if p.contains("navigate") || p.contains("browse") || p.contains("go to") { return "browse" }
        if p.contains("click") { return "click" }
        if p.contains("type") || p.contains("input") || p.contains("fill") || p.contains("enter text") { return "type" }
        return p
    }
}
