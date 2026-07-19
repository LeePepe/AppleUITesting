import Foundation
import UIActionKit
#if os(macOS)
import AppKit
import ApplicationServices
#elseif os(iOS)
import UIKit
#endif

/// A lightweight HTTP server that exposes the app's accessibility tree on port 7979.
/// Add `UITestingBridge.start()` in your app's debug entry point to enable
/// the `get_ax_tree` tool in the `apple-ui-tester` MCP server.
///
/// ```swift
/// #if DEBUG
/// UITestingBridge.start()
/// #endif
/// ```
public final class UITestingBridge: @unchecked Sendable {
    public static let defaultPort: UInt16 = 7979

    private var server: SimpleHTTPServer?
    private let actionExecutor: ActionExecutor

    /// Shared singleton instance.
    public static let shared = UITestingBridge()

    private init() {
        self.actionExecutor = createActionExecutor()
    }

    /// Starts the bridge on the default port (7979).
    public static func start(port: UInt16 = defaultPort) {
        shared.startServer(port: port)
    }

    /// Stops the bridge.
    public static func stop() {
        shared.server?.stop()
        shared.server = nil
    }

    private func startServer(port: UInt16) {
        let srv = SimpleHTTPServer(port: port)

        srv.route("/health") { _ in
            HTTPResponse(body: #"{"status":"ok"}"#)
        }

        srv.route("/ax-tree") { [weak self] _ in
            let json = self?.buildAXTreeJSON() ?? "{}"
            return HTTPResponse(body: json)
        }

        srv.route("/ax-tree/element") { [weak self] request in
            guard let identifier = request.queryParams["id"] else {
                return HTTPResponse(status: 400, body: #"{"error":"Missing 'id' query parameter"}"#)
            }
            let json = self?.buildElementJSON(identifier: identifier) ?? #"{"error":"Element not found"}"#
            return HTTPResponse(body: json)
        }

        srv.route("/action") { [weak self] request in
            guard request.method == "POST" else {
                return HTTPResponse(status: 405, body: #"{"error":"Method not allowed, use POST"}"#)
            }
            guard let self else {
                return HTTPResponse(status: 500, body: #"{"error":"Bridge unavailable"}"#)
            }
            return self.handleAction(body: request.body)
        }

        srv.route("/screenshot") { [weak self] _ in
            self?.handleScreenshot() ?? HTTPResponse(status: 500, body: #"{"error":"Bridge unavailable"}"#)
        }

        server = srv
        srv.start()
    }

    // MARK: - Action Handler

    private func handleAction(body: String) -> HTTPResponse {
        guard let data = body.data(using: .utf8) else {
            return HTTPResponse(status: 400, body: #"{"error":"Invalid request body"}"#)
        }
        let action: UIAction
        do {
            action = try JSONDecoder().decode(UIAction.self, from: data)
        } catch {
            return HTTPResponse(status: 400, body: #"{"error":"Invalid action JSON: \#(error.localizedDescription)"}"#)
        }

        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        let executor = self.actionExecutor

        Task {
            do {
                let r = try await executor.execute(action)
                box.setResult(r)
            } catch {
                box.setError(error)
            }
            semaphore.signal()
        }
        semaphore.wait()

        if let error = box.error {
            let errorResult = ActionResult.failure(message: error.localizedDescription)
            guard let json = try? JSONEncoder().encode(errorResult),
                  let jsonStr = String(data: json, encoding: .utf8) else {
                return HTTPResponse(status: 500, body: #"{"error":"Encoding failed"}"#)
            }
            return HTTPResponse(body: jsonStr)
        }

        guard let result = box.result,
              let json = try? JSONEncoder().encode(result),
              let jsonStr = String(data: json, encoding: .utf8) else {
            return HTTPResponse(status: 500, body: #"{"error":"Encoding failed"}"#)
        }
        return HTTPResponse(body: jsonStr)
    }

    // MARK: - Screenshot Handler

    private func handleScreenshot() -> HTTPResponse {
        #if os(macOS)
        guard let image = CGWindowListCreateImage(
            CGRect.infinite,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else {
            return HTTPResponse(status: 500, body: #"{"error":"Screenshot capture failed"}"#)
        }
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return HTTPResponse(status: 500, body: #"{"error":"PNG encoding failed"}"#)
        }
        let base64 = pngData.base64EncodedString()
        return HTTPResponse(body: #"{"image":"\#(base64)","format":"png"}"#)
        #elseif os(iOS)
        let semaphore = DispatchSemaphore(value: 0)
        var pngData: Data?
        DispatchQueue.main.async {
            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: { $0.isKeyWindow }) {
                let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
                let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                pngData = image.pngData()
            }
            semaphore.signal()
        }
        semaphore.wait()
        guard let data = pngData else {
            return HTTPResponse(status: 500, body: #"{"error":"Screenshot capture failed"}"#)
        }
        let base64 = data.base64EncodedString()
        return HTTPResponse(body: #"{"image":"\#(base64)","format":"png"}"#)
        #else
        return HTTPResponse(status: 501, body: #"{"error":"Not supported on this platform"}"#)
        #endif
    }

    // MARK: - AX Tree

    private func buildAXTreeJSON() -> String {
#if os(macOS)
        return buildMacOSAXTree()
#elseif os(iOS)
        return buildIOSAXTree()
#else
        return "{}"
#endif
    }

    private func buildElementJSON(identifier: String) -> String {
#if os(macOS)
        return buildMacOSElementJSON(identifier: identifier)
#elseif os(iOS)
        return buildIOSElementJSON(identifier: identifier)
#else
        return #"{"error":"Not supported"}"#
#endif
    }

#if os(macOS)
    private func buildMacOSAXTree() -> String {
        let axApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let node = axNodeFromElement(axApp, depth: 0, maxDepth: 6)
        return encodeToJSON(node) ?? "{}"
    }

    private func buildMacOSElementJSON(identifier: String) -> String {
        let axApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        guard let element = findAXElement(axApp, identifier: identifier, depth: 0, maxDepth: 8) else {
            return #"{"error":"Element not found","identifier":"\#(identifier)"}"#
        }
        let node = axNodeFromElement(element, depth: 0, maxDepth: 2)
        return encodeToJSON(node) ?? "{}"
    }

    private func findAXElement(_ element: AXUIElement, identifier: String, depth: Int, maxDepth: Int) -> AXUIElement? {
        var identifierRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierRef)
        if let elemId = identifierRef as? String, elemId == identifier {
            return element
        }
        guard depth < maxDepth else { return nil }
        var childrenRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard let children = childrenRef as? [AXUIElement] else { return nil }
        for child in children {
            if let found = findAXElement(child, identifier: identifier, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }
        return nil
    }

    private func axNodeFromElement(_ element: AXUIElement, depth: Int, maxDepth: Int) -> [String: Any] {
        var result: [String: Any] = [:]

        func getString(_ attr: String) -> String? {
            var value: AnyObject?
            AXUIElementCopyAttributeValue(element, attr as CFString, &value)
            return value as? String
        }

        result["role"] = getString(kAXRoleAttribute as String) ?? "unknown"
        if let label = getString(kAXLabelValueAttribute as String) { result["label"] = label }
        if let title = getString(kAXTitleAttribute as String) { result["title"] = title }
        if let identifier = getString(kAXIdentifierAttribute as String) { result["identifier"] = identifier }
        if let value = getString(kAXValueAttribute as String) { result["value"] = value }

        if depth < maxDepth {
            var childrenRef: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
            if let children = childrenRef as? [AXUIElement] {
                result["children"] = children.map { axNodeFromElement($0, depth: depth + 1, maxDepth: maxDepth) }
            }
        }

        return result
    }
#endif

#if os(iOS)
    private func buildIOSAXTree() -> String {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })
        else { return "{}" }

        let node = accessibilityNode(from: window)
        return encodeToJSON(node) ?? "{}"
    }

    private func buildIOSElementJSON(identifier: String) -> String {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })
        else { return #"{"error":"No key window"}"# }

        guard let view = findView(in: window, identifier: identifier) else {
            return #"{"error":"Element not found","identifier":"\#(identifier)"}"#
        }
        var result: [String: Any] = [:]
        result["label"] = view.accessibilityLabel ?? ""
        result["identifier"] = view.accessibilityIdentifier ?? ""
        result["value"] = view.accessibilityValue ?? ""
        result["traits"] = view.accessibilityTraits.rawValue
        result["frame"] = [
            "x": view.frame.origin.x,
            "y": view.frame.origin.y,
            "width": view.frame.size.width,
            "height": view.frame.size.height,
        ]
        return encodeToJSON(result) ?? "{}"
    }

    private func findView(in view: UIView, identifier: String) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        for subview in view.subviews {
            if let found = findView(in: subview, identifier: identifier) {
                return found
            }
        }
        return nil
    }

    private func accessibilityNode(from element: UIAccessibilityElement, depth: Int = 0, maxDepth: Int = 6) -> [String: Any] {
        var result: [String: Any] = [:]
        result["label"] = element.accessibilityLabel ?? ""
        result["identifier"] = element.accessibilityIdentifier ?? ""
        result["value"] = element.accessibilityValue ?? ""
        result["traits"] = element.accessibilityTraits.rawValue
        return result
    }
#endif

    private func encodeToJSON(_ value: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Thread-safe Result Box

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _result: ActionResult?
    private var _error: Error?

    var result: ActionResult? {
        lock.withLock { _result }
    }

    var error: Error? {
        lock.withLock { _error }
    }

    func setResult(_ value: ActionResult) {
        lock.withLock { _result = value }
    }

    func setError(_ value: Error) {
        lock.withLock { _error = value }
    }
}

// MARK: - HTTP Types

struct HTTPRequest {
    let method: String
    let path: String
    let queryParams: [String: String]
    let headers: [String: String]
    let body: String
}

struct HTTPResponse {
    let status: Int
    let body: String

    init(status: Int = 200, body: String) {
        self.status = status
        self.body = body
    }

    var statusText: String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        default: return "Unknown"
        }
    }
}

// MARK: - Simple HTTP Server

/// Minimal GCD-based HTTP/1.1 server for exposing JSON endpoints.
final class SimpleHTTPServer: @unchecked Sendable {
    private let port: UInt16
    private var routes: [String: (HTTPRequest) -> HTTPResponse] = [:]
    private var listeningSocket: Int32 = -1
    private let queue = DispatchQueue(label: "UITestingBridge.server", attributes: .concurrent)

    init(port: UInt16) {
        self.port = port
    }

    func route(_ path: String, handler: @escaping (HTTPRequest) -> HTTPResponse) {
        routes[path] = handler
    }

    func start() {
        queue.async { [weak self] in self?.runLoop() }
    }

    func stop() {
        if listeningSocket >= 0 {
            Darwin.close(listeningSocket)
            listeningSocket = -1
        }
    }

    private func runLoop() {
        let sock = socket(AF_INET6, SOCK_STREAM, 0)
        guard sock >= 0 else { return }

        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(sock, IPPROTO_IPV6, IPV6_V6ONLY, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in6()
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = port.bigEndian
        addr.sin6_addr = in6addr_any

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        guard bindResult == 0 else { Darwin.close(sock); return }
        guard listen(sock, 10) == 0 else { Darwin.close(sock); return }

        listeningSocket = sock

        while true {
            let client = accept(sock, nil, nil)
            guard client >= 0 else { break }
            queue.async { [weak self] in self?.handle(client: client) }
        }
    }

    private func handle(client: Int32) {
        defer { Darwin.close(client) }

        var buffer = [UInt8](repeating: 0, count: 65536)
        let bytesRead = recv(client, &buffer, buffer.count, 0)
        guard bytesRead > 0 else { return }

        let rawRequest = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) ?? ""
        let request = parseRequest(rawRequest)

        let routePath = request.path
        let httpResponse: HTTPResponse

        if let handler = routes[routePath] {
            httpResponse = handler(request)
        } else {
            httpResponse = HTTPResponse(status: 404, body: #"{"error":"Not Found"}"#)
        }

        let bodyBytes = httpResponse.body.utf8.count
        let response = "HTTP/1.1 \(httpResponse.status) \(httpResponse.statusText)\r\nContent-Type: application/json\r\nContent-Length: \(bodyBytes)\r\n\r\n\(httpResponse.body)"
        send(client, response, response.utf8.count, 0)
    }

    private func parseRequest(_ raw: String) -> HTTPRequest {
        let headerBodySplit = raw.components(separatedBy: "\r\n\r\n")
        let headerSection = headerBodySplit[0]
        let body = headerBodySplit.count > 1 ? headerBodySplit[1] : ""

        let lines = headerSection.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? "GET / HTTP/1.1"
        let parts = requestLine.components(separatedBy: " ")

        let method = parts.count >= 1 ? parts[0] : "GET"
        let fullPath = parts.count >= 2 ? parts[1] : "/"

        let (path, queryParams) = parsePathAndQuery(fullPath)

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let headerParts = line.split(separator: ":", maxSplits: 1)
            if headerParts.count == 2 {
                headers[String(headerParts[0]).trimmingCharacters(in: .whitespaces).lowercased()] =
                    String(headerParts[1]).trimmingCharacters(in: .whitespaces)
            }
        }

        return HTTPRequest(method: method, path: path, queryParams: queryParams, headers: headers, body: body)
    }

    private func parsePathAndQuery(_ fullPath: String) -> (String, [String: String]) {
        let components = fullPath.split(separator: "?", maxSplits: 1)
        let path = String(components[0])
        var queryParams: [String: String] = [:]

        if components.count > 1 {
            let queryString = String(components[1])
            for pair in queryString.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                    let value = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                    queryParams[key] = value
                }
            }
        }

        return (path, queryParams)
    }
}
