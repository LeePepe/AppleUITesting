import Foundation

#if os(macOS)
import ScreenCaptureKit
import AppKit

/// Captures a screenshot of the main display as PNG data.
@MainActor
public func captureScreen() async throws -> Data {
    try await captureWithScreenCaptureKit()
}

@MainActor
private func captureWithScreenCaptureKit() async throws -> Data {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let display = content.displays.first else {
        throw ScreenCaptureError.noDisplayFound
    }

    let config = SCStreamConfiguration()
    config.width = display.width
    config.height = display.height

    let filter = SCContentFilter(display: display, excludingWindows: [])
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

    let rep = NSBitmapImageRep(cgImage: image)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        throw ScreenCaptureError.encodingFailed
    }
    return pngData
}

#elseif os(iOS)
import UIKit

/// Captures a screenshot of the key window as PNG data.
@MainActor
public func captureScreen() async throws -> Data {
    guard let window = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap(\.windows)
        .first(where: \.isKeyWindow)
    else {
        throw ScreenCaptureError.noDisplayFound
    }

    let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
    let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
    guard let data = image.pngData() else { throw ScreenCaptureError.encodingFailed }
    return data
}
#endif

public enum ScreenCaptureError: Error, LocalizedError {
    case noDisplayFound
    case captureAPIFailed
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .noDisplayFound: return "No display or window found"
        case .captureAPIFailed: return "CGWindowListCreateImage failed"
        case .encodingFailed: return "Failed to encode screenshot as PNG"
        }
    }
}
