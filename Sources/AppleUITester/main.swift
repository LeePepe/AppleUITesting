import Foundation
#if os(macOS)
import AppKit
import CoreGraphics
#endif
import VisionEvalKit

// MARK: - Argument Parsing

struct CLIArguments {
    var bundleId: String = ""
    var host: String = "localhost"
    var port: Int = 7979
    var expectations: [String] = []
    var screenshot: Bool = false
    var output: String? = nil
}

enum ParseError: Error {
    case missingValue(String)
    case missingRequired(String)
    case invalidPort(String)
}

func parseArguments(_ args: [String]) throws -> CLIArguments {
    var result = CLIArguments()
    var i = 1
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
        default:
            break
        }
        i += 1
    }
    guard !result.bundleId.isEmpty else { throw ParseError.missingRequired("--bundle-id") }
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

// AnyCodable wrapper for arbitrary JSON
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

// MARK: - Screenshot Capture

func captureScreenshot() async -> (String?, String?) {
    let tmpPath = NSTemporaryDirectory() + "ux-screenshot-\(Int(Date().timeIntervalSince1970)).png"

    // Try xcrun simctl io booted screenshot
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["simctl", "io", "booted", "screenshot", tmpPath]
    let errPipe = Pipe()
    process.standardError = errPipe
    process.standardOutput = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0, FileManager.default.fileExists(atPath: tmpPath) {
            return (tmpPath, nil)
        }
    } catch {
        // fall through to ScreenCaptureKit fallback
    }

    // Fallback: ScreenCaptureKit (macOS 12.3+)
    #if os(macOS)
    if #available(macOS 12.3, *) {
        let captureResult = await captureWithScreenCaptureKit(path: tmpPath)
        return captureResult
    }
    #endif

    return (nil, "Screenshot capture failed: xcrun simctl returned non-zero and ScreenCaptureKit unavailable")
}

#if os(macOS)
@available(macOS 12.3, *)
func captureWithScreenCaptureKit(path: String) async -> (String?, String?) {
    // Use CGWindowListCreateImage as a lightweight fallback
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

// MARK: - Main Runner

func run() async -> Int32 {
    var errors: [String] = []

    let args: CLIArguments
    do {
        args = try parseArguments(CommandLine.arguments)
    } catch ParseError.missingRequired(let flag) {
        fputs("Error: \(flag) is required\nUsage: apple-ui-tester --bundle-id <id> [--host <host>] [--port <port>] [--expectations <json>] [--screenshot] [--output <path>]\n", stderr)
        return 1
    } catch {
        fputs("Error parsing arguments: \(error)\n", stderr)
        return 1
    }

    // 1. Health check
    let reachable = await fetchHealth(host: args.host, port: args.port)
    if !reachable {
        errors.append("Bridge unreachable at \(args.host):\(args.port)")
    }

    // 2. Fetch AX tree
    var axTreeValue: Any? = nil
    if reachable {
        let (tree, treeError) = await fetchAXTree(host: args.host, port: args.port)
        axTreeValue = tree
        if let e = treeError { errors.append(e) }
    }

    // 3. Screenshot
    var screenshotPath: String? = nil
    if args.screenshot {
        let (path, captureError) = await captureScreenshot()
        screenshotPath = path
        if let e = captureError { errors.append(e) }
    }

    // 4. Vision eval
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

    // 5. Build report
    let axTreeCodable: AnyCodable? = axTreeValue.map { AnyCodable(value: $0) }
    let report = Report(
        bundleId: args.bundleId,
        bridgeReachable: reachable,
        axTree: axTreeCodable,
        screenshot: ScreenshotInfo(captured: screenshotPath != nil, path: screenshotPath),
        evalReport: evalReportJSON,
        errors: errors
    )

    // 6. Encode output
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
        let outputString = String(data: outputData, encoding: .utf8) ?? ""
        print(outputString)
    }

    // 7. Exit code
    if !reachable { return 1 }
    if hasBlockingFailures { return 2 }
    return 0
}

// Run
let exitCode = await run()
exit(exitCode)
