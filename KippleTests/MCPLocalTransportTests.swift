import Darwin
import AppKit
import SwiftData
import XCTest
@testable import Kipple

final class MCPLocalTransportTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testSocketRegistrationPersistsHistoryAndReceiptAfterReopeningStore() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "Kipple.MCPPersistenceTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "mcpEnabled")
        let pasteboard = NSPasteboard.withUniqueName()
        defer {
            pasteboard.releaseGlobally()
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let schema = Schema([ClipItemModel.self, MCPReceiptModel.self])
        let config = ModelConfiguration(schema: schema, url: root.appendingPathComponent("history.store"))
        let repository = try SwiftDataRepository.make(container: ModelContainer(for: schema, configurations: [config]))
        let writer: @MainActor @Sendable (ClipItem) -> Int = {
            ClipboardRichText.write($0, to: pasteboard)
        }
        let service = ModernClipboardService(testRepository: repository, clipboardWriter: writer)
        let integration = MCPIntegration(service: service, defaults: defaults, listener: nil)
        let path = root.appendingPathComponent("mcp.sock").path
        let listener = MCPListener()
        defer { listener.stop() }
        try listener.start(path: path) { await integration.respond($0) }
        let request = MCPRegistration(requestId: UUID(), items: [.init(content: "Saved over IPC", title: "IPC check")])
        let payload = try JSONEncoder().encode(MCPEnvelope(version: 1, request: request))
        let response = try await Task.detached { try LocalMCPTransport.request(payload, path: path) }.value
        let receipt = try JSONDecoder().decode(MCPReceipt.self, from: response)
        XCTAssertEqual(receipt.status, "completed")
        XCTAssertEqual(pasteboard.string(forType: .string), "Saved over IPC")
        listener.stop()
        let reopened = try SwiftDataRepository.make(container: ModelContainer(for: schema, configurations: [config]))
        let saved = try await reopened.loadAll()
        XCTAssertEqual(saved.map(\.content), ["Saved over IPC"])
        XCTAssertEqual(saved.first?.metadata?.title, "IPC check")
        let storedReceipt = try await reopened.receipt(for: request.requestId.uuidString)
        XCTAssertNotNil(storedReceipt)
    }

    @MainActor
    func testTokenlessRegistrationOverPrivateSocketEnforcesCharacterLimit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "Kipple.MCPSocketTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "mcpEnabled")
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let service = ModernClipboardService(testRepository: try SwiftDataRepository.make(inMemory: true))
        let integration = MCPIntegration(service: service, defaults: defaults, listener: nil)
        let path = root.appendingPathComponent("mcp.sock").path
        let listener = MCPListener()
        defer { listener.stop() }
        try listener.start(path: path) { await integration.respond($0) }
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        let content = String(repeating: "😀", count: 80_000)
        for suffix in ["", "a"] {
            let payload = try JSONEncoder().encode(MCPEnvelope(
                version: 1, request: .init(requestId: UUID(), items: [.init(content: content + suffix)])
            ))
            let data = try await Task.detached { try LocalMCPTransport.request(payload, path: path) }.value
            let receipt = try JSONDecoder().decode(MCPReceipt.self, from: data)
            if suffix.isEmpty {
                XCTAssertEqual(receipt.status, "completed")
            } else {
                XCTAssertEqual(receipt.code, "PAYLOAD_TOO_LARGE")
            }
        }
        let clipboard = await service.getCurrentClipboardContent()
        XCTAssertEqual(clipboard, content)
        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.content), [content])
    }

    func testUnixSocketRoundTripAndRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("mcp.sock").path
        let listener = MCPListener()
        defer { listener.stop() }
        let payload = Data(String(repeating: "日本語\n", count: 100_000).utf8)
        for _ in 0..<3 {
            try listener.start(path: path) { $0 }
            let response = try await Task.detached { try LocalMCPTransport.request(payload, path: path) }.value
            XCTAssertEqual(response, payload)
            listener.stop()
        }
    }

    func testRejectsOversizedFrameBeforeAllocatingPayload() throws {
        var descriptors: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
        defer { descriptors.forEach { close($0) } }
        var size = UInt32(MCPProtocolConfig.maxFrameBytes + 1).bigEndian
        XCTAssertEqual(Darwin.write(descriptors[0], &size, 4), 4)
        XCTAssertThrowsError(try LocalMCPTransport.readFrame(descriptors[1])) { error in
            XCTAssertEqual(error as? MCPFailure, .tooLarge)
        }
    }
}
