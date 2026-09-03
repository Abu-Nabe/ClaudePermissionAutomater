import Foundation

struct AppConfig: Codable, Equatable {
    /// When true, auto-approve every Claude permission dialog (Chrome only).
    var autoApproveAll: Bool
    /// Used when autoApproveAll is false.
    var trustedSites: [String]
    var allowedActions: [String]
    var preferAlwaysAllow: Bool
    var pollIntervalMs: Int

    static let defaultAllowedActions = [
        "read page content",
        "browse",
        "navigate",
        "click",
        "type",
        "input",
    ]

    static let `default` = AppConfig(
        autoApproveAll: true,
        trustedSites: ["reddit.com"],
        allowedActions: defaultAllowedActions,
        preferAlwaysAllow: true,
        pollIntervalMs: 250
    )
}

final class ConfigStore {
    static let shared = ConfigStore()

    private let url: URL
    private let queue = DispatchQueue(label: "config.store")
    private(set) var config: AppConfig

    var onChange: ((AppConfig) -> Void)?

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ClaudePermissionAutomater", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
        } else {
            config = .default
            save()
        }
    }

    func update(_ mutate: (inout AppConfig) -> Void) {
        queue.sync {
            mutate(&config)
            save()
            let snapshot = config
            DispatchQueue.main.async { self.onChange?(snapshot) }
        }
    }

    func addTrustedSite(_ raw: String) {
        let normalized = DomainMatcher.normalize(raw)
        guard !normalized.isEmpty else { return }
        update { cfg in
            if !cfg.trustedSites.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
                cfg.trustedSites.append(normalized)
            }
        }
    }

    func removeTrustedSite(_ site: String) {
        update { cfg in
            cfg.trustedSites.removeAll { $0.caseInsensitiveCompare(site) == .orderedSame }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

enum DomainMatcher {
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("http://") || s.hasPrefix("https://") {
            if let host = URL(string: s)?.host { s = host }
        }
        if s.hasPrefix("www.") { s = String(s.dropFirst(4)) }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func matches(hostOrURL: String, trustedSites: [String]) -> Bool {
        let host = normalize(hostOrURL)
        guard !host.isEmpty else { return false }
        for site in trustedSites {
            let t = normalize(site)
            if host == t || host.hasSuffix("." + t) { return true }
        }
        return false
    }
}
