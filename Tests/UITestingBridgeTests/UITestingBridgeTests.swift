import XCTest
@testable import UITestingBridge

final class HTTPRequestParsingTests: XCTestCase {
    func testHTTPResponseStatusText() {
        XCTAssertEqual(HTTPResponse(status: 200, body: "").statusText, "OK")
        XCTAssertEqual(HTTPResponse(status: 400, body: "").statusText, "Bad Request")
        XCTAssertEqual(HTTPResponse(status: 404, body: "").statusText, "Not Found")
        XCTAssertEqual(HTTPResponse(status: 405, body: "").statusText, "Method Not Allowed")
        XCTAssertEqual(HTTPResponse(status: 500, body: "").statusText, "Internal Server Error")
        XCTAssertEqual(HTTPResponse(status: 501, body: "").statusText, "Not Implemented")
        XCTAssertEqual(HTTPResponse(status: 418, body: "").statusText, "Unknown")
    }

    func testHTTPResponseDefaultStatus() {
        let response = HTTPResponse(body: "test")
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.body, "test")
    }
}
