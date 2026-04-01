import Foundation

/// Evaluates screenshots against expectations using Claude Vision.
public final class VisionEvaluator: Sendable {
    private let apiKey: String
    private let model: String

    /// Creates a `VisionEvaluator` using the Anthropic API.
    /// - Parameters:
    ///   - apiKey: Anthropic API key. Defaults to `ANTHROPIC_API_KEY` environment variable.
    ///   - model: Claude model ID to use. Defaults to `claude-sonnet-4-6`.
    public init(
        apiKey: String? = nil,
        model: String = "claude-sonnet-4-6"
    ) {
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        self.model = model
    }

    /// Evaluates a screenshot (PNG data) against a list of expectations.
    /// - Parameters:
    ///   - imageData: Raw PNG data of the screenshot.
    ///   - sceneName: Human-readable name for the evaluated scene.
    ///   - expectations: Descriptions of what should be visible/true in the screenshot.
    /// - Returns: An `EvalReport` with pass/fail results for each expectation.
    public func evaluate(
        imageData: Data,
        sceneName: String,
        expectations: [EvalExpectation]
    ) async throws -> EvalReport {
        guard !apiKey.isEmpty else {
            throw VisionEvalError.missingAPIKey
        }

        let base64 = imageData.base64EncodedString()
        let expectationList = expectations.enumerated()
            .map { "\($0.offset + 1). \($0.element.description)" }
            .joined(separator: "\n")

        let prompt = """
        You are evaluating a UI screenshot. For each expectation below, respond with PASS or FAIL and a brief reason.

        Expectations:
        \(expectationList)

        Format your response as JSON:
        {
          "results": [
            { "index": 1, "passed": true, "reasoning": "..." },
            ...
          ]
        }
        """

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/png",
                                "data": base64,
                            ],
                        ],
                        [
                            "type": "text",
                            "text": prompt,
                        ],
                    ],
                ]
            ],
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw VisionEvalError.apiError(body)
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let rawText = decoded.content.first?.text ?? ""

        let results = try parseResults(rawText, expectations: expectations)
        return EvalReport(sceneName: sceneName, results: results, rawResponse: rawText)
    }

    private func parseResults(_ text: String, expectations: [EvalExpectation]) throws -> [EvalResult] {
        // Extract JSON from the response text
        guard let jsonStart = text.firstIndex(of: "{"),
              let jsonEnd = text.lastIndex(of: "}") else {
            throw VisionEvalError.parseError("No JSON object found in response")
        }
        let jsonString = String(text[jsonStart...jsonEnd])
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw VisionEvalError.parseError("Invalid UTF-8 in JSON")
        }

        let parsed = try JSONDecoder().decode(EvalResponseBody.self, from: jsonData)

        return parsed.results.compactMap { item in
            guard item.index >= 1, item.index <= expectations.count else { return nil }
            let expectation = expectations[item.index - 1]
            return EvalResult(expectation: expectation, passed: item.passed, reasoning: item.reasoning)
        }
    }
}

// MARK: - Private Decodable types

private struct AnthropicResponse: Decodable {
    struct ContentBlock: Decodable {
        let text: String?
    }
    let content: [ContentBlock]
}

private struct EvalResponseBody: Decodable {
    struct Item: Decodable {
        let index: Int
        let passed: Bool
        let reasoning: String
    }
    let results: [Item]
}

// MARK: - Errors

public enum VisionEvalError: Error, LocalizedError {
    case missingAPIKey
    case apiError(String)
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "ANTHROPIC_API_KEY is not set"
        case .apiError(let body):
            return "Anthropic API error: \(body)"
        case .parseError(let reason):
            return "Failed to parse eval response: \(reason)"
        }
    }
}
