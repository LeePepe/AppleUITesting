import Foundation

/// MCP Server implementing stdio JSON-RPC transport for the Model Context Protocol.
@main
struct MCPServerMain {
    static func main() async {
        let server = MCPServer()
        await server.run()
    }
}

final class MCPServer: Sendable {
    private let toolDefinitions = ToolDefinitions()
    private let toolHandlers: ToolHandlers

    init(host: String = "localhost", port: Int = 7979) {
        self.toolHandlers = ToolHandlers(host: host, port: port)
    }

    func run() async {
        setbuf(stdout, nil)
        setbuf(stdin, nil)

        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }
            let response = await handleMessage(line)
            if let response {
                print(response)
                fflush(stdout)
            }
        }
    }

    private func handleMessage(_ message: String) async -> String? {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return encodeError(id: nil, code: -32700, message: "Parse error")
        }

        let id = json["id"]
        let method = json["method"] as? String ?? ""

        switch method {
        case "initialize":
            return handleInitialize(id: id)
        case "initialized":
            return nil
        case "tools/list":
            return handleToolsList(id: id)
        case "tools/call":
            let params = json["params"] as? [String: Any] ?? [:]
            return await handleToolsCall(id: id, params: params)
        case "ping":
            return encodeResult(id: id, result: [:])
        default:
            return encodeError(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func handleInitialize(id: Any?) -> String {
        let result: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": [
                    "listChanged": false
                ]
            ],
            "serverInfo": [
                "name": "apple-ui-tester-mcp",
                "version": "1.0.0",
            ],
        ]
        return encodeResult(id: id, result: result)
    }

    private func handleToolsList(id: Any?) -> String {
        let tools = toolDefinitions.allTools()
        let result: [String: Any] = ["tools": tools]
        return encodeResult(id: id, result: result)
    }

    private func handleToolsCall(id: Any?, params: [String: Any]) async -> String {
        guard let name = params["name"] as? String else {
            return encodeError(id: id, code: -32602, message: "Missing tool name")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]

        let response = await toolHandlers.handle(tool: name, arguments: arguments)
        return encodeResult(id: id, result: response)
    }

    // MARK: - JSON-RPC Encoding

    private func encodeResult(id: Any?, result: [String: Any]) -> String {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result,
        ]
        if let id { response["id"] = id }
        return jsonString(response)
    }

    private func encodeError(id: Any?, code: Int, message: String) -> String {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "error": [
                "code": code,
                "message": message,
            ],
        ]
        if let id { response["id"] = id }
        return jsonString(response)
    }

    private func jsonString(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return #"{"jsonrpc":"2.0","error":{"code":-32603,"message":"Internal encoding error"}}"#
        }
        return str
    }
}
