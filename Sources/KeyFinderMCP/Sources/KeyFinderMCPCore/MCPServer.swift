import Foundation

/// Minimal MCP server over JSON-RPC 2.0 (tools only).
///
/// Written by hand instead of using modelcontextprotocol/swift-sdk: the SDK needs macOS 13
/// and several transitive packages, while KeyFinder supports macOS 12 and five tools over
/// stdio need only initialize, tools/list, tools/call and ping.
public struct MCPServer: Sendable {
    public static let serverVersion = "3.0.2"
    /// Newest first. The client's requested version is echoed back when supported.
    public static let supportedProtocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    static let instructions = """
    KeyFinder analyzes local audio files on this Mac: musical key (Camelot notation), BPM, \
    energy and key changes. Use it as a DJ and production assistant: analyze a folder, \
    find tracks that mix out of a track, build a harmonic set with an energy shape, or \
    work out how to transpose and stretch a sample to fit a project. Audio never leaves \
    the machine. Only folders the user allowed can be read.
    """

    let tools: ToolBox

    public init(tools: ToolBox) {
        self.tools = tools
    }

    /// Handles one line from the client. Returns the response line, or nil for
    /// notifications and responses that need no reply.
    public func handle(line: String) async -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: Data(trimmed.utf8)),
              case .object = message else {
            return Self.encode(Self.error(id: .null, code: -32700, message: "Parse error"))
        }
        guard let method = message["method"]?.stringValue else {
            // A response to something we never send, or malformed: ignore unless it has an id.
            guard let id = message["id"], message["result"] == nil, message["error"] == nil else { return nil }
            return Self.encode(Self.error(id: id, code: -32600, message: "Invalid request"))
        }
        guard let id = message["id"] else { return nil }  // notification

        let response = await respond(id: id, method: method, params: message["params"] ?? [:])
        return Self.encode(response)
    }

    private func respond(id: JSONValue, method: String, params: JSONValue) async -> JSONValue {
        switch method {
        case "initialize":
            let requested = params["protocolVersion"]?.stringValue ?? ""
            let version = Self.supportedProtocolVersions.contains(requested) ? requested : Self.supportedProtocolVersions[0]
            return Self.result(id: id, [
                "protocolVersion": .string(version),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "keyfinder", "title": "KeyFinder", "version": .string(Self.serverVersion)],
                "instructions": .string(Self.instructions),
            ])
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": .array(tools.definitions)])
        case "tools/call":
            guard let name = params["name"]?.stringValue else {
                return Self.error(id: id, code: -32602, message: "tools/call needs a tool name")
            }
            guard tools.definitions.contains(where: { $0["name"]?.stringValue == name }) else {
                return Self.error(id: id, code: -32602, message: "Unknown tool: \(name)")
            }
            return Self.result(id: id, await callTool(name, arguments: params["arguments"] ?? [:]))
        default:
            return Self.error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    /// Tool failures are results with isError, so the model sees the message and can recover.
    private func callTool(_ name: String, arguments: JSONValue) async -> JSONValue {
        do {
            let structured = try await tools.call(name, arguments: arguments)
            return [
                "content": [["type": "text", "text": .string(Self.prettyText(structured))]],
                "structuredContent": structured,
                "isError": false,
            ]
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return ["content": [["type": "text", "text": .string(message)]], "isError": true]
        }
    }

    // MARK: - Encoding

    static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(id: JSONValue, code: Int, message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(message)]]
    }

    /// One message per line: the stdio transport forbids embedded newlines.
    static func encode(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
        }
        return text
    }

    static func prettyText(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
