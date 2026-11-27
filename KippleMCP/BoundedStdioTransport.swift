import Foundation
import Darwin
import MCP
import Logging

actor BoundedStdioTransport: Transport {
    nonisolated let logger = Logger(label: "com.nissy.Kipple.MCP")
    private let messages: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    init() {
        let pair = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(8))
        messages = pair.stream
        continuation = pair.continuation
    }

    func connect() async throws {
        let continuation = continuation
        DispatchQueue(label: "com.nissy.Kipple.mcp-stdin").async {
            Self.readInput(continuation)
        }
    }

    private nonisolated static func readInput(_ continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        do {
            var pending = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                guard count >= 0 else { throw MCPFailure.invalidInput }
                if count == 0 { break }
                pending.append(contentsOf: buffer.prefix(count))
                while let newline = pending.firstIndex(of: 10) {
                    let frame = Data(pending[..<newline])
                    guard frame.count <= MCPProtocolConfig.maxInputBytes else { throw MCPFailure.tooLarge }
                    if !frame.isEmpty, case .dropped = continuation.yield(compatibleInitialization(frame)) {
                        throw MCPFailure.tooLarge
                    }
                    pending.removeSubrange(...newline)
                }
                guard pending.count <= MCPProtocolConfig.maxInputBytes else { throw MCPFailure.tooLarge }
            }
            continuation.finish()
        } catch { continuation.finish(throwing: MCPFailure.invalidInput) }
    }

    private nonisolated static func compatibleInitialization(_ frame: Data) -> Data {
        guard var request = (try? JSONSerialization.jsonObject(with: frame)) as? [String: Any],
              request["method"] as? String == "initialize",
              var parameters = request["params"] as? [String: Any],
              var capabilities = parameters["capabilities"] as? [String: Any],
              let experimental = capabilities["experimental"] as? [String: Any] else { return frame }

        // Swift SDK 0.12.1 decodes experimental capabilities as a string dictionary.
        let strings = experimental.compactMapValues { $0 as? String }
        guard strings.count != experimental.count else { return frame }
        capabilities["experimental"] = strings
        parameters["capabilities"] = capabilities
        request["params"] = parameters
        return (try? JSONSerialization.data(withJSONObject: request)) ?? frame
    }

    func disconnect() async { continuation.finish() }

    func send(_ data: Data) async throws {
        var line = data
        line.append(10)
        try FileHandle.standardOutput.write(contentsOf: line)
    }

    func receive() -> AsyncThrowingStream<Data, Error> { messages }
}
