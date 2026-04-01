#if canImport(XCTest)
import XCTest
import SwiftUI
import SnapshotTesting

// MARK: - iOS Helpers

#if os(iOS)
/// Assert a SwiftUI view matches a stored snapshot on iOS.
/// - Parameters:
///   - view: The SwiftUI view to snapshot.
///   - config: Device configuration defining size and scale.
///   - testName: Snapshot file name (defaults to the calling function).
///   - record: Whether to record a new reference image.
///   - file: Source file for XCTest failure reporting.
///   - line: Source line for XCTest failure reporting.
@MainActor
public func assertAppSnapshot<V: View>(
    _ view: V,
    on config: SnapshotConfiguration,
    testName: String = #function,
    record: SnapshotTestingConfiguration.Record? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let controller = UIHostingController(rootView: view)
    controller.view.frame = CGRect(origin: .zero, size: CGSize(width: config.width, height: config.height))

    assertSnapshot(
        of: controller,
        as: .image(on: .init(size: CGSize(width: config.width, height: config.height))),
        named: config.name,
        record: record,
        file: file,
        testName: testName,
        line: line
    )
}
#endif

// MARK: - macOS Helpers

#if os(macOS)
import AppKit

/// Assert a SwiftUI view matches a stored snapshot on macOS.
/// - Parameters:
///   - view: The SwiftUI view to snapshot.
///   - config: Device configuration defining size and scale.
///   - testName: Snapshot file name (defaults to the calling function).
///   - record: Whether to record a new reference image.
///   - file: Source file for XCTest failure reporting.
///   - line: Source line for XCTest failure reporting.
@MainActor
public func assertAppSnapshot<V: View>(
    _ view: V,
    on config: SnapshotConfiguration,
    testName: String = #function,
    record: SnapshotTestingConfiguration.Record? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let hostView = NSHostingView(rootView: view)
    hostView.frame = CGRect(origin: .zero, size: CGSize(width: config.width, height: config.height))

    assertSnapshot(
        of: hostView,
        as: .image(),
        named: config.name,
        record: record,
        file: file,
        testName: testName,
        line: line
    )
}
#endif

#endif // canImport(XCTest)
