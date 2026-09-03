import ApplicationServices
import AppKit
import Foundation

enum AXHelpers {
    static func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let value else { return nil }
        return value as? T
    }

    static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        if let s: String = copyAttribute(element, attribute) { return s }
        if let n: NSNumber = copyAttribute(element, attribute) { return n.stringValue }
        return nil
    }

    static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        if let n: NSNumber = copyAttribute(element, attribute) { return n.boolValue }
        return nil
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        copyAttribute(element, kAXChildrenAttribute as String) ?? []
    }

    static func role(_ element: AXUIElement) -> String {
        stringAttribute(element, kAXRoleAttribute as String) ?? ""
    }

    static func title(_ element: AXUIElement) -> String {
        stringAttribute(element, kAXTitleAttribute as String) ?? ""
    }

    static func value(_ element: AXUIElement) -> String {
        stringAttribute(element, kAXValueAttribute as String) ?? ""
    }

    static func description(_ element: AXUIElement) -> String {
        stringAttribute(element, kAXDescriptionAttribute as String) ?? ""
    }

    static func help(_ element: AXUIElement) -> String {
        stringAttribute(element, kAXHelpAttribute as String) ?? ""
    }

    static func labelText(_ element: AXUIElement) -> String {
        [title(element), value(element), description(element), help(element)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let posRef: AXValue = copyAttribute(element, kAXPositionAttribute as String),
              let sizeRef: AXValue = copyAttribute(element, kAXSizeAttribute as String) else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef, .cgPoint, &position)
        AXValueGetValue(sizeRef, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    static func performPress(_ element: AXUIElement) -> Bool {
        if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            return true
        }
        guard let rect = frame(element), rect.width > 0, rect.height > 0 else { return false }
        return click(at: CGPoint(x: rect.midX, y: rect.midY))
    }

    static func click(at point: CGPoint) -> Bool {
        guard let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ),
        let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return false }
        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)
        return true
    }

    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt + open System Settings Accessibility pane so the user can enable the toggle.
    static func requestTrustAndOpenSettings() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        openAccessibilitySettings()
    }

    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) {
                return
            }
        }
        // Fallback: open Privacy & Security root
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openScreenRecordingSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
