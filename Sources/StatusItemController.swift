import AppKit
import Foundation

final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem!
    private var activityLog: [ActivityEvent] = []
    private let maxLog = 40

    private lazy var menu: NSMenu = {
        let m = NSMenu()
        m.autoenablesItems = false
        return m
    }()

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checkmark.shield", accessibilityDescription: "Claude Permission Automation")
            button.image?.isTemplate = true
            button.toolTip = "Claude Permission Automation"
        }
        statusItem.menu = menu
        rebuildMenu()

        PermissionMonitor.shared.onActivity = { [weak self] event in
            self?.append(event)
        }
        PermissionMonitor.shared.onStatusChange = { [weak self] in
            self?.rebuildMenu()
        }
        ConfigStore.shared.onChange = { [weak self] _ in
            self?.rebuildMenu()
        }
    }

    private func append(_ event: ActivityEvent) {
        activityLog.insert(event, at: 0)
        if activityLog.count > maxLog {
            activityLog = Array(activityLog.prefix(maxLog))
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let monitor = PermissionMonitor.shared
        let config = ConfigStore.shared.config
        let trusted = AXHelpers.isTrusted()

        addHeader("Claude Permission Automation")

        let status = statusLine(monitor: monitor)
        addDisabled(status)

        if !trusted {
            menu.addItem(.separator())
            addDisabled("⚠ BLOCKED: Accessibility not granted")
            addDisabled("Detection cannot run until you enable it.")
            let grant = NSMenuItem(
                title: "Open Accessibility Settings…",
                action: #selector(requestAccessibility),
                keyEquivalent: ""
            )
            grant.target = self
            menu.addItem(grant)
            let screen = NSMenuItem(
                title: "Open Screen Recording Settings…",
                action: #selector(openScreenRecording),
                keyEquivalent: ""
            )
            screen.target = self
            menu.addItem(screen)
            addDisabled("Add ClaudePermissionAutomater → toggle ON")
            addDisabled("Then Quit & reopen this app")
            menu.addItem(.separator())
            let quitBlocked = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
            quitBlocked.target = self
            menu.addItem(quitBlocked)
            return
        }

        menu.addItem(.separator())

        let automation = NSMenuItem(
            title: "Automation: \(monitor.automationEnabled && !monitor.isPaused ? "ON" : "OFF")",
            action: #selector(toggleAutomation),
            keyEquivalent: ""
        )
        automation.target = self
        menu.addItem(automation)

        let pauseTitle = monitor.isPaused ? "Resume" : "Pause"
        let pause = NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: "p")
        pause.target = self
        pause.isEnabled = monitor.automationEnabled
        menu.addItem(pause)

        menu.addItem(.separator())

        addHeader("Mode")
        let allItem = NSMenuItem(
            title: "Auto-approve all Claude dialogs",
            action: #selector(toggleAutoApproveAll),
            keyEquivalent: ""
        )
        allItem.target = self
        allItem.state = config.autoApproveAll ? .on : .off
        menu.addItem(allItem)

        let alwaysItem = NSMenuItem(
            title: "Prefer “Always allow on this site”",
            action: #selector(togglePreferAlways),
            keyEquivalent: ""
        )
        alwaysItem.target = self
        alwaysItem.state = config.preferAlwaysAllow ? .on : .off
        menu.addItem(alwaysItem)

        menu.addItem(.separator())
        addHeader("Trusted Sites")
        if config.trustedSites.isEmpty {
            addDisabled("(none — using auto-approve all)")
        } else {
            for site in config.trustedSites {
                let item = NSMenuItem(title: site, action: #selector(removeSite(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = site
                item.toolTip = "Click to remove"
                menu.addItem(item)
            }
        }
        let addSite = NSMenuItem(title: "Add site…", action: #selector(addSite), keyEquivalent: "")
        addSite.target = self
        menu.addItem(addSite)

        menu.addItem(.separator())
        addHeader("Permission types")
        for action in AppConfig.defaultAllowedActions {
            let enabled = config.allowedActions.contains { $0.caseInsensitiveCompare(action) == .orderedSame }
            let item = NSMenuItem(title: action.capitalized, action: #selector(toggleAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action
            item.state = enabled ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        addHeader("Activity")
        if activityLog.isEmpty {
            addDisabled("No activity yet")
        } else {
            for event in activityLog.prefix(12) {
                addDisabled("\(event.timestamp) - \(event.message)")
            }
        }

        menu.addItem(.separator())
        addDisabled("Accessibility: Granted")

        let force = NSMenuItem(
            title: "Test: send Allow keystroke now",
            action: #selector(forceKeystroke),
            keyEquivalent: ""
        )
        force.target = self
        menu.addItem(force)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func statusLine(monitor: PermissionMonitor) -> String {
        if !AXHelpers.isTrusted() {
            return "Status: ● Needs Accessibility"
        }
        if !monitor.isRunning {
            return "Status: ● Stopped"
        }
        if monitor.isPaused {
            return "Status: ● Paused"
        }
        if !monitor.automationEnabled {
            return "Status: ● Idle (automation off)"
        }
        if ChromeFinder.runningChromeApps().isEmpty {
            return "Status: ● Running (Chrome not open)"
        }
        return "Status: ● Running"
    }

    private func addHeader(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addDisabled(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    @objc private func toggleAutomation() {
        let next = !PermissionMonitor.shared.automationEnabled
        PermissionMonitor.shared.setAutomationEnabled(next)
        if next {
            PermissionMonitor.shared.setPaused(false)
        }
        rebuildMenu()
    }

    @objc private func togglePause() {
        PermissionMonitor.shared.setPaused(!PermissionMonitor.shared.isPaused)
        rebuildMenu()
    }

    @objc private func toggleAutoApproveAll() {
        ConfigStore.shared.update { $0.autoApproveAll.toggle() }
    }

    @objc private func togglePreferAlways() {
        ConfigStore.shared.update { $0.preferAlwaysAllow.toggle() }
    }

    @objc private func addSite() {
        let alert = NSAlert()
        alert.messageText = "Add trusted site"
        alert.informativeText = "Enter a domain (e.g. reddit.com). Used when “Auto-approve all” is off."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "example.com"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            ConfigStore.shared.addTrustedSite(field.stringValue)
        }
    }

    @objc private func removeSite(_ sender: NSMenuItem) {
        guard let site = sender.representedObject as? String else { return }
        ConfigStore.shared.removeTrustedSite(site)
    }

    @objc private func toggleAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? String else { return }
        ConfigStore.shared.update { cfg in
            if let idx = cfg.allowedActions.firstIndex(where: { $0.caseInsensitiveCompare(action) == .orderedSame }) {
                cfg.allowedActions.remove(at: idx)
            } else {
                cfg.allowedActions.append(action)
            }
        }
    }

    @objc private func requestAccessibility() {
        AXHelpers.requestTrustAndOpenSettings()
        PermissionMonitor.shared.ensureAccessibility()
        // Poll until granted so the menu unlocks after the user flips the toggle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.rebuildMenu()
            if !AXHelpers.isTrusted() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self?.rebuildMenu()
                }
            }
        }
    }

    @objc private func openScreenRecording() {
        AXHelpers.openScreenRecordingSettings()
    }

    @objc private func forceKeystroke() {
        if !AXHelpers.isTrusted() {
            let event = ActivityEvent(
                date: Date(),
                message: "Cannot send keystrokes — grant Accessibility first",
                level: .error
            )
            append(event)
            AXHelpers.requestTrustAndOpenSettings()
            return
        }
        PermissionMonitor.shared.forceAllowKeystroke()
        rebuildMenu()
    }

    @objc private func quit() {
        PermissionMonitor.shared.stop()
        NSApp.terminate(nil)
    }
}
