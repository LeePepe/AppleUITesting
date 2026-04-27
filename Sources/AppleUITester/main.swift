import Foundation
#if os(macOS)
import AppKit
import CoreGraphics
#endif
import VisionEvalKit
import UIActionKit

// MARK: - Argument Parsing

struct CLIArguments {
    var subcommand: String = "inspect"
    var bundleId: String = ""
    var host: String = "localhost"
    var port: Int = 7979
    var expectations: [String] = []
    var screenshot: Bool = false
    var output: String? = nil

    // Action subcommand
    var tapIdentifier: String? = nil
    var typeIdentifier: String? = nil
    var typeText: String? = nil
    var swipeDirection: String? = nil
    var tapX: Double? = nil
    var tapY: Double? = nil
    var longPressIdentifier: String? = nil
    var longPressDuration: Double = 1.0
    var scrollDirection: String? = nil
    var scrollAmount: Double = 100.0

    // Flow subcommand
    var flowSteps: String? = nil
}

enum ParseError: Error, LocalizedError {
    case missingValue(String)
    case missingRequired(String)
    case invalidPort(String)
    case unknownSubcommand(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag): return "Missing value for \(flag)"
        case .missingRequired(let flag): return "\(flag) is required"
        case .invalidPort(let val): return "Invalid port: \(val)"
        case .unknownSubcommand(let cmd): return "Unknown subcommand: \(cmd)"
        }
    }
}

func parseArguments(_ args: [String]) throws -> CLIArguments {
    var result = CLIArguments()

    guard args.count > 1 else {
        throw ParseError.missingRequired("subcommand")
    }

    let firstArg = args[1]
    if firstArg.hasPrefix("--") {
        result.subcommand = "inspect"
    } else {
        result.subcommand = firstArg
    }

    let startIndex = result.subcommand == "inspect" && firstArg.hasPrefix("--") ? 1 : 2
    var i = startIndex

    while i < args.count {
        switch args[i] {
        case "--bundle-id":
            i += 1
            guard i < args.count else { throw ParseError.missingValue("--bundle-id") }
            result.bundleId = args[i]
        case "--host":
            i += 1
            guard i < args.count else { throw ParseError.missingValue("--host") }
            result.host = args[i]
        case "--port":
            i += 1
            guard i < args.count else { throw ParseError.missingValue("--port") }
            guard let p = Int(args[i]) else { throw ParseError.invalidPort(args[i]) }
            result.port = p
        case "--expectations":
            i += 1
            guard i < args.count else { throw ParseError.missingValue("--expectations") }
            let jsonString = args[i]
            if let data = jsonString.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                result.expectations = decoded
            }
        case "--screenshot":
            result.screenshot = true
        case "--output":
            i += 1
            guard i < args.count else { throw ParseError.missingValue("--output") }
            result.output = args[i]
        case "--tap":
            i += 1
            guard i < args.count else { throw ParseError.missingValue("--tap") }
            result.tapIdentifier = args[i]
        case "--tap-xy":
            i += 1
            guard i < args.count else { throw ParseError.missingValue("--tap-xy") }
            let coords = args[i].split(separator: ",")
            if coords.count == 2, let x = Double(coords[0]), let y = Double(coords[1]) {
                result.tapX = x
                result.tapY = y
            }
        case "--type":
            i += 1
            guard i < args.count else { throw ParseError.missingValue("--type") }
            result.typeIdentifier = args[i]
            i += 1
            guard i < args.count else { throw ParseError.missingValue("--type (text)") }
            result.typeText = args[i]
        case "--swipe":
            i += 1
            guard i < args.count else { throw ParseError.missingValue("--swipe") }
            result.swipeDirection = args[i]
        case "--scroll":
            i += 1
            guard i < args.count else { throw ParseError.missingValue("--scroll") }
            result.scrollDirection = args[i]
            if i + 1 < args.count, let amount = Double(args[i + 1]) {
                i += 1
                result.scrollAmount = amount
            }
        case "--long-press":
            i += 1
            guard i < args.count else { throw ParseError.missingValue("--long-press") }
            result.longPressIdentifier = args[i]
            if i + 1 < args.count, let dur = Double(args[i + 1]) {
                i += 1
                result.longPressDuration = dur
            }
        case "--steps":
            i += 1
            guard i < args.count else { throw ParseError.missingValue("--steps") }
            result.flowSteps = args[i]
        default:
            break
        }
        i += 1
    }

    if result.subcommand != "help" {
        guard !result.bundleId.isEmpty else { throw ParseError.missingRequired("--bundle-id") }
    }

    return result
}

