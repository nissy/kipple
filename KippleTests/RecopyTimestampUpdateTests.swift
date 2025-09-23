//
//  RecopyTimestampUpdateTests.swift
//  KippleTests
//
//  Tests for timestamp update when recopying from history
//

import XCTest
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class RecopyTimestampUpdateTests: XCTestCase {
    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!
    private var viewModel: MainViewModel!

    override func setUp() async throws {
        try await super.setUp()

        service = ModernClipboardService.shared
        await service.resetForTesting()
        adapter = ModernClipboardServiceAdapter.shared
        viewModel = MainViewModel(clipboardService: adapter)

        await service.resetForTesting()
        await adapter.clearHistory(keepPinned: false)
    }

    override func tearDown() async throws {
        // Clean up
        await service.resetForTesting()
        await adapter.clearHistory(keepPinned: false)

        service = nil
        adapter = nil
        viewModel = nil

        try await super.tearDown()
    }

    // MARK: - Timestamp Update Tests

    func testRecopyFromHistoryUpdatesTimestamp() async throws {
        // Given: Item with old timestamp
        let oldDate = Date().addingTimeInterval(-3600) // 1 hour ago
        var oldItem = ClipItem(
            content: "Old Content",
            sourceApp: "Safari"
        )
        oldItem.timestamp = oldDate

        await service.recopyFromHistory(oldItem)
        await service.flushPendingSaves()

        // When: Recopy the item
        let beforeRecopy = Date()
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        viewModel.selectHistoryItem(oldItem)
        await service.flushPendingSaves()

        let afterRecopy = Date()

        // Then: Timestamp should be updated
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].content, "Old Content")

        let newTimestamp = history[0].timestamp
        XCTAssertNotEqual(newTimestamp, oldDate, "Timestamp should be updated")
        XCTAssertTrue(newTimestamp >= beforeRecopy, "New timestamp should be recent")
        XCTAssertTrue(newTimestamp <= afterRecopy, "New timestamp should be within test window")
    }

    func testMultipleRecopiesUpdateTimestamps() async throws {
        // Given: Multiple items with different timestamps
        let items = [
            ("First", -7200),  // 2 hours ago
            ("Second", -3600), // 1 hour ago
            ("Third", -1800)   // 30 minutes ago
        ]

        for (content, timeOffset) in items {
            var item = ClipItem(content: content)
            item.timestamp = Date().addingTimeInterval(TimeInterval(timeOffset))
            await service.recopyFromHistory(item)
        }
        await service.flushPendingSaves()

        // When: Recopy the oldest item
        let history = await service.getHistory()
        let firstItem = history.first { $0.content == "First" }!
        let oldTimestamp = firstItem.timestamp

        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        viewModel.selectHistoryItem(firstItem)
        await service.flushPendingSaves()

        // Then: First item should be at top with new timestamp
        let updatedHistory = await service.getHistory()
        XCTAssertEqual(updatedHistory[0].content, "First")
        XCTAssertNotEqual(updatedHistory[0].timestamp, oldTimestamp)
        XCTAssertTrue(updatedHistory[0].timestamp > oldTimestamp)
    }

    func testTimestampPersistenceAfterRecopy() async throws {
        // Given: Item with old timestamp
        let repository = try await SwiftDataRepository(inMemory: true)
        let oldItem = ClipItem(
            content: "Persistent Content",
            sourceApp: "Xcode"
        )
        // Save with old timestamp
        var itemToSave = oldItem
        itemToSave.timestamp = Date().addingTimeInterval(-86400) // 1 day ago
        try await repository.save([itemToSave])

        // Load and recopy
        let loadedItems = try await repository.load(limit: 100)
        XCTAssertEqual(loadedItems.count, 1)

        let beforeRecopy = Date()
        await service.recopyFromHistory(loadedItems[0])
        await service.flushPendingSaves()

        // When: Save and reload from repository
        let currentHistory = await service.getHistory()
        try await repository.save(currentHistory)

        let reloadedItems = try await repository.load(limit: 100)

        // Then: Reloaded item should have updated timestamp
        XCTAssertEqual(reloadedItems.count, 1)
        XCTAssertEqual(reloadedItems[0].content, "Persistent Content")
        XCTAssertTrue(reloadedItems[0].timestamp >= beforeRecopy, "Timestamp should persist as recent")
    }

    func testTimestampOrderAfterRecopy() async throws {
        // Given: Multiple items with different ages
        for i in 1...5 {
            var item = ClipItem(content: "Item \(i)")
            item.timestamp = Date().addingTimeInterval(TimeInterval(-i * 3600)) // i hours ago
            await service.recopyFromHistory(item)
        }
        await service.flushPendingSaves()

        // When: Recopy item 5 (oldest)
        let history = await service.getHistory()
        let oldestItem = history.first { $0.content == "Item 5" }!

        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        viewModel.selectHistoryItem(oldestItem)
        await service.flushPendingSaves()

        // Then: Item 5 should be first with newest timestamp
        let updatedHistory = await service.getHistory()
        XCTAssertEqual(updatedHistory[0].content, "Item 5", "Oldest item should move to top")

        // Verify timestamp ordering
        for i in 0..<updatedHistory.count - 1 {
            XCTAssertTrue(
                updatedHistory[i].timestamp >= updatedHistory[i + 1].timestamp,
                "Items should be ordered by timestamp (newest first)"
            )
        }
    }

    func testTimestampUpdateWithPinnedItems() async throws {
        // Given: Mix of pinned and unpinned items with old timestamps
        var pinnedItem = ClipItem(content: "Pinned Old")
        pinnedItem.timestamp = Date().addingTimeInterval(-7200) // 2 hours ago
        pinnedItem.isPinned = true

        var unpinnedItem = ClipItem(content: "Unpinned Old")
        unpinnedItem.timestamp = Date().addingTimeInterval(-3600) // 1 hour ago

        await service.recopyFromHistory(pinnedItem)
        await service.recopyFromHistory(unpinnedItem)
        await service.flushPendingSaves()

        // When: Recopy pinned item
        let beforeRecopy = Date()
        viewModel.selectHistoryItem(pinnedItem)
        await service.flushPendingSaves()

        // Then: Pinned item should have updated timestamp and remain pinned
        let history = await service.getHistory()
        XCTAssertEqual(history[0].content, "Pinned Old")
        XCTAssertTrue(history[0].isPinned, "Should remain pinned")
        XCTAssertTrue(history[0].timestamp >= beforeRecopy, "Timestamp should be updated")
    }

    // MARK: - Edge Cases

    func testTimestampUpdateForEmptyContent() async throws {
        // Empty content usually gets filtered, but test if it doesn't
        var emptyItem = ClipItem(content: "")
        emptyItem.timestamp = Date().addingTimeInterval(-1000)

        await service.recopyFromHistory(emptyItem)
        await service.flushPendingSaves()

        let history = await service.getHistory()
        // Empty strings are typically filtered
        if !history.isEmpty && history[0].content.isEmpty {
            XCTAssertTrue(history[0].timestamp > Date().addingTimeInterval(-1000))
        }
    }

    func testRapidRecopyTimestamps() async throws {
        // Given: Single item
        var item = ClipItem(content: "Rapid Recopy")
        item.timestamp = Date().addingTimeInterval(-1000)
        await service.recopyFromHistory(item)
        await service.flushPendingSaves()

        var timestamps: [Date] = []

        // When: Rapidly recopy multiple times
        for _ in 1...5 {
            viewModel.selectHistoryItem(item)
            await service.flushPendingSaves()

            let history = await service.getHistory()
            timestamps.append(history[0].timestamp)

            try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        }

        // Then: Each recopy should have a newer or equal timestamp
        for i in 1..<timestamps.count {
            XCTAssertTrue(
                timestamps[i] >= timestamps[i - 1],
                "Later recopies should have newer or equal timestamps"
            )
        }
    }
}
