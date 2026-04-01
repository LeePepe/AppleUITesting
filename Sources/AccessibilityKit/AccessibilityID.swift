import Foundation

/// A typed accessibility identifier for UI elements.
/// Use this to tag interactive elements and query them in XCUITest.
public struct AccessibilityID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension AccessibilityID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}