// MARK: - Report Types

struct ScreenshotInfo: Encodable {
    let captured: Bool
    let path: String?
}

struct EvalResultJSON: Encodable {
    let expectation: String
    let passed: Bool
    let reasoning: String
}

struct EvalReportJSON: Encodable {
    let sceneName: String
    let results: [EvalResultJSON]
}

struct Report: Encodable {
    let bundleId: String
    let bridgeReachable: Bool
    let axTree: AnyCodable?
    let screenshot: ScreenshotInfo
    let evalReport: EvalReportJSON?
    let errors: [String]
}

struct AnyCodable: Encodable {
    let value: Any
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable(value: $0) })
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable(value: $0) })
        } else if let str = value as? String {
            try container.encode(str)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else {
            try container.encodeNil()
        }
    }
}

// MARK: - Bridge Client

func fetchHealth(host: String, port: Int) async -> Bool {
    guard let url = URL(string: "http://\(host):\(port)/health") else { return false }
    do {
        let (_, response) = try await URLSession.shared.data(from: url)
        return (response as? HTTPURLResponse)?.statusCode == 200
    } catch {
        return false
    }
}

func fetchAXTree(host: String, port: Int) async -> (Any?, String?) {
    guard let url = URL(string: "http://\(host):\(port)/ax-tree") else {
        return (nil, "Invalid URL")
    }
    do {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            return (nil, "Non-200 response from /ax-tree")
        }
        let json = try JSONSerialization.jsonObject(with: data)
        return (json, nil)
    } catch {
        return (nil, error.localizedDescription)
    }
}

func postAction(host: String, port: Int, action: UIAction) async -> (ActionResult?, String?) {
    guard let url = URL(string: "http://\(host):\(port)/action") else {
        return (nil, "Invalid URL")
    }
    do {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(action)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            return (nil, "Non-200 response from /action")
        }
        let result = try JSONDecoder().decode(ActionResult.self, from: data)
        return (result, nil)
    } catch {
        return (nil, error.localizedDescription)
    }
}

// MARK: - Screenshot Capture

func captureScreenshot() async -> (String?, String?) {
    let tmpPath = NSTemporaryDirectory() + "ux-screenshot-\(Int(Date().timeIntervalSince1970)).png"

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["simctl", "io", "booted", "screenshot", tmpPath]
    process.standardError = Pipe()
    process.standardOutput = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0, FileManager.default.fileExists(atPath: tmpPath) {
            return (tmpPath, nil)
        }
    } catch {
        // fall through
    }

    #if os(macOS)
    if #available(macOS 12.3, *) {
        return await captureWithScreenCaptureKit(path: tmpPath)
    }
    #endif

    return (nil, "Screenshot capture failed")
}

#if os(macOS)
@available(macOS 12.3, *)
func captureWithScreenCaptureKit(path: String) async -> (String?, String?) {
    guard let image = CGWindowListCreateImage(
        CGRect.infinite,
        .optionOnScreenOnly,
        kCGNullWindowID,
        .bestResolution
    ) else {
        return (nil, "CGWindowListCreateImage failed")
    }
    let bitmapRep = NSBitmapImageRep(cgImage: image)
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        return (nil, "PNG conversion failed")
    }
    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        return (path, nil)
    } catch {
        return (nil, "Failed to write screenshot: \(error.localizedDescription)")
    }
}
#endif

