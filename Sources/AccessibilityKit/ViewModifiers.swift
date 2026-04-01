import SwiftUI

extension View {
    /// Tags this view with an `AccessibilityID` for XCUITest queries.
    public func accessibilityId(_ id: AccessibilityID) -> some View {
        accessibilityIdentifier(id.rawValue)
    }
}
