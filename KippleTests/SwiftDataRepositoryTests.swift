import XCTest
import SwiftData
@testable import Kipple

final class SwiftDataRepositoryTests: XCTestCase, @unchecked Sendable {
    private var repository: SwiftDataRepository!
    private var modelContainer: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory container for testing
        let schema = Schema([ClipItemModel.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        repository = try SwiftDataRepository.make(container: modelContainer)
    }

    override func tearDown() async throws {
        repository = nil
        modelContainer = nil
        try await super.tearDown()
    }

    func testSaveAndLoad() async throws {
        // Given
        let items = [
            ClipItem(content: "Test 1"),
            ClipItem(content: "Test 2", userCategoryId: savedHistoryCategoryID),
            ClipItem(content: "Test 3")
        ]

        // When
        try await repository.save(items)
        let loaded = try await repository.load(limit: 10)

        // Then
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.first?.content, "Test 3") // Most recent first
        XCTAssertEqual(loaded[1].content, "Test 2")
        XCTAssertEqual(loaded[2].content, "Test 1")
    }

    func testLoadWithLimit() async throws {
        // Given
        let items = (1...10).map { ClipItem(content: "Item \($0)") }
        try await repository.save(items)

        // When
        let loaded = try await repository.load(limit: 5)

        // Then
        XCTAssertEqual(loaded.count, 5)
        XCTAssertEqual(loaded.first?.content, "Item 10") // Most recent
        XCTAssertEqual(loaded.last?.content, "Item 6")
    }