// MARK: - Subcommand: Action

func runAction(_ args: CLIArguments) async -> Int32 {
    let action: UIAction

    if let identifier = args.tapIdentifier {
        action = .tap(identifier: identifier)
    } else if let x = args.tapX, let y = args.tapY {
        action = .tapCoordinate(x: x, y: y)
    } else if let identifier = args.typeIdentifier, let text = args.typeText {
        action = .typeText(identifier: identifier, text: text)
    } else if let direction = args.swipeDirection,
              let dir = UIAction.SwipeDirection(rawValue: direction) {
        action = .swipe(direction: dir)
    } else if let direction = args.scrollDirection,
              let dir = UIAction.ScrollDirection(rawValue: direction) {
        action = .scroll(direction: dir, amount: args.scrollAmount)
    } else if let identifier = args.longPressIdentifier {
        action = .longPress(identifier: identifier, duration: args.longPressDuration)
    } else {
        fputs("Error: No action specified. Use --tap, --type, --swipe, --scroll, --long-press, or --tap-xy\n", stderr)
        return 1
    }

    let (result, error) = await postAction(host: args.host, port: args.port, action: action)
    if let error {
        fputs("Error: \(error)\n", stderr)
        return 1
    }

    guard let result else {
        fputs("Error: No result returned\n", stderr)
        return 1
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(result), let json = String(data: data, encoding: .utf8) {
        print(json)
    }

    return result.success ? 0 : 1
}

// MARK: - Subcommand: Flow

struct FlowStep: Codable {
    let action: UIAction
    let delayMs: Int?
}

struct FlowResult: Encodable {
    let steps: [StepResult]
    let allPassed: Bool
}

struct StepResult: Encodable {
    let index: Int
    let action: UIAction
    let result: ActionResult
}

func runFlow(_ args: CLIArguments) async -> Int32 {
    guard let stepsJSON = args.flowSteps,
          let data = stepsJSON.data(using: .utf8) else {
        fputs("Error: --steps requires a JSON array\n", stderr)
        return 1
    }

    let steps: [FlowStep]
    do {
        steps = try JSONDecoder().decode([FlowStep].self, from: data)
    } catch {
        fputs("Error: Invalid flow steps JSON: \(error.localizedDescription)\n", stderr)
        return 1
    }

    var stepResults: [StepResult] = []
    var allPassed = true

    for (index, step) in steps.enumerated() {
        if let delayMs = step.delayMs, delayMs > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
        }

        let (result, error) = await postAction(host: args.host, port: args.port, action: step.action)
        if let error {
            let failResult = ActionResult.failure(message: error)
            stepResults.append(StepResult(index: index, action: step.action, result: failResult))
            allPassed = false
            break
        }

        guard let result else {
            let failResult = ActionResult.failure(message: "No result")
            stepResults.append(StepResult(index: index, action: step.action, result: failResult))
            allPassed = false
            break
        }

        stepResults.append(StepResult(index: index, action: step.action, result: result))
        if !result.success {
            allPassed = false
            break
        }
    }

    let flowResult = FlowResult(steps: stepResults, allPassed: allPassed)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(flowResult), let json = String(data: data, encoding: .utf8) {
        print(json)
    }

    return allPassed ? 0 : 1
}

// MARK: - Subcommand: Inspect (original behavior)

