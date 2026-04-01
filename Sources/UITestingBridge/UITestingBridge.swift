import Foundation
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

    /// Shared singleton instance.
    public static let shared = UITestingBridge()

    private init() {}

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
        srv.route("/ax-tree") { [weak self] in
            self?.buildAXTreeJSON() ?? "{}"
        }
        srv.route("/health") {
            #"{"status":"ok"}"#
        }
        server = srv
        srv.start()
    }

    private func buildAXTreeJSON() -> String {
#if os(macOS)
        return buildMacOSAXTree()
#elseif os(iOS)
        return buildIOSAXTree()
#else
        return "{}"
#endif
    }

#if os(macOS)
    private func buildMacOSAXTree() -> String {
        let axApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let node = axNodeFromElement(axApp, depth: 0, maxDepth: 6)
        return encodeToJSON(node) ?? "{}"
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
        // On iOS, use UIAccessibility to build a simplified tree from the key window
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        else { return "{}" }

        let node = accessibilityNode(from: window)
        return encodeToJSON(node) ?? "{}"
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

// MARK: - Simple HTTP Server

/// Minimal GCD-based HTTP/1.1 server for exposing JSON endpoints.
final class SimpleHTTPServer: @unchecked Sendable {
    private let port: UInt16
    private var routes: [String: () -> String] = [:]
    private var listeningSocket: Int32 = -1
    private let queue = DispatchQueue(label: "UITestingBridge.server", attributes: .concurrent)

    init(port: UInt16) {
        self.port = port
    }

    func route(_ path: String, handler: @escaping () -> String) {
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

        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = recv(client, &buffer, buffer.count, 0)
        guard bytesRead > 0 else { return }

        let request = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) ?? ""
        let path = parsePath(from: request)
        let body: String

        if let handler = routes[path] {
            body = handler()
        } else {
            let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found"
            send(client, response, response.utf8.count, 0)
            return
        }

        let bodyBytes = body.utf8.count
        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(bodyBytes)\r\n\r\n\(body)"
        send(client, response, response.utf8.count, 0)
    }

    private func parsePath(from request: String) -> String {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return "/" }
        let parts = firstLine.components(separatedBy: " ")
        return parts.count >= 2 ? parts[1] : "/"
    }
}
