import ApplicationServices
import Foundation

struct DetectedButton {
    let title: String
    let element: AXUIElement
}

struct ClaudePermissionDialog {
    let site: String
    let actionText: String
    let actionKind: String
    let buttons: [DetectedButton]
    let sourceText: String

    var allowButton: DetectedButton? {
        buttons.first { $0.title.localizedCaseInsensitiveContains("Allow this action") }
            ?? buttons.first {
                let t = $0.title.lowercased()
                return t == "allow" || (t.contains("allow") && !t.contains("always") && !t.contains("decline"))
            }
    }

    var alwaysAllowButton: DetectedButton? {
        buttons.first {
            let t = $0.title.lowercased()
            return t.contains("always allow")
        }
    }

    var declineButton: DetectedButton? {
        buttons.first { $0.title.localizedCaseInsensitiveContains("Decline") }
    }
}

enum ActivityLevel {
    case info
    case success
    case warning
    case error
}

struct ActivityEvent: Identifiable {
    let id = UUID()
    let date: Date
    let message: String
    let level: ActivityLevel

    var timestamp: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
