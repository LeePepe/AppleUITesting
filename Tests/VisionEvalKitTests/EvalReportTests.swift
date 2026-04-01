import XCTest
@testable import VisionEvalKit

final class EvalReportTests: XCTestCase {
    func testPassRate() {
        let expectations = [
            EvalExpectation("Button is visible"),
            EvalExpectation("No error shown"),
            EvalExpectation("Title is correct"),
        ]
        let results = [
            EvalResult(expectation: expectations[0], passed: true, reasoning: "Button present"),
            EvalResult(expectation: expectations[1], passed: false, reasoning: "Error banner visible"),
            EvalResult(expectation: expectations[2], passed: true, reasoning: "Title matches"),
        ]
        let report = EvalReport(sceneName: "Test", results: results, rawResponse: "")

        XCTAssertEqual(report.passedCount, 2)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertEqual(report.passRate, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertFalse(report.allPassed)
    }

    func testAllPassed() {
        let e = EvalExpectation("Something")
        let results = [EvalResult(expectation: e, passed: true, reasoning: "ok")]
        let report = EvalReport(sceneName: "Scene", results: results, rawResponse: "")
        XCTAssertTrue(report.allPassed)
        XCTAssertEqual(report.passRate, 1.0, accuracy: 0.001)
    }

    func testEmptyReport() {
        let report = EvalReport(sceneName: "Empty", results: [], rawResponse: "")
        XCTAssertEqual(report.passRate, 0)
        XCTAssertTrue(report.allPassed)
    }

    func testSummaryIncludesFailures() {
        let e = EvalExpectation("No crash dialog")
        let results = [EvalResult(expectation: e, passed: false, reasoning: "Dialog detected")]
        let report = EvalReport(sceneName: "Crash", results: results, rawResponse: "")
        let summary = report.summary()
        XCTAssertTrue(summary.contains("FAIL"))
        XCTAssertTrue(summary.contains("No crash dialog"))
    }
}
