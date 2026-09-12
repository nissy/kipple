import AppKit
import XCTest
@testable import Kipple

final class MCPRegistrationTests: XCTestCase, @unchecked Sendable {
    private func receipt(digest: Data = Data([1]), requestID: UUID = UUID()) -> MCPStoredReceipt {
        MCPStoredReceipt(
            key: requestID.uuidString, digest: digest, receivedAt: Date(), result: MCPReceipt(requestId: requestID, status: "clipboard_unknown")
        )
    }

    func testAtomicBatchAndRetryDoesNotCopyAgain() async throws {
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository)
        let record = receipt()
        let first = ClipItem(content: "MCP first", metadata: ClipMetadata(title: "First", source: .mcp))
        let second = ClipItem(content: "MCP second", metadata: ClipMetadata(title: "Second", source: .mcp))
        let result = try await service.registerMCP([first, second], record: record)
        XCTAssertEqual(result.items.map(\.id), [first.id, second.id])
        XCTAssertEqual(result.clipboardWrite, "written")
        let loaded = try await repository.loadAll()
        XCTAssertEqual(Set(loaded.map(\.id)), Set([first.id, second.id]))
        await service.writeToClipboardOnly("Newer user clipboard")
        let replay = try await service.registerMCP([first, second], record: record)
        XCTAssertTrue(replay.replayed)
        let content = await service.getCurrentClipboardContent()
        XCTAssertEqual(content, "Newer user clipboard")
        let conflict = MCPStoredReceipt(
            key: record.key, digest: Data([2]), receivedAt: Date(), result: record.result
        )
        let conflictResult = try await service.registerMCP([first], record: conflict)
        XCTAssertEqual(conflictResult.code, "REQUEST_ID_CONFLICT")
    }

    func testCanceledCopyAndClearDoNotReplaceNewerClipboard() async throws {
        let service = ModernClipboardService(testRepository: try SwiftDataRepository.make(inMemory: true))
        await service.writeToClipboardOnly("newer")
        await service.copyToClipboard("stale copy", fromEditor: false) { false }
        await service.recopyFromHistory(ClipItem(content: "stale")) { false }
        await service.clearSystemClipboard { false }
        await service.writeToClipboardOnly("stale edit") { false }
        let current = await service.getCurrentClipboardContent()
        XCTAssertEqual(current, "newer")
        let history = await service.getHistory()
        XCTAssertTrue(history.isEmpty)
    }

    func testCapacityAndDisabledIntegrationHaveNoSideEffects() async throws {
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository)
        await service.setMaxHistoryItems(1)
        let items = [ClipItem(content: "a"), ClipItem(content: "b")]
        do {
            _ = try await service.registerMCP(items, record: receipt())
            XCTFail("Capacity must reject the entire batch")
        } catch { XCTAssertEqual(error as? MCPFailure, .capacity) }
        let disabled = try await service.registerMCP([items[0]], record: receipt()) { false }
        XCTAssertEqual(disabled.code, "INTEGRATION_DISABLED")
        let history = await service.getHistory()
        let persisted = try await repository.loadAll()
        XCTAssertTrue(history.isEmpty)
        XCTAssertTrue(persisted.isEmpty)
    }

    func testTitleEditPersistsWithoutCopyingOrReorderingHistory() async throws {
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository)
        let first = ClipItem(content: "First", sourceApp: "MCP", metadata: ClipMetadata(title: "Old", source: .mcp))
        let second = ClipItem(content: "Second")
        _ = try await service.registerMCP([first, second], record: receipt())
        await service.writeToClipboardOnly("edited draft")
        let changeCount = await MainActor.run { NSPasteboard.general.changeCount }

        try await service.updateDetails(id: first.id, title: "  New\nTitle  ")

        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.id), [first.id, second.id])
        XCTAssertEqual(history.first?.title, "New Title")
        XCTAssertEqual(history.first?.content, "First")
        let persisted = try await repository.loadAll()
        XCTAssertEqual(persisted.first { $0.id == first.id }?.title, "New Title")
        let clipboard = await service.getCurrentClipboardContent()
        XCTAssertEqual(clipboard, "edited draft")
        let afterCount = await MainActor.run { NSPasteboard.general.changeCount }
        XCTAssertEqual(afterCount, changeCount)

        try await service.updateDetails(id: first.id, title: " ")
        let untitled = await service.getHistory()
        XCTAssertNil(untitled.first?.title)
    }

    func testMCPHistoryAndReceiptsSurviveServiceRestart() async throws {
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository)
        let item = ClipItem(content: "AI result", sourceApp: "MCP", metadata: ClipMetadata(
            title: "Release notes", createdAt: Date(), source: .mcp
        ))
        let record = receipt()
        _ = try await service.registerMCP([item], record: record)
        await service.writeToClipboardOnly("Later user copy")

        let restarted = ModernClipboardService(testRepository: repository)
        await restarted.loadHistoryFromRepository()
        let history = await restarted.getHistory()
        XCTAssertEqual(history.map(\.id), [item.id])
        XCTAssertEqual(history.first?.title, item.title)
        XCTAssertEqual(history.first?.sourceApp, "MCP")
        XCTAssertEqual(history.first?.metadata, item.metadata)

        let replay = try await restarted.registerMCP([item], record: record)
        XCTAssertTrue(replay.replayed)
        XCTAssertEqual(replay.status, "completed")
        let clipboard = await restarted.getCurrentClipboardContent()
        XCTAssertEqual(clipboard, "Later user copy")
    }

    func testRecopyPreservesMCPDetailsAndEditorWritesDoNotAddHistory() async throws {
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository)
        let item = ClipItem(content: "Original", sourceApp: "MCP", metadata: ClipMetadata(
            title: "Draft", createdAt: Date(), source: .mcp
        ))
        _ = try await service.registerMCP([item], record: receipt())
        await service.recopyFromHistory(item)
        await service.writeToClipboardOnly("Edited")
        await service.flushPendingSaves()

        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.id), [item.id])
        XCTAssertEqual(history.first?.metadata, item.metadata)
        let saved = try await repository.loadAll()
        XCTAssertEqual(saved.map(\.id), [item.id])

        let derived = await service.addEditorItems(["Line one", "Line two"])
        await service.flushPendingSaves()
        XCTAssertEqual(derived.count, 2)
        XCTAssertTrue(derived.allSatisfy { $0.metadata?.source == .editor })
        let allSaved = try await repository.loadAll()
        XCTAssertEqual(Set(allSaved.map(\.content)), ["Original", "Line one", "Line two"])
    }
}
