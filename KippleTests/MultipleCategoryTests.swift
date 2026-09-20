import AppKit
import SwiftData
import XCTest
@testable import Kipple

final class MultipleCategoryTests: XCTestCase, @unchecked Sendable {
    func testAutomaticCategoriesCombineWithManualCategories() {
        let custom = UUID()
        var item = ClipItem(content: "https://example.com", userCategoryId: custom,
                            metadata: ClipMetadata(source: .ocr))
        XCTAssertEqual(item.categoryIDs, [custom, BuiltInCategory.url, BuiltInCategory.ocr])
        item.setCategory(BuiltInCategory.ai, enabled: true)
        XCTAssertTrue(item.categoryIDs.contains(BuiltInCategory.ai))
        XCTAssertEqual(item.metadata?.sources, [.ocr], "Manual AI assignment must not fabricate MCP provenance")
    }

    func testLegacyNoneAndLegacyMetadataRemainReadable() throws {
        let oldData = Data("{\"source\":\"mcp\",\"title\":\"Legacy\"}".utf8)
        let metadata = try JSONDecoder().decode(ClipMetadata.self, from: oldData)
        var item = ClipItem(content: "https://example.com", userCategoryId: BuiltInCategory.none, metadata: metadata)
        XCTAssertTrue(item.categoryIDs.isEmpty)
        item.setCategory(BuiltInCategory.ai, enabled: true)
        XCTAssertEqual(item.categoryIDs, [BuiltInCategory.ai])
        XCTAssertEqual(item.title, "Legacy")
        XCTAssertEqual(item.metadata?.sources, [.mcp])
    }

    func testRemovingAutomaticCategorySurvivesCodingAndDuplicateImport() throws {
        var item = ClipItem(content: "https://example.com", metadata: ClipMetadata(source: .ocr))
        item.setCategory(BuiltInCategory.url, enabled: false)
        item.setCategory(BuiltInCategory.ocr, enabled: false)
        let decoded = try JSONDecoder().decode(ClipItem.self, from: JSONEncoder().encode(item))
        var imported = ClipItem(content: item.content, metadata: ClipMetadata(source: .mcp))
        imported.metadata = imported.metadata?.inheritingDetails(from: decoded.metadata)
        XCTAssertEqual(imported.categoryIDs, [BuiltInCategory.ai])
        XCTAssertEqual(imported.metadata?.sources, [.mcp, .ocr])
        imported.setCategory(BuiltInCategory.url, enabled: true)
        XCTAssertEqual(imported.categoryIDs, [BuiltInCategory.url, BuiltInCategory.ai])
    }

    func testMatchAllAnyAndUncategorized() {
        let item = ClipItem(content: "https://example.com", metadata: ClipMetadata(source: .ocr))
        var filter = CategoryFilter(ids: [BuiltInCategory.url, BuiltInCategory.ocr])
        XCTAssertTrue(filter.includes(item))
        filter.toggle(BuiltInCategory.ai)
        XCTAssertFalse(filter.includes(item))
        filter.match = .any
        XCTAssertTrue(filter.includes(item))
        filter.toggle(BuiltInCategory.none)
        XCTAssertEqual(filter.ids, [BuiltInCategory.none])
        XCTAssertFalse(filter.includes(item))
        XCTAssertTrue(filter.includes(ClipItem(content: "memo")))
        filter.toggle(BuiltInCategory.url)
        XCTAssertEqual(filter.ids, [BuiltInCategory.url])
    }

