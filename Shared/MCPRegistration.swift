import Darwin
import Foundation

struct MCPRegistration: Codable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        var content: String
        var title: String?
    }
    var requestId: UUID
    var items: [Item]
}

struct MCPReceipt: Codable, Sendable {
    struct Item: Codable, Sendable {
        let id: UUID
        let inputIndex: Int
    }
    let requestId: UUID
    var status: String
    var items: [Item] = []
    var clipboardItemId: UUID?
    var clipboardWrite = "not_written"
    var replayed = false
    var code: String?
    var inputIndex: Int?

    static func failure(_ requestID: UUID, code: String, index: Int? = nil) -> MCPReceipt {
        MCPReceipt(requestId: requestID, status: "failed", code: code, inputIndex: index)
    }
}

struct MCPEnvelope: Codable, Sendable {
    let version: Int
    let request: MCPRegistration
}

enum MCPFailure: String, Error {
    case invalidInput = "INVALID_INPUT"
    case tooLarge = "PAYLOAD_TOO_LARGE"
    case capacity = "CAPACITY_EXCEEDED"
    case unavailable = "APP_UNAVAILABLE"
    case persistence = "PERSISTENCE_FAILED"
}

enum MCPProtocolConfig {
    static let appGroup = "R7LKF73J2W.com.nissy.Kipple"
    static let maxInputBytes = 24 * 1024 * 1024
    static let maxFrameBytes = maxInputBytes + 64 * 1024
    static let maxTextCharacters = 80_000
    static let maxBatchBytes = 16 * 1024 * 1024

    static func socketURL() throws -> URL {
#if DEBUG
        // Unsigned development builds cannot use the signed App Group container.
        // Test hosts must not replace the running development app's listener.
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            NSClassFromString("XCTest") != nil
        let suffix = isTesting ? "-test-\(getpid())" : ""
        let directory = URL(fileURLWithPath: "/private/tmp/kipple-mcp-debug-\(getuid())\(suffix)")
        return try debugSocketURL(directory: directory)
#else
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else { throw MCPFailure.unavailable }
        return group.appendingPathComponent("mcp.sock")
#endif
    }

#if DEBUG
    static func debugSocketURL(directory: URL) throws -> URL {
        guard mkdir(directory.path, 0o700) == 0 || errno == EEXIST else { throw MCPFailure.unavailable }
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw MCPFailure.unavailable }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_uid == getuid(), info.st_mode & 0o7777 == 0o700 else { throw MCPFailure.unavailable }
        return directory.appendingPathComponent("mcp.sock")
    }
#endif
}
