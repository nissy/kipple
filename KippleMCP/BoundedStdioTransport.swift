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
                    if !frame.isEmpty, case .dropped = continuation.yield(frame) { throw MCPFailure.tooLarge }
                    pending.removeSubrange(...newline)
                }
                guard pending.count <= MCPProtocolConfig.maxInputBytes else { throw MCPFailure.tooLarge }
            }
            continuation.finish()
        } catch { continuation.finish(throwing: MCPFailure.invalidInput) }
    }

    func disconnect() async { continuation.finish() }

    func send(_ data: Data) async throws {
        var line = data
        line.append(10)
        try FileHandle.standardOutput.write(contentsOf: line)
    }

    func receive() -> AsyncThrowingStream<Data, Error> { messages }
}
