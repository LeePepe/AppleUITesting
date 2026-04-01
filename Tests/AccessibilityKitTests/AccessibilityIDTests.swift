import XCTest
@testable import AccessibilityKit

final class AccessibilityIDTests: XCTestCase {
    func testRawValueRoundTrip() {
        let id: AccessibilityID = "my.button"
        XCTAssertEqual(id.rawValue, "my.button")
    }

    func testEquality() {
        let a: AccessibilityID = "a.b"
        let b = AccessibilityID(rawValue: "a.b")
        XCTAssertEqual(a, b)
    }

    func testHashing() {
        var set = Set<AccessibilityID>()
        set.insert("x.y")
        set.insert("x.y")
        XCTAssertEqual(set.count, 1)
    }
}
