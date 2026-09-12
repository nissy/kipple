import Foundation
import AppKit
import MCP

@main
struct KippleMCPMain {
    static func main() async {
        do {
            let server = Server(name: "Kipple", version: "1.0.0", capabilities: .init(tools: .init()))
            await server.withMethodHandler(ListTools.self) { _ in
                .init(tools: [try makeTool()])
            }
            await server.withMethodHandler(CallTool.self) { params in
                guard params.name == "kipple_add_items" else { throw MCPError.methodNotFound(params.name) }
                return await call(params.arguments ?? [:])
            }
            try await server.start(transport: BoundedStdioTransport())
            await server.waitUntilCompleted()
        } catch {
            try? FileHandle.standardError.write(contentsOf: Data("Kipple MCP could not start.\n".utf8))
        }
    }

    private static func makeTool() throws -> Tool {
        let schema = #"""
        {"type":"object","additionalProperties":false,"required":["requestId","items"],"properties":{
          "requestId":{"type":"string","format":"uuid","description":"Reuse for retries within 24 hours."},
          "items":{"type":"array","minItems":1,"maxItems":50,"items":{
            "type":"object","additionalProperties":false,
            "required":["content"],
            "properties":{
              "content":{"type":"string","minLength":1,"maxLength":80000,"description":"Exact text, up to 80,000 Unicode code points. No truncation."},
              "title":{"type":"string","maxLength":120,"description":"Purpose of the text."}
            }
          }}
        }}
        """#
        return Tool(
            name: "kipple_add_items",
            description: "Register text in Kipple history and REPLACE the current clipboard with the first item. " +
                "Does not paste into another app or read history. Active Queue ends.",
            inputSchema: try JSONDecoder().decode(Value.self, from: Data(schema.utf8)),
            annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false),
            outputSchema: .object(["type": .string("object")])
        )
    }

    private static func call(_ arguments: [String: Value]) async -> CallTool.Result {
        var requestID = UUID()
        do {
            let request = try MCPInputValidation.decode(JSONEncoder().encode(arguments))
            requestID = request.requestId
            let payload = try JSONEncoder().encode(MCPEnvelope(version: 1, request: request))
            let path = try MCPProtocolConfig.socketURL().path
            if !FileManager.default.fileExists(atPath: path) ||
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.nissy.Kipple").isEmpty {
                await launchApplication()
            }
            let response = try await Task.detached { try LocalMCPTransport.request(payload, path: path) }.value
            return try result(JSONDecoder().decode(MCPReceipt.self, from: response))
        } catch let error as MCPFailure {
            return (try? result(.failure(requestID, code: error.rawValue))) ?? .init(content: [], isError: true)
        } catch {
            return (try? result(.failure(requestID, code: "INVALID_INPUT"))) ?? .init(content: [], isError: true)
        }
    }

    private static func result(_ receipt: MCPReceipt) throws -> CallTool.Result {
        let data = try JSONEncoder().encode(receipt)
        guard let text = String(data: data, encoding: .utf8) else { throw MCPFailure.invalidInput }
        return try .init(
            content: [.text(text: text, annotations: nil, _meta: nil)],
            structuredContent: try JSONDecoder().decode(Value.self, from: data),
            isError: receipt.status != "completed"
        )
    }

    @MainActor
    private static func launchApplication() async {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.nissy.Kipple") else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
        for _ in 0..<40 {
            if let url = try? MCPProtocolConfig.socketURL(), FileManager.default.fileExists(atPath: url.path) { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}