    func testEditsSurviveRecopyMCPAndRestartWithoutReplacingOtherDetails() async throws {
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository)
        let custom = UUID()
        await service.copyToClipboard("https://example.com", fromEditor: false, source: .ocr) { true }
        let initialHistory = await service.getHistory()
        let original = try XCTUnwrap(initialHistory.first)
        try await service.setCategory(itemID: original.id, categoryID: BuiltInCategory.ocr, enabled: false)
        try await service.setCategory(itemID: original.id, categoryID: custom, enabled: true)
        await service.recopyFromHistory(original) // Deliberately stale UI snapshot.
        let imported = ClipItem(content: original.content, metadata: ClipMetadata(title: "MCP title", source: .mcp))
        let requestID = UUID()
        let record = MCPStoredReceipt(key: requestID.uuidString, digest: Data([1]), receivedAt: Date(),
                                      result: MCPReceipt(requestId: requestID, status: "clipboard_unknown"))
        _ = try await service.registerMCP([imported], record: record)
        await service.flushPendingSaves()
        let restarted = ModernClipboardService(testRepository: repository)
        await restarted.loadHistoryFromRepository()
        let history = await restarted.getHistory()
        let saved = try XCTUnwrap(history.first)
        XCTAssertEqual(saved.id, original.id)
        XCTAssertEqual(saved.categoryIDs, [custom, BuiltInCategory.url, BuiltInCategory.ai])
        XCTAssertEqual(saved.title, "MCP title")
        XCTAssertEqual(saved.metadata?.sources, [.ocr, .mcp])
    }

    func testCategoryDeletionPreservesOtherCategoriesAndClipboard() async throws {
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository)
        let removed = UUID()
        let retained = UUID()
        await service.copyToClipboard("https://example.com", fromEditor: false)
        let initial = await service.getHistory()
        let item = try XCTUnwrap(initial.first)
        try await service.setCategory(itemID: item.id, categoryID: removed, enabled: true)
        try await service.setCategory(itemID: item.id, categoryID: retained, enabled: true)
        let before = await MainActor.run { NSPasteboard.general.changeCount }
        try await service.removeCategoryDefinition(removed)
        let saved = try await repository.loadAll()
        XCTAssertEqual(saved.first?.categoryIDs, [retained, BuiltInCategory.url])
        XCTAssertEqual(saved.first?.id, item.id)
        XCTAssertEqual(saved.first?.timestamp, item.timestamp)
        let after = await MainActor.run { NSPasteboard.general.changeCount }
        XCTAssertEqual(before, after)
    }

    func testConcurrentCategoryEditsAreMerged() async throws {
        let service = ModernClipboardService(testRepository: try SwiftDataRepository.make(inMemory: true))
        await service.copyToClipboard("memo", fromEditor: false)
        let history = await service.getHistory()
        let item = try XCTUnwrap(history.first)
        let first = UUID()
        let second = UUID()
        async let firstEdit: Void = service.setCategory(itemID: item.id, categoryID: first, enabled: true)
        async let secondEdit: Void = service.setCategory(itemID: item.id, categoryID: second, enabled: true)
        _ = try await (firstEdit, secondEdit)
        let updated = await service.getHistory()
        XCTAssertEqual(updated.first?.categoryIDs, [first, second])
    }

    func testFailedPersistenceKeepsCategoryStateUnchanged() async throws {
        let custom = UUID()
        let item = ClipItem(content: "memo", userCategoryId: custom)
        let service = ModernClipboardService(testRepository: RejectingCategoryRepository(item: item))
        await service.loadHistoryFromRepository()
        do {
            try await service.setCategory(itemID: item.id, categoryID: BuiltInCategory.ai, enabled: true)
            XCTFail("A failed save must be reported")
        } catch { XCTAssertEqual(error as? MCPFailure, .persistence) }
        do {
            try await service.removeCategoryDefinition(custom)
            XCTFail("A failed deletion must be reported")
        } catch { XCTAssertEqual(error as? MCPFailure, .persistence) }
        let history = await service.getHistory()
        XCTAssertEqual(history, [item])
    }

    @MainActor
    func testEditingRowRemainsVisibleUntilPopoverCloses() {
        let clipboard = MockClipboardService()
        var item = ClipItem(content: "https://example.com", isPinned: true)
        clipboard.history = [item, ClipItem(content: "https://second.example.com")]
        let model = MainViewModel(clipboardService: clipboard)
        model.categoryFilter.ids = [BuiltInCategory.url]
        model.showOnlyPinned = true
        model.searchText = "example.com"
        model.categoryEditingItemID = item.id
        item.setCategory(BuiltInCategory.url, enabled: false)
        clipboard.history[0] = item
        model.updateFilteredItems(clipboard.history)
        XCTAssertEqual(model.filteredHistory.map(\.id), [item.id])
        model.categoryEditingItemID = nil
        XCTAssertTrue(model.filteredHistory.isEmpty)
    }

    @MainActor
    func testLegacySwiftDataMetadataCanBeEditedAndReopened() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([ClipItemModel.self])
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("history.store"))
        let custom = UUID()
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let legacy = ClipItemModel(content: "https://example.com", userCategoryId: custom)
        legacy.metadataData = Data("{\"source\":\"mcp\",\"title\":\"Old title\"}".utf8)
        context.insert(legacy)
        try context.save()
        let repository = try SwiftDataRepository.make(container: container)
        let loaded = try await repository.loadAll()
        var item = try XCTUnwrap(loaded.first)
        XCTAssertEqual(item.categoryIDs, [custom, BuiltInCategory.url, BuiltInCategory.ai])
        item.setCategory(BuiltInCategory.ai, enabled: false)
        try await repository.save([item])
        let reopened = try ModelContainer(for: schema, configurations: [config])
        let reopenedRepository = try SwiftDataRepository.make(container: reopened)
        let saved = try await reopenedRepository.loadAll()
        XCTAssertEqual(saved.first?.categoryIDs, [custom, BuiltInCategory.url])
        XCTAssertEqual(saved.first?.title, "Old title")
        XCTAssertEqual(saved.first?.metadata?.sources, [.mcp])
    }
}

private actor RejectingCategoryRepository: ClipboardRepositoryProtocol {
    let item: ClipItem
    init(item: ClipItem) { self.item = item }
    func load(limit: Int) async throws -> [ClipItem] { [item] }
    func loadAll() async throws -> [ClipItem] { [item] }
    func loadPinned() async throws -> [ClipItem] { [] }
    func save(_ items: [ClipItem]) async throws { throw MCPFailure.persistence }
    func replaceAll(with items: [ClipItem]) async throws { throw MCPFailure.persistence }
    func delete(_ item: ClipItem) async throws { throw MCPFailure.persistence }
    func clear() async throws { throw MCPFailure.persistence }
    func clear(keepPinned: Bool) async throws { throw MCPFailure.persistence }
    func applyChanges(inserted: [ClipItem], updated: [ClipItem], removed: [UUID]) async throws {
        throw MCPFailure.persistence
    }
}