    func testStartupPreviewsTrackFullRowsAcrossUpdatesAndDeletion() async throws {
        let original = ClipItem(content: String(repeating: "あ", count: 700) + "全文の末尾", userCategoryId: savedHistoryCategoryID)
        let recent = ClipItem(content: "newest")
        try await repository.save([original, recent])

        let firstPage = try await repository.loadStartupPreviews(limit: 1)
        XCTAssertEqual(firstPage.map(\.id), [recent.id])
        let rows = try await repository.loadStartupPreviews(limit: 2)
        let preview = try XCTUnwrap(rows.last)
        XCTAssertEqual(preview.id, original.id)
        XCTAssertEqual(preview.text, String(repeating: "あ", count: 512) + "…")
        XCTAssertEqual(preview.categoryIDs, [savedHistoryCategoryID])
        let full = try await repository.load(ids: [preview.id])
        XCTAssertEqual(full.first?.content, original.content)
        XCTAssertTrue(full[0].matchesSearch("全文の末尾"))

        let revised = original.replacingContent(with: "更新後\n続き")
        try await repository.update(revised)
        let revisedPreviews = try await repository.loadStartupPreviews(limit: 10)
        XCTAssertEqual(revisedPreviews.first { $0.id == original.id }?.text, "更新後…")

        try await repository.delete(revised)
        let remaining = try await repository.loadStartupPreviews(limit: 10)
        XCTAssertEqual(remaining.map(\.id), [recent.id])
        try await repository.clear()
        let cleared = try await repository.loadStartupPreviews(limit: 10)
        XCTAssertTrue(cleared.isEmpty)
        let context = ModelContext(modelContainer)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StoredHistoryRowPreview>()), 0)
    }

    func testRowsWithEqualTimestampsKeepTheirOrderWhenFullHistoryArrives() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString, directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([ClipItemModel.self])
        let configuration = ModelConfiguration(
            schema: schema, url: directory.appending(path: "history.sqlite"), cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let repository = try SwiftDataRepository.make(container: container)
        let context = ModelContext(container)
        let sharedTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
        for index in (0..<12).reversed() {
            let model = ClipItemModel(content: "Identical timestamp \(index)", timestamp: sharedTimestamp)
            context.insert(model)
        }
        try context.save()
        try await repository.backfillHistoryPreviews()

        let previews = try await repository.loadStartupPreviews(limit: 5)
        let service = ModernClipboardService(testRepository: repository)
        await service.loadHistoryFromRepository()
        let full = await service.getHistory()

        XCTAssertEqual(full.count, 12)
        XCTAssertEqual(previews.count, 5)
        XCTAssertEqual(full.prefix(5).map(\.id), previews.map(\.id))
    }

    func testLoadAll() async throws {
        // Given
        let items = (1...20).map { ClipItem(content: "Item \($0)") }
        try await repository.save(items)

        // When
        let loaded = try await repository.loadAll()

        // Then
        XCTAssertEqual(loaded.count, 20)
    }

    func testDelete() async throws {
        // Given
        let items = [
            ClipItem(content: "Keep 1"),
            ClipItem(content: "Delete Me"),
            ClipItem(content: "Keep 2")
        ]
        try await repository.save(items)

        // When
        let deleteItem = items[1]
        try await repository.delete(deleteItem)
        let loaded = try await repository.loadAll()

        // Then
        XCTAssertEqual(loaded.count, 2)
        XCTAssertFalse(loaded.contains { $0.content == "Delete Me" })
        XCTAssertTrue(loaded.contains { $0.content == "Keep 1" })
        XCTAssertTrue(loaded.contains { $0.content == "Keep 2" })
    }

    func testClearAll() async throws {
        // Given
        let items = (1...5).map { ClipItem(content: "Item \($0)") }
        try await repository.save(items)

        // When
        try await repository.clear()
        let loaded = try await repository.loadAll()

        // Then
        XCTAssertEqual(loaded.count, 0)
    }

    func testClearKeepingCategories() async throws {
        // Given
        let items = [
            ClipItem(content: "Uncategorized 1"),
            ClipItem(content: "Categorized 1", userCategoryId: savedHistoryCategoryID),
            ClipItem(content: "Uncategorized 2"),
            ClipItem(content: "Categorized 2", userCategoryId: savedHistoryCategoryID)
        ]
        try await repository.save(items)

        // When
        try await repository.replaceAll(with: repository.loadCategorized())
        let loaded = try await repository.loadAll()

        // Then
        XCTAssertEqual(loaded.count, 2)
        XCTAssertTrue(loaded.allSatisfy { $0.hasCustomCategory })
        XCTAssertTrue(loaded.contains { $0.content == "Categorized 1" })
        XCTAssertTrue(loaded.contains { $0.content == "Categorized 2" })
    }

    func testCountItems() async throws {
        // Given
        let items = (1...7).map { ClipItem(content: "Item \($0)") }
        try await repository.save(items)

        // When
        let count = try await repository.countItems()

        // Then
        XCTAssertEqual(count, 7)
    }

    func testConcurrentAccess() async throws {
        // Test thread safety with concurrent operations
        let repository = self.repository!
        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask {
                    let item = ClipItem(content: "Concurrent \(i)")
                    try? await repository.save([item])
                }
            }

            for _ in 1...5 {
                group.addTask {
                    _ = try? await repository.loadAll()
                }
            }
        }
    }

    // MARK: - Additional Comprehensive Tests

    func testUpdateExistingItem() async throws {
        // Given
        let originalItem = ClipItem(content: "Original")
        try await repository.save([originalItem])

        // When - Update the same item
        var updatedItem = originalItem
        updatedItem.setCategory(savedHistoryCategoryID, enabled: true)
        try await repository.update(updatedItem)
        let loaded = try await repository.loadAll()

        // Then
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, originalItem.id)
        XCTAssertTrue(loaded.first?.hasCustomCategory ?? false)
    }

    func testSaveDuplicateItems() async throws {
        // Given
        let item = ClipItem(content: "Duplicate Test")

        // When - Save the same item twice
        try await repository.save([item])
        try await repository.save([item]) // Try to save again
        let loaded = try await repository.loadAll()

        // Then - Should not create duplicates
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.content, "Duplicate Test")
    }

    func testLoadCategorizedItems() async throws {
        // Given
        let items = [
            ClipItem(content: "Uncategorized 1"),
            ClipItem(content: "Categorized 1", userCategoryId: savedHistoryCategoryID),
            ClipItem(content: "Uncategorized 2"),
            ClipItem(content: "Categorized 2", userCategoryId: savedHistoryCategoryID),
            ClipItem(content: "Categorized 3", userCategoryId: savedHistoryCategoryID)
        ]
        try await repository.save(items)

        // When
        let categorizedItems = try await repository.loadCategorized()

        // Then
        XCTAssertEqual(categorizedItems.count, 3)
        XCTAssertTrue(categorizedItems.allSatisfy { $0.hasCustomCategory })
    }

    func testItemWithSpecialCharacters() async throws {
        // Given - Items with special characters and emojis
        let specialItems = [
            ClipItem(content: "Test with 'quotes' and \"double quotes\""),
            ClipItem(content: "Unicode: 日本語テスト 🚀🎉"),
            ClipItem(content: "Line\nbreaks\nand\ttabs"),
            ClipItem(content: "Special chars: <>&@#$%^*()")
        ]

        // When
        try await repository.save(specialItems)
        let loaded = try await repository.loadAll()

        // Then
        XCTAssertEqual(loaded.count, 4)
        XCTAssertTrue(loaded.contains { $0.content.contains("日本語") })
        XCTAssertTrue(loaded.contains { $0.content.contains("🚀") })
    }

    func testLargeContentHandling() async throws {
        // Given - Very large content
        let largeContent = String(repeating: "Large content ", count: 10000)
        let item = ClipItem(content: largeContent)

        // When
        try await repository.save([item])
        let loaded = try await repository.loadAll()

        // Then
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.content.count, largeContent.count)
    }

    func testEmptyContentHandling() async throws {
        // Given
        let emptyItem = ClipItem(content: "")

        // When
        try await repository.save([emptyItem])
        let loaded = try await repository.loadAll()

        // Then
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.content, "")
    }

    func testPerformanceOfLargeDataset() async throws {
        // Given - Large number of items
        let items = (1...1000).map { index in
            ClipItem(content: "Performance test item \(index)", userCategoryId: index % 10 == 0 ? savedHistoryCategoryID : nil)
        }

        // When/Then - Measure performance
        let saveStart = Date()
        try await repository.save(items)
        let saveTime = Date().timeIntervalSince(saveStart)

        let loadStart = Date()
        let loaded = try await repository.loadAll()
        let loadTime = Date().timeIntervalSince(loadStart)

        XCTAssertEqual(loaded.count, 1000)
        XCTAssertLessThan(saveTime, 2.0, "Save should complete in less than 2 seconds")
        XCTAssertLessThan(loadTime, 1.0, "Load should complete in less than 1 second")
    }

    func testDataIntegrity() async throws {
        // Given
        let testDate = Date()
        let items = [
            ClipItem(
                id: UUID(),
                content: "Test Content",
                timestamp: testDate,
                kind: .text,
                sourceApp: "TestApp",
                windowTitle: "TestWindow",
                bundleIdentifier: "com.test.app",
                processID: 12345,
                isFromEditor: true,
                userCategoryId: savedHistoryCategoryID
            )
        ]

        // When
        try await repository.save(items)
        let loaded = try await repository.loadAll()

        // Then - Verify all properties are preserved
        let loadedItem = loaded.first
        XCTAssertNotNil(loadedItem)
        XCTAssertEqual(loadedItem?.content, "Test Content")
        XCTAssertEqual(loadedItem?.hasCustomCategory, true)
        XCTAssertEqual(loadedItem?.sourceApp, "TestApp")
        XCTAssertEqual(loadedItem?.windowTitle, "TestWindow")
        XCTAssertEqual(loadedItem?.bundleIdentifier, "com.test.app")
        XCTAssertEqual(loadedItem?.processID, 12345)
        XCTAssertEqual(loadedItem?.isFromEditor, true)
    }

    func testCleanupOldItems() async throws {
        // Given - Items with different timestamps
        let oldDate = Date().addingTimeInterval(-86400 * 30) // 30 days ago
        let recentDate = Date().addingTimeInterval(-3600) // 1 hour ago

        var oldItem = ClipItem(content: "Old item")
        oldItem.timestamp = oldDate

        var recentItem = ClipItem(content: "Recent item")
        recentItem.timestamp = recentDate

        try await repository.save([oldItem, recentItem])

        // When - Cleanup items older than 7 days
        let cutoffDate = Date().addingTimeInterval(-86400 * 7)
        try await repository.deleteItemsOlderThan(cutoffDate)
        let remaining = try await repository.loadAll()

        // Then
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.content, "Recent item")
    }
}
