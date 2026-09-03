import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusController = StatusItemController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController.setup()

        // Prompt for Accessibility on first launch if needed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            _ = PermissionMonitor.shared.ensureAccessibility()
            PermissionMonitor.shared.setAutomationEnabled(true)
            PermissionMonitor.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        PermissionMonitor.shared.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Menu-bar only; ignore dock reopen
        false
    }
}

// Retain delegate for the lifetime of the process (must not be a temporary local).
private final class AppRuntime {
    static let shared = AppRuntime()
    let app = NSApplication.shared
    let delegate = AppDelegate()

    func run() {
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

AppRuntime.shared.run()
