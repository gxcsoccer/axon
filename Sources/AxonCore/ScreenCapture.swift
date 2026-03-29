import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Screen capture using ScreenCaptureKit (macOS 13+) with Retina handling.
public final class ScreenCapture: Sendable {

    public init() {}

    /// Capture the entire main display, returning base64-encoded JPEG.
    /// Coordinates in the returned image map to logical points (divided by scale factor).
    public func captureMainDisplay(quality: Double = 0.7, scale: Int = 1) async throws -> (base64: String, width: Int, height: Int) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw AxonError.noDisplay
        }
        return try await captureDisplay(display, quality: quality, scale: scale)
    }

    /// Capture a specific display by index.
    public func captureDisplay(index: Int, quality: Double = 0.7, scale: Int = 1) async throws -> (base64: String, width: Int, height: Int) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard index < content.displays.count else {
            throw AxonError.invalidDisplayIndex(index)
        }
        return try await captureDisplay(content.displays[index], quality: quality, scale: scale)
    }

    /// Capture a specific window by its owning app bundle ID and optional title.
    /// Falls back to system `screencapture` command if ScreenCaptureKit crashes (CGS_REQUIRE_INIT in CLI).
    public func captureWindow(bundleId: String, title: String? = nil, quality: Double = 0.7) async throws -> (base64: String, width: Int, height: Int) {
        do {
            return try await captureWindowSCKit(bundleId: bundleId, title: title, quality: quality)
        } catch {
            return try await captureWindowFallback(bundleId: bundleId, title: title)
        }
    }

    private func captureWindowSCKit(bundleId: String, title: String? = nil, quality: Double = 0.7) async throws -> (base64: String, width: Int, height: Int) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { w in
            guard w.owningApplication?.bundleIdentifier == bundleId else { return false }
            if let title { return w.title?.contains(title) == true }
            return true
        }) else {
            throw AxonError.windowNotFound(bundleId)
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width)
        config.height = Int(window.frame.height)
        config.scalesToFit = true
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try encodeImage(image, quality: quality)
    }

    /// Fallback window capture using system `screencapture -l <windowId>`.
    private func captureWindowFallback(bundleId: String, title: String? = nil) async throws -> (base64: String, width: Int, height: Int) {
        guard let windowId = findWindowId(bundleId: bundleId, title: title) else {
            throw AxonError.windowNotFound(bundleId)
        }
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("axon-wincap-\(UUID().uuidString).jpg").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-l", String(windowId), "-x", "-t", "jpg", tempPath]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let data = FileManager.default.contents(atPath: tempPath) else {
            let errMsg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw AxonError.actionFailed("Window screenshot failed (exit \(process.terminationStatus)): \(errMsg). Check Screen Recording permission.")
        }
        try? FileManager.default.removeItem(atPath: tempPath)
        guard let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AxonError.imageEncodingFailed
        }
        return (base64: data.base64EncodedString(), width: cgImage.width, height: cgImage.height)
    }

    private func findWindowId(bundleId: String, title: String?) -> CGWindowID? {
        guard let pid = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleId })?
            .processIdentifier else { return nil }
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in windowList {
            guard let ownerPid = info[kCGWindowOwnerPID as String] as? Int32, ownerPid == pid else { continue }
            if let title, let winTitle = info[kCGWindowName as String] as? String {
                if !winTitle.contains(title) { continue }
            }
            if let windowId = info[kCGWindowNumber as String] as? CGWindowID {
                return windowId
            }
        }
        return nil
    }

    /// Capture a rectangular region of a display.
    public func captureRegion(x: Int, y: Int, width: Int, height: Int, displayIndex: Int = 0, quality: Double = 0.7) async throws -> (base64: String, width: Int, height: Int) {
        guard width > 0, height > 0 else {
            throw AxonError.actionFailed("Region width and height must be positive")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard displayIndex < content.displays.count else {
            throw AxonError.invalidDisplayIndex(displayIndex)
        }
        let display = content.displays[displayIndex]
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: x, y: y, width: width, height: height)
        config.width = width
        config.height = height
        config.scalesToFit = true
        config.showsCursor = true

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try encodeImage(image, quality: quality)
    }

    /// Get information about all connected displays.
    public func getScreenInfo() async throws -> ScreenInfo {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displays = content.displays.enumerated().map { (i, d) in
            DisplayInfo(index: i, width: d.width, height: d.height, isMain: i == 0)
        }
        return ScreenInfo(displayCount: displays.count, displays: displays)
    }

    // MARK: - Internal

    private func captureDisplay(_ display: SCDisplay, quality: Double, scale: Int) async throws -> (base64: String, width: Int, height: Int) {
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        // Use logical dimensions (scaled down for efficiency and to match CGEvent coordinate space)
        config.width = display.width / max(scale, 1)
        config.height = display.height / max(scale, 1)
        config.scalesToFit = true
        config.showsCursor = true

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try encodeImage(image, quality: quality)
    }

    private func encodeImage(_ image: CGImage, quality: Double) throws -> (base64: String, width: Int, height: Int) {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            throw AxonError.imageEncodingFailed
        }
        return (base64: jpeg.base64EncodedString(), width: image.width, height: image.height)
    }
}

// MARK: - Errors

public enum AxonError: Error, LocalizedError {
    case noDisplay
    case invalidDisplayIndex(Int)
    case windowNotFound(String)
    case imageEncodingFailed
    case appNotFound(String)
    case appNotRunning(String)
    case elementNotFound
    case actionFailed(String)
    case securityDenied(String)
    case rateLimited
    case scriptError(String)
    case permissionDenied(String)

    public var errorDescription: String? {
        switch self {
        case .noDisplay: "No display found. Grant Screen Recording permission: System Settings > Privacy & Security > Screen Recording"
        case .invalidDisplayIndex(let i): "Invalid display index: \(i)"
        case .windowNotFound(let id): "Window not found for bundle: \(id)"
        case .imageEncodingFailed: "Failed to encode image"
        case .appNotFound(let id): "App not found: \(id)"
        case .appNotRunning(let id): "App not running: \(id)"
        case .elementNotFound: "UI element not found. Check Accessibility permission: System Settings > Privacy & Security > Accessibility"
        case .actionFailed(let msg): "Action failed: \(msg)"
        case .securityDenied(let msg): "Security denied: \(msg)"
        case .rateLimited: "Rate limit exceeded"
        case .scriptError(let msg): "Script error: \(msg)"
        case .permissionDenied(let permission): "Permission denied: \(permission). Go to System Settings > Privacy & Security to grant access."
        }
    }
}
