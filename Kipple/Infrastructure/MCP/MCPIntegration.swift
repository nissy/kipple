import AppKit
import Combine
import CryptoKit

@MainActor
final class MCPIntegration: ObservableObject {
    static let shared = MCPIntegration()
    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "mcpEnabled"); restart() }
    }
    @Published private(set) var status = ""
    private let service: ModernClipboardService
    private let defaults: UserDefaults
    private let listener: MCPListener?
    private var generation: UInt64 = 0
    private var recentRequests: [Date] = []

    init(
        service: ModernClipboardService = .shared,
        defaults: UserDefaults = .standard,
        listener: MCPListener? = MCPListener()
    ) {
        self.service = service
        self.defaults = defaults
        self.listener = listener
        enabled = defaults.bool(forKey: "mcpEnabled")
    }

    func stop() {
        generation &+= 1
        listener?.stop()
    }

    func restart() {
        stop()
        guard enabled else { status = "MCP disabled"; return }
        status = "MCP starting"
        let expected = generation
        Task {
            guard isActive(expected) else { return }
            do {
                if let listener {
                    try listener.start(path: MCPProtocolConfig.socketURL().path) { data in
                        await self.respond(data)
                    }
                }
                status = "MCP ready"
            } catch {
                if isActive(expected) { status = "MCP unavailable" }
            }
        }
    }

    static func configuration() throws -> String {
        let path = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/KippleMCP").path
        let value = ["mcpServers": ["kipple": ["command": path]]]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        guard let configuration = String(data: data, encoding: .utf8) else { throw MCPFailure.invalidInput }
        return configuration
    }

    func copyConfiguration() async -> Bool {
        guard enabled, let content = try? Self.configuration() else { return false }
        let expected = generation
        return await service.copyMCPConfiguration(content) { [weak self] in
            self?.isActive(expected) == true
        }
    }

    func respond(_ data: Data) async -> Data {
        var requestID = UUID()
        let receipt: MCPReceipt
        do {
            guard data.count <= MCPProtocolConfig.maxFrameBytes,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == ["version", "request"],
                  let rawRequest = object["request"] else { throw MCPFailure.invalidInput }
            let envelope = try JSONDecoder().decode(MCPEnvelope.self, from: data)
            requestID = envelope.request.requestId
            _ = try MCPInputValidation.decode(JSONSerialization.data(withJSONObject: rawRequest))
            receipt = await register(envelope)
        } catch let error as MCPFailure {
            receipt = .failure(requestID, code: error.rawValue)
        } catch {
            receipt = .failure(requestID, code: "INVALID_INPUT")
        }
        return (try? JSONEncoder().encode(receipt)) ?? Data()
    }

    func register(_ envelope: MCPEnvelope) async -> MCPReceipt {
        let request = envelope.request
        guard envelope.version == 1 else { return .failure(request.requestId, code: "VERSION_MISMATCH") }
        guard enabled else { return .failure(request.requestId, code: "INTEGRATION_DISABLED") }
        let expected = generation
        let now = Date()
        recentRequests.removeAll { now.timeIntervalSince($0) >= 60 }
        guard recentRequests.count < 60 else { return .failure(request.requestId, code: "RATE_LIMITED") }
        recentRequests.append(now)
        do {
            return try await process(request, generation: expected, now: now)
        } catch let error as MCPFailure {
            return .failure(request.requestId, code: error.rawValue)
        } catch { return .failure(request.requestId, code: "PERSISTENCE_FAILED") }
    }

    private func process(_ request: MCPRegistration, generation expected: UInt64, now: Date) async throws -> MCPReceipt {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(request)
        _ = try MCPInputValidation.decode(data)
        let digest = Data(SHA256.hash(data: data))
        let key = request.requestId.uuidString
        if let previous = try await service.previousReceipt(key: key) {
            guard isActive(expected) else { return .failure(request.requestId, code: "INTEGRATION_DISABLED") }
            return previous.replay(digest: digest)
        }
        let items = try await Task.detached { try Self.prepare(request.items, now: now) }.value
        guard isActive(expected) else { return .failure(request.requestId, code: "INTEGRATION_DISABLED") }
        let record = MCPStoredReceipt(
            key: key, digest: digest, receivedAt: now,
            result: MCPReceipt(requestId: request.requestId, status: "clipboard_unknown")
        )
        return try await service.registerMCP(items, record: record) { [weak self] in
            self?.isActive(expected) == true
        }
    }

    private func isActive(_ expected: UInt64) -> Bool {
        enabled && generation == expected
    }

    nonisolated private static func prepare(_ inputs: [MCPRegistration.Item], now: Date) throws -> [ClipItem] {
        var bytes = 0
        return try inputs.enumerated().map { index, input in
            let content = try MCPInputValidation.text(input.content)
            bytes += content.utf8.count
            guard bytes <= MCPProtocolConfig.maxBatchBytes else { throw MCPFailure.tooLarge }
            let metadata = ClipMetadata(
                title: try MCPInputValidation.title(input.title), createdAt: now, source: .mcp
            )
            var item = ClipItem(content: content, sourceApp: "MCP", metadata: metadata)
            item.timestamp = now.addingTimeInterval(-Double(index) * 0.001)
            return item
        }
    }
}
