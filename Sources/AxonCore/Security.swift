import Foundation

/// Multi-layered security gate for all automation actions.
///
/// Layers:
///   1. App allowlist/denylist
///   2. AX role denylist (e.g., AXSecureTextField)
///   3. Rate limiting
///   4. Audit logging
public actor SecurityGate {
    private var config: SecurityConfig
    private var actionTimestamps: [Date] = []
    private var consecutiveFailures: Int = 0
    private var auditLog: [AuditEntry] = []
    private let auditFileURL: URL?

    public init(config: SecurityConfig = SecurityConfig(), auditDir: URL? = nil) {
        self.config = config
        if let dir = auditDir {
            self.auditFileURL = dir.appendingPathComponent("axon-audit.jsonl")
        } else {
            self.auditFileURL = nil
        }
    }

    // MARK: - Config

    public func updateConfig(_ config: SecurityConfig) {
        self.config = config
    }

    public func getConfig() -> SecurityConfig {
        config
    }

    // MARK: - Authorization Check

    /// Check whether an action targeting an app is allowed.
    /// Returns nil if allowed, or an error string if denied.
    public func authorize(action: String, bundleId: String?) -> String? {
        // Check rate limit
        pruneOldTimestamps()
        if actionTimestamps.count >= config.maxActionsPerMinute {
            return "Rate limit exceeded (\(config.maxActionsPerMinute)/min)"
        }

        // Check consecutive failures
        if consecutiveFailures >= config.maxConsecutiveFailures {
            return "Too many consecutive failures (\(consecutiveFailures)). Paused for safety."
        }

        // Check app permissions
        if let bundleId {
            // Denied apps
            for pattern in config.deniedApps {
                if bundleId == pattern || (pattern.hasSuffix(".*") && bundleId.hasPrefix(String(pattern.dropLast(2)))) {
                    return "App '\(bundleId)' is in deny list"
                }
            }

            // If allowlist is non-empty, app must be listed
            if !config.allowedApps.isEmpty {
                guard let perm = config.allowedApps[bundleId] else {
                    return "App '\(bundleId)' is not in allow list"
                }
                if perm.level == .deny {
                    return "App '\(bundleId)' permission level is deny"
                }
            }
        }

        return nil
    }

    /// Check whether interacting with a specific AX role is allowed.
    public func authorizeAXRole(_ role: String) -> String? {
        if config.deniedAXRoles.contains(role) {
            return "AX role '\(role)' is denied (potential password field)"
        }
        return nil
    }

    /// Get the permission level for an app. Returns `.auto` for unlisted apps when allowlist is empty.
    public func permissionLevel(for bundleId: String) -> PermissionLevel {
        if let perm = config.allowedApps[bundleId] {
            return perm.level
        }
        return config.allowedApps.isEmpty ? .auto : .deny
    }

    // MARK: - Tracking

    public func recordAction(action: String, targetApp: String?, details: String?, success: Bool) {
        let entry = AuditEntry(action: action, targetApp: targetApp, details: details, success: success)
        auditLog.append(entry)
        actionTimestamps.append(Date())

        if success {
            consecutiveFailures = 0
        } else {
            consecutiveFailures += 1
        }

        // Persist to file
        if let url = auditFileURL {
            persistEntry(entry, to: url)
        }

        // Keep audit log manageable in memory
        if auditLog.count > 1000 {
            auditLog.removeFirst(500)
        }
    }

    public func resetFailureCount() {
        consecutiveFailures = 0
    }

    public func getRecentAuditLog(count: Int = 50) -> [AuditEntry] {
        Array(auditLog.suffix(count))
    }

    // MARK: - Internal

    private func pruneOldTimestamps() {
        let cutoff = Date().addingTimeInterval(-60)
        actionTimestamps.removeAll { $0 < cutoff }
    }

    private func persistEntry(_ entry: AuditEntry, to url: URL) {
        do {
            let data = try JSONEncoder().encode(entry)
            guard var line = String(data: data, encoding: .utf8) else { return }
            line += "\n"
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                handle.closeFile()
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            // Silently fail — audit should not break operations
        }
    }
}

// MARK: - Config Loading

extension SecurityConfig {
    /// Load config from a JSON file, or return default if not found.
    public static func load(from url: URL) -> SecurityConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(SecurityConfig.self, from: data) else {
            return SecurityConfig()
        }
        return config
    }

    /// Save config to a JSON file.
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}
