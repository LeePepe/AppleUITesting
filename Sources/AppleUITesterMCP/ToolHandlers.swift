import Foundation

struct ToolHandlers: Sendable {
    let host: String
    let port: Int

    func handle(tool: String, arguments: [String: Any]) async -> [String: Any] {
        switch tool {
        case "get_ax_tree":
            return await handleGetAxTree(arguments: arguments)
        case "capture_screenshot":
            return await handleCaptureScreenshot()
        case "vision_eval":
            return await handleVisionEval(arguments: arguments)
        case "perform_action":
            return await handlePerformAction(arguments: arguments)
        case "run_flow":
            return await handleRunFlow(arguments: arguments)
        default:
            return errorContent("Unknown tool: \(tool)")
        }
    }

    // MARK: - get_ax_tree

    private func handleGetAxTree(arguments: [String: Any]) async -> [String: Any] {
        let elementId = arguments["element_id"] as? String
        let path: String
        if let elementId {
            let encoded = elementId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? elementId
            path = "/ax-tree/element?id=\(encoded)"
        } else {
            path = "/ax-tree"
        }

        guard let (data, error) = await fetchBridge(path: path) else {
            return errorContent("Request failed")
        }
        if let error {
            return errorContent(error)
        }
        guard let data else {
            return errorContent("No data returned")
        }

        let text = String(data: data, encoding: .utf8) ?? "{}"
        return textContent(text)
    }

    // MARK: - capture_screenshot

    private func handleCaptureScreenshot() async -> [String: Any] {
        guard let (data, error) = await fetchBridge(path: "/screenshot") else {
            return errorContent("Request failed")
        }
        if let error {
            return errorContent(error)
        }
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base64Image = json["image"] as? String else {
            return errorContent("Invalid screenshot response")
        }

        return [
            "content": [
                [
                    "type": "image",
                    "data": base64Image,
                    "mimeType": "image/png",
                ]
            ]
        ]
    }

    // MARK: - vision_eval

    private func handleVisionEval(arguments: [String: Any]) async -> [String: Any] {
        guard let expectations = arguments["expectations"] as? [String], !expectations.isEmpty else {
            return errorContent("Missing or empty 'expectations' array")
        }

        guard let (screenshotData, screenshotError) = await fetchBridge(path: "/screenshot") else {
            return errorContent("Screenshot request failed")
        }
        if let screenshotError {
            return errorContent(screenshotError)
        }
        guard let screenshotData,
              let screenshotJson = try? JSONSerialization.jsonObject(with: screenshotData) as? [String: Any],
              let base64Image = screenshotJson["image"] as? String,
              let imageData = Data(base64Encoded: base64Image) else {
            return errorContent("Failed to capture screenshot for vision eval")
        }

        let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        guard !apiKey.isEmpty else {
            return errorContent("ANTHROPIC_API_KEY environment variable not set")
        }

        let expectationList = expectations.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        let prompt = """
        Evaluate this UI screenshot. For each expectation, respond PASS or FAIL with reasoning.

        Expectations:
        \(expectationList)

        Respond as JSON: {"results": [{"index": 1, "passed": true, "reasoning": "..."}]}
        """

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": imageData.base64EncodedString()]],
                        ["type": "text", "text": prompt],
                    ],
                ]
            ],
        ]

        do {
            let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = bodyData

            let (data, _) = try await URLSession.shared.data(for: request)
            let responseText = String(data: data, encoding: .utf8) ?? "{}"
            return textContent(responseText)
        } catch {
            return errorContent("Vision eval failed: \(error.localizedDescription)")
        }
    }

    // MARK: - perform_action

    private func handlePerformAction(arguments: [String: Any]) async -> [String: Any] {
        guard let actionJSON = buildActionJSON(from: arguments) else {
            return errorContent("Invalid action parameters")
        }
        return await postActionToBridge(actionJSON: actionJSON)
    }

    // MARK: - run_flow

    private func handleRunFlow(arguments: [String: Any]) async -> [String: Any] {
        guard let steps = arguments["steps"] as? [[String: Any]] else {
            return errorContent("Missing 'steps' array")
        }

        var results: [[String: Any]] = []
        var allPassed = true

        for (index, step) in steps.enumerated() {
            if let delayMs = step["delay_ms"] as? Int, delayMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }

            guard let actionJSON = buildActionJSON(from: step) else {
                results.append(["index": index, "success": false, "message": "Invalid action at step \(index)"])
                allPassed = false
                break
            }

            let response = await postActionToBridge(actionJSON: actionJSON)
            let content = response["content"] as? [[String: Any]]
            let text = content?.first?["text"] as? String ?? ""

            if let data = text.data(using: .utf8),
               let resultJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var stepResult = resultJSON
                stepResult["index"] = index
                results.append(stepResult)
                if resultJSON["success"] as? Bool != true {
                    allPassed = false
                    break
                }
            } else {
                results.append(["index": index, "success": false, "message": "Failed to parse result"])
                allPassed = false
                break
            }
        }

        let flowResult: [String: Any] = ["steps": results, "allPassed": allPassed]
        guard let data = try? JSONSerialization.data(withJSONObject: flowResult, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return errorContent("Failed to encode flow result")
        }
        return textContent(text)
    }

    // MARK: - Helpers

    private func buildActionJSON(from arguments: [String: Any]) -> Data? {
        guard let actionType = arguments["action_type"] as? String else { return nil }

        var actionDict: [String: Any]

        switch actionType {
        case "tap":
            guard let identifier = arguments["identifier"] as? String else { return nil }
            actionDict = ["tap": ["identifier": identifier]]
        case "tapCoordinate":
            guard let x = arguments["x"] as? Double, let y = arguments["y"] as? Double else { return nil }
            actionDict = ["tapCoordinate": ["x": x, "y": y]]
        case "typeText":
            guard let identifier = arguments["identifier"] as? String, let text = arguments["text"] as? String else { return nil }
            actionDict = ["typeText": ["identifier": identifier, "text": text]]
        case "swipe":
            guard let direction = arguments["direction"] as? String else { return nil }
            actionDict = ["swipe": ["direction": direction]]
        case "scroll":
            guard let direction = arguments["direction"] as? String else { return nil }
            let amount = arguments["amount"] as? Double ?? 100.0
            actionDict = ["scroll": ["direction": direction, "amount": amount]]
        case "longPress":
            guard let identifier = arguments["identifier"] as? String else { return nil }
            let duration = arguments["duration"] as? Double ?? 1.0
            actionDict = ["longPress": ["identifier": identifier, "duration": duration]]
        default:
            return nil
        }

        return try? JSONSerialization.data(withJSONObject: actionDict)
    }

    private func postActionToBridge(actionJSON: Data) async -> [String: Any] {
        guard let url = URL(string: "http://\(host):\(port)/action") else {
            return errorContent("Invalid bridge URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = actionJSON

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                return errorContent("Bridge returned error: \(body)")
            }
            let text = String(data: data, encoding: .utf8) ?? "{}"
            return textContent(text)
        } catch {
            return errorContent("Bridge request failed: \(error.localizedDescription)")
        }
    }

    private func fetchBridge(path: String) async -> (Data?, String?)? {
        guard let url = URL(string: "http://\(host):\(port)\(path)") else {
            return (nil, "Invalid URL")
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return (nil, "Non-200 response from \(path)")
            }
            return (data, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private func textContent(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]]]
    }

    private func errorContent(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": "Error: \(message)"]], "isError": true]
    }
}
