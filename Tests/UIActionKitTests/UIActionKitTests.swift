import XCTest
@testable import UIActionKit

final class UIActionTests: XCTestCase {
    func testTapEncoding() throws {
        let action = UIAction.tap(identifier: "loginButton")
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(UIAction.self, from: data)
        if case .tap(let identifier) = decoded {
            XCTAssertEqual(identifier, "loginButton")
        } else {
            XCTFail("Expected .tap")
        }
    }

    func testTapCoordinateEncoding() throws {
        let action = UIAction.tapCoordinate(x: 100.5, y: 200.3)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(UIAction.self, from: data)
        if case .tapCoordinate(let x, let y) = decoded {
            XCTAssertEqual(x, 100.5, accuracy: 0.001)
            XCTAssertEqual(y, 200.3, accuracy: 0.001)
        } else {
            XCTFail("Expected .tapCoordinate")
        }
    }

    func testTypeTextEncoding() throws {
        let action = UIAction.typeText(identifier: "emailField", text: "test@example.com")
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(UIAction.self, from: data)
        if case .typeText(let identifier, let text) = decoded {
            XCTAssertEqual(identifier, "emailField")
            XCTAssertEqual(text, "test@example.com")
        } else {
            XCTFail("Expected .typeText")
        }
    }

    func testSwipeEncoding() throws {
        let action = UIAction.swipe(direction: .up)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(UIAction.self, from: data)
        if case .swipe(let direction) = decoded {
            XCTAssertEqual(direction, .up)
        } else {
            XCTFail("Expected .swipe")
        }
    }

    func testScrollEncoding() throws {
        let action = UIAction.scroll(direction: .down, amount: 150.0)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(UIAction.self, from: data)
        if case .scroll(let direction, let amount) = decoded {
            XCTAssertEqual(direction, .down)
            XCTAssertEqual(amount, 150.0, accuracy: 0.001)
        } else {
            XCTFail("Expected .scroll")
        }
    }

    func testLongPressEncoding() throws {
        let action = UIAction.longPress(identifier: "menuItem", duration: 2.5)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(UIAction.self, from: data)
        if case .longPress(let identifier, let duration) = decoded {
            XCTAssertEqual(identifier, "menuItem")
            XCTAssertEqual(duration, 2.5, accuracy: 0.001)
        } else {
            XCTFail("Expected .longPress")
        }
    }

    func testSwipeDirectionRawValues() {
        XCTAssertEqual(UIAction.SwipeDirection.up.rawValue, "up")
        XCTAssertEqual(UIAction.SwipeDirection.down.rawValue, "down")
        XCTAssertEqual(UIAction.SwipeDirection.left.rawValue, "left")
        XCTAssertEqual(UIAction.SwipeDirection.right.rawValue, "right")
    }

    func testScrollDirectionRawValues() {
        XCTAssertEqual(UIAction.ScrollDirection.up.rawValue, "up")
        XCTAssertEqual(UIAction.ScrollDirection.down.rawValue, "down")
        XCTAssertEqual(UIAction.ScrollDirection.left.rawValue, "left")
        XCTAssertEqual(UIAction.ScrollDirection.right.rawValue, "right")
    }
}

final class ActionResultTests: XCTestCase {
    func testOkFactory() {
        let result = ActionResult.ok(message: "Done", duration: 0.5)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.message, "Done")
        XCTAssertEqual(result.duration, 0.5, accuracy: 0.001)
    }

    func testFailureFactory() {
        let result = ActionResult.failure(message: "Not found")
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "Not found")
        XCTAssertEqual(result.duration, 0.0, accuracy: 0.001)
    }

    func testActionResultEncoding() throws {
        let result = ActionResult(success: true, message: "Tapped", duration: 0.123)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertEqual(decoded.success, true)
        XCTAssertEqual(decoded.message, "Tapped")
        XCTAssertEqual(decoded.duration, 0.123, accuracy: 0.001)
    }

    func testOkDefaultMessage() {
        let result = ActionResult.ok()
        XCTAssertEqual(result.message, "Action completed")
    }
}

final class ActionExecutorErrorTests: XCTestCase {
    func testElementNotFoundDescription() {
        let error = ActionExecutorError.elementNotFound("btn1")
        XCTAssertTrue(error.localizedDescription.contains("btn1"))
    }

    func testActionFailedDescription() {
        let error = ActionExecutorError.actionFailed("reason")
        XCTAssertTrue(error.localizedDescription.contains("reason"))
    }

    func testUnsupportedPlatformDescription() {
        let error = ActionExecutorError.unsupportedPlatform
        XCTAssertFalse(error.localizedDescription.isEmpty)
    }

    func testTimeoutDescription() {
        let error = ActionExecutorError.timeout("5s")
        XCTAssertTrue(error.localizedDescription.contains("5s"))
    }
}
