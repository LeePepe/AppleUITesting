#if canImport(XCTest)
import XCTest

/// Asserts that the average FPS in `metrics` meets the minimum threshold.
/// - Parameters:
///   - metrics: Frame metrics captured by `FrameTracker`.
///   - minimumFPS: The minimum acceptable average FPS (default: 55).
///   - file: Source file for XCTest failure reporting.
///   - line: Source line for XCTest failure reporting.
public func assertSmoothAnimation(
    _ metrics: FrameMetrics,
    minimumFPS: Double = 55,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertGreaterThanOrEqual(
        metrics.averageFPS,
        minimumFPS,
        "Average FPS \(String(format: "%.1f", metrics.averageFPS)) is below minimum \(minimumFPS)",
        file: file,
        line: line
    )
}

/// Asserts that the dropped frame ratio is within an acceptable threshold.
/// - Parameters:
///   - metrics: Frame metrics captured by `FrameTracker`.
///   - maxRatio: Maximum acceptable ratio of dropped frames (default: 0.05 = 5%).
///   - file: Source file for XCTest failure reporting.
///   - line: Source line for XCTest failure reporting.
public func assertNoJank(
    _ metrics: FrameMetrics,
    maxRatio: Double = 0.05,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertLessThanOrEqual(
        metrics.droppedFrameRatio,
        maxRatio,
        "Dropped frame ratio \(String(format: "%.1f%%", metrics.droppedFrameRatio * 100)) exceeds maximum \(String(format: "%.1f%%", maxRatio * 100))",
        file: file,
        line: line
    )
}
#endif
