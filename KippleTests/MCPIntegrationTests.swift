import AppKit
import XCTest
@testable import Kipple

@MainActor
final class MCPIntegrationTests: XCTestCase {
    private struct Fixture {
        let integration: MCPIntegration
        let service: ModernClipboardService
    }

    private func fixture() throws -> Fixture {
        let suite = "Kipple.MCPIntegrationTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "mcpEnabled")
        addTeardownBlock {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        let service = ModernClipboardService(testRepository: try SwiftDataRepository.make(inMemory: true))
        let integration = MCPIntegration(service: service, defaults: defaults, listener: nil)
        return Fixture(integration: integration, service: service)
    }

    func testTokenlessRegistrationReplaysAfterReenableWithoutCopy() async throws {
        let context = try fixture()
        let integration = context.integration
        let request = MCPRegistration(requestId: UUID(), items: [.init(content: "AI result", title: "Result")])
        let first = await integration.register(.init(version: 1, request: request))
        XCTAssertEqual(first.status, "completed")
        await context.service.writeToClipboardOnly("Later user copy")
        integration.enabled = false
        let rejected = await integration.register(.init(version: 1, request: request))
        XCTAssertEqual(rejected.code, "INTEGRATION_DISABLED")
        integration.enabled = true
        let replay = await integration.register(.init(version: 1, request: request))
        XCTAssertTrue(replay.replayed)
        XCTAssertEqual(replay.items.map(\.id), first.items.map(\.id))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Later user copy")
        var changed = request
        changed.items[0].content = "Changed request"
        let conflict = await integration.register(.init(version: 1, request: changed))
        XCTAssertEqual(conflict.code, "REQUEST_ID_CONFLICT")
    }

    func testConfigurationContainsOnlyCommandAndDoesNotEnterHistory() async throws {
        let context = try fixture()
        let copied = await context.integration.copyConfiguration()
        XCTAssertTrue(copied)
        let configuration = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(configuration.utf8)) as? [String: Any])
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: [String: String]])
        let server = try XCTUnwrap(servers["kipple"])
        XCTAssertEqual(Set(server.keys), ["command"])
        XCTAssertTrue(try XCTUnwrap(server["command"]).hasSuffix("/Contents/Helpers/KippleMCP"))
        let visible = await context.service.getCurrentClipboardContent()
        XCTAssertEqual(visible, configuration)
        let history = await context.service.getHistory()
        XCTAssertTrue(history.isEmpty)
        context.integration.enabled = false
        context.integration.enabled = true
        let copiedAgain = await context.integration.copyConfiguration()
        XCTAssertTrue(copiedAgain)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), configuration)
    }

    func testDisabledMCPDoesNotRegisterOrCopySettings() async throws {
        let context = try fixture()
        await context.service.writeToClipboardOnly("Keep this clipboard")
        context.integration.enabled = false
        for format in MCPIntegration.ConfigurationFormat.allCases {
            let copied = await context.integration.copyConfiguration(for: format)
            XCTAssertFalse(copied)
        }
        let result = await context.integration.register(.init(
            version: 1, request: .init(requestId: UUID(), items: [.init(content: "Blocked")])
        ))
        XCTAssertEqual(result.code, "INTEGRATION_DISABLED")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Keep this clipboard")
        let history = await context.service.getHistory()
        XCTAssertTrue(history.isEmpty)
    }

    func testAllConfigurationFormatsCopyWithoutEnteringHistory() async throws {
        let context = try fixture()
        for format in MCPIntegration.ConfigurationFormat.allCases {
            let copied = await context.integration.copyConfiguration(for: format)
            XCTAssertTrue(copied)
            let expected = try MCPIntegration.configuration(for: format)
            XCTAssertEqual(NSPasteboard.general.string(forType: .string), expected)
            let visible = await context.service.getCurrentClipboardContent()
            XCTAssertEqual(visible, expected)
            let history = await context.service.getHistory()
            XCTAssertTrue(history.isEmpty)
        }
    }

    func testDisablingMCPImmediatelyBeforeConfigurationWritePreservesClipboard() async throws {
        for format in MCPIntegration.ConfigurationFormat.allCases {
            for reenable in [false, true] {
                let context = try fixture()
                let integration = context.integration
                await context.service.writeToClipboardOnly("Keep this clipboard")
                let observer = NotificationCenter.default.addObserver(forName: .mcpWillCopy, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated {
                        integration.enabled = false
                        if reenable { integration.enabled = true }
                    }
                }
                let copied = await integration.copyConfiguration(for: format)
                NotificationCenter.default.removeObserver(observer)
                XCTAssertFalse(copied)
                XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Keep this clipboard")
            }
        }
    }

    func testDisablingMCPImmediatelyBeforeRegistrationWritePreservesClipboard() async throws {
        for reenable in [false, true] {
            let context = try fixture()
            let integration = context.integration
            await context.service.writeToClipboardOnly("Keep this clipboard")
            let observer = NotificationCenter.default.addObserver(forName: .mcpWillCopy, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    integration.enabled = false
                    if reenable { integration.enabled = true }
                }
            }
            let result = await integration.register(.init(
                version: 1, request: .init(requestId: UUID(), items: [.init(content: "AI result")])
            ))
            NotificationCenter.default.removeObserver(observer)
            XCTAssertEqual(result.status, "clipboard_failed")
            XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Keep this clipboard")
        }
    }

    func testEightyThousandCharactersAreCopiedExactlyAndLargerBatchIsRejected() async throws {
        for character in ["a", "あ", "😀"] {
            let context = try fixture()
            let content = String(repeating: character, count: 80_000)
            let result = await context.integration.register(.init(
                version: 1, request: .init(requestId: UUID(), items: [.init(content: content)])
            ))
            XCTAssertEqual(result.status, "completed")
            XCTAssertEqual(NSPasteboard.general.string(forType: .string), content)
            let rejected = await context.integration.register(.init(
                version: 1, request: .init(requestId: UUID(), items: [
                    .init(content: "Must not be registered"), .init(content: content + character)
                ])
            ))
            XCTAssertEqual(rejected.code, "PAYLOAD_TOO_LARGE")
            XCTAssertEqual(NSPasteboard.general.string(forType: .string), content)
            let history = await context.service.getHistory()
            XCTAssertEqual(history.map(\.content), [content])
        }
    }

    func testIPCRejectsRemovedFieldsAndAcceptsTokenlessEnvelope() async throws {
        let context = try fixture()
        let envelope = MCPEnvelope(version: 1, request: .init(requestId: UUID(), items: [.init(content: "Test")]))
        let data = try JSONEncoder().encode(envelope)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for field in ["token", "connectionId", "folderBookmark", "unexpected"] {
            var object = original
            object[field] = "obsolete"
            let response = await context.integration.respond(try JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(try JSONDecoder().decode(MCPReceipt.self, from: response).code, "INVALID_INPUT")
        }
        for field in ["sensitive", "expiresAt"] {
            var object = original
            object["request"] = [
                "requestId": UUID().uuidString,
                "items": [["content": "Must not be registered", field: "removed"]]
            ]
            let response = await context.integration.respond(try JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(try JSONDecoder().decode(MCPReceipt.self, from: response).code, "INVALID_INPUT")
            let history = await context.service.getHistory()
            XCTAssertTrue(history.isEmpty)
        }
        let response = await context.integration.respond(data)
        XCTAssertEqual(try JSONDecoder().decode(MCPReceipt.self, from: response).status, "completed")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Test")
    }
}
