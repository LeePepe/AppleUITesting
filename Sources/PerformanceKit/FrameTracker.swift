import Foundation
import QuartzCore
#if os(macOS)
import AppKit
#endif

/// Tracks display frame rate using `CADisplayLink` (macOS 14+ / iOS 3.1+).
/// Use in performance tests to detect dropped frames or jank.
public final class FrameTracker: @unchecked Sendable {
    private var displayLink: CADisplayLink?
    private var frameTimestamps: [CFTimeInterval] = []
    private let lock = NSLock()

    public init() {}

    /// Starts tracking frames.
    public func start() {
        stop()
        frameTimestamps = []
#if os(macOS)
        guard let link = NSScreen.main?.displayLink(target: self, selector: #selector(frameTick(_:))) else { return }
        link.add(to: .main, forMode: .common)
        displayLink = link
#else
        let link = CADisplayLink(target: self, selector: #selector(frameTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
#endif
    }

    /// Stops tracking and returns a `FrameMetrics` snapshot.
    @discardableResult
    public func stop() -> FrameMetrics {
        displayLink?.invalidate()
        displayLink = nil
        let timestamps = lock.withLock { frameTimestamps }
        return FrameMetrics(timestamps: timestamps)
    }

    @objc private func frameTick(_ link: CADisplayLink) {
        lock.withLock { frameTimestamps.append(link.timestamp) }
    }
}

/// Computed metrics derived from a sequence of frame timestamps.
public struct FrameMetrics: Sendable {
    public let timestamps: [CFTimeInterval]

    /// Total number of frames recorded.
    public var frameCount: Int { timestamps.count }

    /// Average frames per second over the tracking window.
    public var averageFPS: Double {
        guard timestamps.count >= 2 else { return 0 }
        let duration = timestamps.last! - timestamps.first!
        return duration > 0 ? Double(timestamps.count - 1) / duration : 0
    }

    /// Number of frames where the inter-frame gap exceeded 33 ms (< 30 fps).
    public var droppedFrameCount: Int {
        let pairs = zip(timestamps.dropLast(), timestamps.dropFirst())
        return pairs.filter { $1 - $0 > 0.033 }.count
    }

    /// Ratio of dropped frames to total frames (0.0 – 1.0).
    public var droppedFrameRatio: Double {
        guard frameCount > 1 else { return 0 }
        return Double(droppedFrameCount) / Double(frameCount - 1)
    }
}
