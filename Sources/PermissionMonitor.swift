import ApplicationServices
import Foundation

final class PermissionMonitor {
    static let shared = PermissionMonitor()

    private let detector = DialogDetector()
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "permission.monitor", qos: .userInitiated)

    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var automationEnabled = true

    private var lastActionKey: String?
    private var lastActionAt: Date = .distantPast
    private var lastAxWarnAt: Date = .distantPast
    private var ocrCounter = 0

    var onActivity: ((ActivityEvent) -> Void)?
    var onStatusChange: (() -> Void)?

    private init() {}

    func start() {
        queue.async {
            guard !self.isRunning else { return }
            self.isRunning = true
            self.scheduleTimer()
            self.log("Monitor started", .info)
            DispatchQueue.main.async { self.onStatusChange?() }
        }
    }

    func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
            self.isRunning = false
            self.log("Monitor stopped", .warning)
            DispatchQueue.main.async { self.onStatusChange?() }
        }
    }

    func setPaused(_ paused: Bool) {
        queue.async {
            self.isPaused = paused
            self.log(paused ? "Paused" : "Resumed", .warning)
            DispatchQueue.main.async { self.onStatusChange?() }
        }
    }

    func setAutomationEnabled(_ enabled: Bool) {
        queue.async {
            self.automationEnabled = enabled
            self.log(enabled ? "Automation ON" : "Automation OFF", .info)
            DispatchQueue.main.async { self.onStatusChange?() }
        }
    }

    /// Manual test: send allow keystroke immediately.
    func forceAllowKeystroke() {
        queue.async {
            guard AXHelpers.isTrusted() else {
                self.log("Cannot send keystrokes — grant Accessibility first", .error)
                return
            }
            let prefer = ConfigStore.shared.config.preferAlwaysAllow
            let ok = KeystrokeApprover.sendAllow(preferAlways: prefer)
            self.log(ok ? "Forced allow keystroke sent" : "Forced keystroke failed", ok ? .success : .error)
        }
    }

    @discardableResult
    func ensureAccessibility() -> Bool {
        if AXHelpers.isTrusted() { return true }
        log("Accessibility permission required — open System Settings and enable this app", .warning)
        AXHelpers.requestTrustAndOpenSettings()
        return AXHelpers.isTrusted()
    }

    private func scheduleTimer() {
        timer?.cancel()
        let interval = max(0.12, Double(ConfigStore.shared.config.pollIntervalMs) / 1000.0)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in
            self?.tick()
        }
        t.resume()
        timer = t
    }

    private func tick() {
        guard isRunning, !isPaused, automationEnabled else { return }

        if !AXHelpers.isTrusted() {
            let now = Date()
            if now.timeIntervalSince(lastAxWarnAt) > 8 {
                lastAxWarnAt = now
                log("Waiting for Accessibility permission…", .warning)
            }
            return
        }

        let apps = ChromeFinder.axApplications()
        guard !apps.isEmpty else { return }

        let config = ConfigStore.shared.config

        // Fast path: Accessibility tree
        for app in apps {
            let probe = detector.dialogLikelyPresent(in: app)
            if probe.present {
                let dialog = detector.findDialogs(in: app).first
                    ?? ClaudePermissionDialog(
                        site: probe.site,
                        actionText: probe.action,
                        actionKind: probe.action.lowercased().contains("read") ? "read page content" : probe.action,
                        buttons: [],
                        sourceText: probe.source
                    )
                handle(dialog: dialog, config: config, via: "AX")
                return
            }
        }

        // Slower path: OCR every ~3rd tick (~0.4s) when AX sees nothing.
        ocrCounter += 1
        if ocrCounter % 3 == 0 {
            let ocr = ScreenOCRDetector.scanChromeForPermissionDialog()
            if ocr.present {
                let dialog = ClaudePermissionDialog(
                    site: ocr.site,
                    actionText: "read page content",
                    actionKind: "read page content",
                    buttons: [],
                    sourceText: ocr.text
                )
                handle(dialog: dialog, config: config, via: "OCR")
            }
        }
    }

    private func handle(dialog: ClaudePermissionDialog, config: AppConfig, via: String) {
        let key = "\(dialog.site)|\(dialog.actionKind)|\(via)"
        let now = Date()
        if key == lastActionKey, now.timeIntervalSince(lastActionAt) < 0.9 {
            return
        }

        log("Detected Claude permission dialog via \(via)\(dialog.site.isEmpty ? "" : " for \(dialog.site)")", .info)
        if !dialog.actionText.isEmpty {
            log("Action: \(dialog.actionText)", .info)
        }

        switch PolicyEngine.decide(dialog: dialog, config: config) {
        case .skip(let reason):
            log(reason, .warning)
            lastActionKey = key
            lastActionAt = now
            return

        case .approve(let preferAlways):
            if !dialog.site.isEmpty {
                log("Matched \(dialog.site)", .success)
            }

            // Prefer keystrokes — the overlay documents ↩ / ⌘↩ and AXPress is unreliable on it.
            let ok = KeystrokeApprover.sendAllow(preferAlways: preferAlways)
            if ok {
                log(
                    preferAlways
                        ? "Sent ⌘↩ (Always allow)"
                        : "Sent ↩ (Allow this action)",
                    .success
                )
            } else {
                log("Keystroke failed — trying AX button press", .warning)
                var clicked = false
                if preferAlways, let always = dialog.alwaysAllowButton {
                    clicked = AXHelpers.performPress(always.element)
                }
                if !clicked, let allow = dialog.allowButton ?? dialog.alwaysAllowButton {
                    clicked = AXHelpers.performPress(allow.element)
                }
                log(clicked ? "AX button press succeeded" : "All click strategies failed", clicked ? .success : .error)
            }

            lastActionKey = key
            lastActionAt = now
        }
    }

    private func log(_ message: String, _ level: ActivityLevel) {
        let event = ActivityEvent(date: Date(), message: message, level: level)
        DispatchQueue.main.async {
            self.onActivity?(event)
        }
    }
}
