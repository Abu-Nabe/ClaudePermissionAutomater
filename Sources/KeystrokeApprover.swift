import AppKit
import ApplicationServices
import Foundation

enum KeystrokeApprover {
    /// Claude's dialog: Return = Allow, Cmd+Return = Always allow, Esc = Decline.
    static func sendAllow(preferAlways: Bool) -> Bool {
        guard activateChrome() else { return false }
        // Small settle so the overlay receives key focus.
        usleep(80_000)
        if preferAlways {
            return postKey(keyCode: 36, command: true) // Return with ⌘
        }
        return postKey(keyCode: 36, command: false) // Return
    }

    private static func activateChrome() -> Bool {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.google.Chrome"
        }
        guard let chrome = apps.first else { return false }
        return chrome.activate(options: [.activateIgnoringOtherApps])
    }

    private static func postKey(keyCode: CGKeyCode, command: Bool) -> Bool {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        if command {
            down.flags = .maskCommand
            up.flags = .maskCommand
        }
        down.post(tap: .cghidEventTap)
        usleep(20_000)
        up.post(tap: .cghidEventTap)
        return true
    }
}