func runInspect(_ args: CLIArguments) async -> Int32 {
    var errors: [String] = []

    let reachable = await fetchHealth(host: args.host, port: args.port)
    if !reachable {
        errors.append("Bridge unreachable at \(args.host):\(args.port)")
    }

    var axTreeValue: Any? = nil
    if reachable {
        let (tree, treeError) = await fetchAXTree(host: args.host, port: args.port)
        axTreeValue = tree
        if let e = treeError { errors.append(e) }
    }

    var screenshotPath: String? = nil
    if args.screenshot {
        let (path, captureError) = await captureScreenshot()
        screenshotPath = path
        if let e = captureError { errors.append(e) }
    }

    var evalReportJSON: EvalReportJSON? = nil
    var hasBlockingFailures = false

    if let imgPath = screenshotPath, !args.expectations.isEmpty {
        do {
            let imgData = try Data(contentsOf: URL(fileURLWithPath: imgPath))
            let evaluator = VisionEvaluator()
            let expectations = args.expectations.map { EvalExpectation($0) }
            let report = try await evaluator.evaluate(imageData: imgData, sceneName: args.bundleId, expectations: expectations)
            let results = report.results.map {
                EvalResultJSON(expectation: $0.expectation.description, passed: $0.passed, reasoning: $0.reasoning)
            }
            evalReportJSON = EvalReportJSON(sceneName: args.bundleId, results: results)
            hasBlockingFailures = report.failedCount > 0
        } catch {
            errors.append("Vision eval failed: \(error.localizedDescription)")
        }
    }

    let axTreeCodable: AnyCodable? = axTreeValue.map { AnyCodable(value: $0) }
    let report = Report(
        bundleId: args.bundleId,
        bridgeReachable: reachable,
        axTree: axTreeCodable,
        screenshot: ScreenshotInfo(captured: screenshotPath != nil, path: screenshotPath),
        evalReport: evalReportJSON,
        errors: errors
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let outputData: Data
    do {
        outputData = try encoder.encode(report)
    } catch {
        fputs("Failed to encode report: \(error)\n", stderr)
        return 1
    }

    if let outputPath = args.output {
        do {
            try outputData.write(to: URL(fileURLWithPath: outputPath))
        } catch {
            fputs("Failed to write output file: \(error)\n", stderr)
            return 1
        }
    } else {
        print(String(data: outputData, encoding: .utf8) ?? "")
    }

    if !reachable { return 1 }
    if hasBlockingFailures { return 2 }
    return 0
}

// MARK: - Help

func printUsage() {
    let usage = """
    apple-ui-tester - AI agent UI testing tool for Apple platforms

    USAGE:
      apple-ui-tester inspect --bundle-id <id> [options]
      apple-ui-tester action --bundle-id <id> <action-flags>
      apple-ui-tester flow --bundle-id <id> --steps '<json>'

    SUBCOMMANDS:
      inspect     Fetch AX tree, capture screenshot, run vision eval (default)
      action      Perform a single UI action via the bridge
      flow        Run a sequence of UI actions

    COMMON OPTIONS:
      --bundle-id <id>    Target app bundle identifier (required)
      --host <host>       Bridge host (default: localhost)
      --port <port>       Bridge port (default: 7979)
      --output <path>     Write output to file instead of stdout

    INSPECT OPTIONS:
      --screenshot        Capture a screenshot
      --expectations <json>  JSON array of expectations for vision eval

    ACTION FLAGS:
      --tap <identifier>            Tap element by accessibility identifier
      --tap-xy <x>,<y>              Tap at screen coordinates
      --type <identifier> <text>    Type text into element
      --swipe <up|down|left|right>  Swipe gesture
      --scroll <up|down|left|right> [amount]  Scroll gesture
      --long-press <identifier> [duration]    Long press element

    FLOW:
      --steps '<json>'    JSON array of {action, delayMs?} objects
    """
    print(usage)
}

// MARK: - Main

func run() async -> Int32 {
    let args: CLIArguments
    do {
        args = try parseArguments(CommandLine.arguments)
    } catch ParseError.missingRequired("subcommand") {
        printUsage()
        return 1
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        printUsage()
        return 1
    }

    switch args.subcommand {
    case "inspect":
        return await runInspect(args)
    case "action":
        return await runAction(args)
    case "flow":
        return await runFlow(args)
    case "help":
        printUsage()
        return 0
    default:
        fputs("Error: Unknown subcommand '\(args.subcommand)'\n", stderr)
        printUsage()
        return 1
    }
}

let exitCode = await run()
exit(exitCode)
