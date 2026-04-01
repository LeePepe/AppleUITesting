#if canImport(XCTest)
import XCTest

extension XCUIApplication {
    /// Returns the element with the given `AccessibilityID`.
    public func element(id: AccessibilityID) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id.rawValue).firstMatch
    }

    /// Returns a button with the given `AccessibilityID`.
    public func button(id: AccessibilityID) -> XCUIElement {
        buttons[id.rawValue]
    }

    /// Returns a text field with the given `AccessibilityID`.
    public func textField(id: AccessibilityID) -> XCUIElement {
        textFields[id.rawValue]
    }
}
#endif
