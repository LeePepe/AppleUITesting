import Foundation

/// A single visual expectation to be evaluated against a screenshot.
public struct EvalExpectation: Sendable {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// The result of evaluating a single expectation.
public struct EvalResult: Sendable {
    public let expectation: EvalExpectation
    public let passed: Bool
    public let reasoning: String
}

/// A complete evaluation report for one screenshot scene.
public struct EvalReport: Sendable {
    public let sceneName: String
    public let results: [EvalResult]
    public let rawResponse: String

    public var passedCount: Int { results.filter(\.passed).count }
    public var failedCount: Int { results.filter { !$0.passed }.count }
    public var passRate: Double {
        guard !results.isEmpty else { return 0 }
        return Double(passedCount) / Double(results.count)
    }
    public var allPassed: Bool { failedCount == 0 }

    public func summary() -> String {
        var lines = ["=== \(sceneName) ===", "Pass rate: \(Int(passRate * 100))% (\(passedCount)/\(results.count))"]
        for result in results where !result.passed {
            lines.append("  FAIL: \(result.expectation.description)")
            lines.append("    Reason: \(result.reasoning)")
        }
        return lines.joined(separator: "\n")
    }
}
