import Foundation
import XCTest
@testable import Kipple

@MainActor
final class MCPConfigurationTests: XCTestCase {
    func testJSONKeepsTheExecutablePathWithoutShellQuoting() throws {
        let path = "/Applications/日本語 O'Reilly/Kipple.app/Contents/Helpers/KippleMCP"
        let text = try MCPIntegration.configuration(for: .json, helperURL: URL(fileURLWithPath: path))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: [String: String]])
        XCTAssertEqual(servers, ["kipple": ["command": path]])
    }

    func testAddCommandsPreserveThePathAsOneLiteralShellArgument() throws {
        let paths = [
            "/Applications/Kipple.app/Contents/Helpers/KippleMCP",
            "/Applications/AI tools/日本語 O'Reilly/Kipple.app/Contents/Helpers/KippleMCP",
            "/Applications/$HOME $(printf injected) `printf injected`; \"quoted\"/KippleMCP",
            "/Applications/line\nbreak/KippleMCP"
        ]
        for shell in ["/bin/sh", "/bin/zsh"] {
            for path in paths {
                for format in [MCPIntegration.ConfigurationFormat.codex, .claudeCode] {
                    let command = try MCPIntegration.configuration(for: format, helperURL: URL(fileURLWithPath: path))
                    let arguments = try shellArguments(command, shell: shell)
                    let prefix = format == .codex
                        ? ["mcp", "add", "kipple", "--"]
                        : ["mcp", "add", "--transport", "stdio", "--scope", "user", "kipple", "--"]
                    XCTAssertEqual(arguments, prefix + [path], "\(shell): \(format)")
                }
            }
        }
    }

    private func shellArguments(_ command: String, shell: String) throws -> [String] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        let script = """
        codex() { printf '%s\\0' "$@"; }
        claude() { printf '%s\\0' "$@"; }
        \(command)
        """
        process.arguments = ["-f", "-c", script]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let text = try XCTUnwrap(String(bytes: data, encoding: .utf8))
        return text.split(separator: "\0").map(String.init)
    }
}
