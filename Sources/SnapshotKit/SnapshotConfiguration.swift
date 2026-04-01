import Foundation

/// Configuration for snapshot testing on specific device presets.
public struct SnapshotConfiguration: Sendable {
    public let name: String
    public let width: CGFloat
    public let height: CGFloat
    public let scale: CGFloat

    public init(name: String, width: CGFloat, height: CGFloat, scale: CGFloat = 2.0) {
        self.name = name
        self.width = width
        self.height = height
        self.scale = scale
    }
}

extension SnapshotConfiguration {
    // iPhone presets
    public static let iPhone15Pro = SnapshotConfiguration(name: "iPhone15Pro", width: 393, height: 852, scale: 3.0)
    public static let iPhone15 = SnapshotConfiguration(name: "iPhone15", width: 390, height: 844, scale: 3.0)
    public static let iPhoneSE3 = SnapshotConfiguration(name: "iPhoneSE3", width: 375, height: 667, scale: 2.0)

    // iPad presets
    public static let iPadPro11 = SnapshotConfiguration(name: "iPadPro11", width: 834, height: 1194, scale: 2.0)
    public static let iPadAir = SnapshotConfiguration(name: "iPadAir", width: 820, height: 1180, scale: 2.0)

    // macOS presets
    public static let macBook13 = SnapshotConfiguration(name: "MacBook13", width: 1280, height: 800, scale: 2.0)
    public static let macBook16 = SnapshotConfiguration(name: "MacBook16", width: 1728, height: 1117, scale: 2.0)
}
