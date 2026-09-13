import Darwin
import XCTest
@testable import Kipple

final class MCPDebugSocketTests: XCTestCase {
    func testConfiguredEndpointIsIsolatedFromRunningDevelopmentApp() throws {
        let endpoint = try MCPProtocolConfig.socketURL()
        let directory = endpoint.deletingLastPathComponent()
        XCTAssertEqual(directory.lastPathComponent, "kipple-mcp-debug-\(getuid())-test-\(getpid())")
        XCTAssertNotEqual(directory.lastPathComponent, "kipple-mcp-debug-\(getuid())")
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testCreatesPrivateDirectoryAndReusesEndpoint() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try MCPProtocolConfig.debugSocketURL(directory: root)
        XCTAssertEqual(first, try MCPProtocolConfig.debugSocketURL(directory: root))
        XCTAssertEqual(first.lastPathComponent, "mcp.sock")
        let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((attributes[.ownerAccountID] as? NSNumber)?.uint32Value, getuid())
    }

    func testRejectsUnsafeDirectoryWithoutChangingPermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(chmod(root.path, 0o755), 0)
        XCTAssertThrowsError(try MCPProtocolConfig.debugSocketURL(directory: root))
        let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o755)
    }

    func testRejectsSymlinkAndRegularFileWithoutReplacingThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target")
        _ = try MCPProtocolConfig.debugSocketURL(directory: target)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try MCPProtocolConfig.debugSocketURL(directory: link))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
        let file = root.appendingPathComponent("file")
        let content = Data("preserve".utf8)
        try content.write(to: file)
        XCTAssertThrowsError(try MCPProtocolConfig.debugSocketURL(directory: file))
        XCTAssertEqual(try Data(contentsOf: file), content)
    }
}
