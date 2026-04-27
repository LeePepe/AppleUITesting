// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleUITesting",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "AccessibilityKit", targets: ["AccessibilityKit"]),
        .library(name: "SnapshotKit", targets: ["SnapshotKit"]),
        .library(name: "PerformanceKit", targets: ["PerformanceKit"]),
        .library(name: "VisionEvalKit", targets: ["VisionEvalKit"]),
        .library(name: "UIActionKit", targets: ["UIActionKit"]),
        .library(name: "UITestingBridge", targets: ["UITestingBridge"]),
        .executable(name: "apple-ui-tester", targets: ["AppleUITester"]),
        .executable(name: "apple-ui-tester-mcp", targets: ["AppleUITesterMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: [
        .target(
            name: "AccessibilityKit",
            dependencies: [],
            path: "Sources/AccessibilityKit"
        ),
        .target(
            name: "SnapshotKit",
            dependencies: [
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Sources/SnapshotKit"
        ),
        .target(
            name: "PerformanceKit",
            dependencies: [],
            path: "Sources/PerformanceKit"
        ),
        .target(
            name: "VisionEvalKit",
            dependencies: [],
            path: "Sources/VisionEvalKit"
        ),
        .target(
            name: "UIActionKit",
            dependencies: [],
            path: "Sources/UIActionKit"
        ),
        .target(
            name: "UITestingBridge",
            dependencies: [
                "UIActionKit",
            ],
            path: "Sources/UITestingBridge"
        ),
        .executableTarget(
            name: "AppleUITester",
            dependencies: [
                "VisionEvalKit",
                "UITestingBridge",
                "UIActionKit",
                "AccessibilityKit",
            ],
            path: "Sources/AppleUITester"
        ),
        .executableTarget(
            name: "AppleUITesterMCP",
            dependencies: [],
            path: "Sources/AppleUITesterMCP"
        ),
        .testTarget(
            name: "AccessibilityKitTests",
            dependencies: ["AccessibilityKit"],
            path: "Tests/AccessibilityKitTests"
        ),
        .testTarget(
            name: "VisionEvalKitTests",
            dependencies: ["VisionEvalKit"],
            path: "Tests/VisionEvalKitTests"
        ),
        .testTarget(
            name: "UIActionKitTests",
            dependencies: ["UIActionKit"],
            path: "Tests/UIActionKitTests"
        ),
        .testTarget(
            name: "UITestingBridgeTests",
            dependencies: ["UITestingBridge", "UIActionKit"],
            path: "Tests/UITestingBridgeTests"
        ),
        .testTarget(
            name: "AppleUITesterMCPTests",
            dependencies: [],
            path: "Tests/AppleUITesterMCPTests"
        ),
    ]
)
