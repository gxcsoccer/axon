import AppKit
import Foundation

/// App lifecycle management via NSWorkspace.
public final class AppManager: Sendable {
    public init() {}

    /// List all running GUI applications.
    public func listRunningApps() -> [AppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let name = app.localizedName,
                      let bundleId = app.bundleIdentifier else { return nil }
                return AppInfo(
                    name: name,
                    bundleId: bundleId,
                    pid: app.processIdentifier,
                    isActive: app.isActive
                )
            }
    }

    /// Launch an app by bundle ID. Returns the app info once launched.
    @discardableResult
    public func launchApp(bundleId: String) async throws -> AppInfo {
        // Check if already running
        if let existing = findRunningApp(bundleId: bundleId) {
            existing.activate()
            return appInfoFrom(existing)
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            throw AxonError.appNotFound(bundleId)
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        // Wait briefly for the app to initialize
        try await Task.sleep(for: .milliseconds(500))
        return appInfoFrom(app)
    }

    /// Activate (bring to front) an app by bundle ID.
    public func activateApp(bundleId: String) throws {
        guard let app = findRunningApp(bundleId: bundleId) else {
            throw AxonError.appNotRunning(bundleId)
        }
        app.activate()
    }

    /// Quit an app by bundle ID.
    public func quitApp(bundleId: String) throws {
        guard let app = findRunningApp(bundleId: bundleId) else {
            throw AxonError.appNotRunning(bundleId)
        }
        app.terminate()
    }

    /// Get info about a running app.
    public func getAppInfo(bundleId: String) -> AppInfo? {
        findRunningApp(bundleId: bundleId).map { appInfoFrom($0) }
    }

    // MARK: - Internal

    private func findRunningApp(bundleId: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleId }
    }

    private func appInfoFrom(_ app: NSRunningApplication) -> AppInfo {
        AppInfo(
            name: app.localizedName ?? "Unknown",
            bundleId: app.bundleIdentifier ?? "",
            pid: app.processIdentifier,
            isActive: app.isActive
        )
    }
}
