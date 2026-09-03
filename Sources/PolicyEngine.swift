import Foundation

enum PolicyDecision {
    case approve(preferAlways: Bool)
    case skip(reason: String)
}

enum PolicyEngine {
    /// Phrases that must never be auto-approved, even with autoApproveAll.
    private static let dangerousPatterns = [
        "purchase", "buy now", "checkout", "payment", "pay for",
        "credit card", "bank account", "wire transfer",
        "create account", "sign up", "register",
        "change password", "reset password", "password",
        "send email", "send message", "compose email",
        "delete account", "transfer funds", "wallet",
    ]

    static func decide(dialog: ClaudePermissionDialog, config: AppConfig) -> PolicyDecision {
        let blob = (dialog.sourceText + " " + dialog.actionText).lowercased()
        if dangerousPatterns.contains(where: { blob.contains($0) }) {
            return .skip(reason: "Blocked dangerous action pattern")
        }

        if config.autoApproveAll {
            return .approve(preferAlways: config.preferAlwaysAllow)
        }

        if dialog.site.isEmpty {
            return .skip(reason: "Could not determine site")
        }

        guard DomainMatcher.matches(hostOrURL: dialog.site, trustedSites: config.trustedSites) else {
            return .skip(reason: "Site not in trusted list: \(dialog.site)")
        }

        let allowed = config.allowedActions.map { $0.lowercased() }
        let kind = dialog.actionKind.lowercased()
        let actionOK = allowed.contains { kind.contains($0) || $0.contains(kind) }
            || allowed.contains(where: { dialog.actionText.lowercased().contains($0) })

        guard actionOK else {
            return .skip(reason: "Action not allowed: \(dialog.actionKind)")
        }

        return .approve(preferAlways: config.preferAlwaysAllow)
    }
}
