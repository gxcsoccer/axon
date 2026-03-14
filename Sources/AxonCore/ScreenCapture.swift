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
    public func captureWindow(bundleId: String, title: String? = nil, quality: Double = 0.7) async throws -> (base64: String, width: Int, height: Int) {
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

    // MARK: - Internal

    private func captureDisplay(_ display: SCDisplay, quality: Double, scale: Int) async throws -> (base64: String, width: Int, height: Int) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
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

    public var errorDescription: String? {
        switch self {
        case .noDisplay: "No display found"
        case .invalidDisplayIndex(let i): "Invalid display index: \(i)"
        case .windowNotFound(let id): "Window not found for bundle: \(id)"
        case .imageEncodingFailed: "Failed to encode image"
        case .appNotFound(let id): "App not found: \(id)"
        case .appNotRunning(let id): "App not running: \(id)"
        case .elementNotFound: "UI element not found"
        case .actionFailed(let msg): "Action failed: \(msg)"
        case .securityDenied(let msg): "Security denied: \(msg)"
        case .rateLimited: "Rate limit exceeded"
        case .scriptError(let msg): "Script error: \(msg)"
        }
    }
}
