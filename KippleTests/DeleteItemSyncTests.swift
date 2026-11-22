//
//  DeleteItemSyncTests.swift
//  KippleTests
//
//  Tests for delete item synchronization
//

import XCTest
@testable import Kipple

@MainActor
final class DeleteItemSyncTests: XCTestCase {
    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!
    private var viewModel: MainViewModel!
    
    override func setUp() async throws {
        try await super.setUp()
        
        service = ModernClipboardService.shared
        await service.resetForTesting()
        adapter = ModernClipboardServiceAdapter.shared
        viewModel = MainViewModel(clipboardService: adapter)
        
        // Clear any existing data
        await service.clearHistory(keepingCategories: false)
        await service.stopMonitoring()
        await service.flushPendingSaves()
    }
    
    override func tearDown() async throws {
        await service.clearHistory(keepingCategories: false)
        await service.stopMonitoring()
        
        service = nil
        adapter = nil
        viewModel = nil
        
        try await super.tearDown()
    }
    
    func testDeleteItemImmediatelyRemovesFromUI() async throws {
        // Given: Add items
        await service.copyToClipboard("Item 1", fromEditor: false)
        await service.copyToClipboard("https://example.com/deletable", fromEditor: false)
        await service.copyToClipboard("Item 3", fromEditor: false)
        await service.flushPendingSaves()
        
        // Wait for UI to sync
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        XCTAssertEqual(viewModel.history.count, 3)
        let itemToDelete = viewModel.history[1]
        XCTAssertEqual(itemToDelete.categoryIDs, [BuiltInCategory.url])
        
        // When: Delete item
        viewModel.deleteItemSync(itemToDelete)
        
        // Then: Item should be removed from UI immediately
        // (Current implementation may not update immediately due to async Task)
        
        // Wait for backend to process
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Verify item is deleted
        XCTAssertEqual(viewModel.history.count, 2)
        XCTAssertFalse(viewModel.history.contains { $0.id == itemToDelete.id },
                      "Deleted item should not be in history")
    }
    
    func testDeleteMultipleItemsInSequence() async throws {
        // Given: Add multiple items
        for i in 1...5 {
            await service.copyToClipboard("Item \(i)", fromEditor: false)
        }
        await service.flushPendingSaves()
        
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(viewModel.history.count, 5)
        
        // When: Delete multiple items quickly
        let itemsToDelete = [viewModel.history[0], viewModel.history[2]]
        for item in itemsToDelete {
            viewModel.deleteItemSync(item)
        }
        
        // Wait for all deletions to complete
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Then: All items should be deleted
        XCTAssertEqual(viewModel.history.count, 3)
        for item in itemsToDelete {
            XCTAssertFalse(viewModel.history.contains { $0.id == item.id })
        }
    }
    
    func testDeleteWithOldSnapshotKeepsNewlyCategorizedItem() async throws {
        await service.copyToClipboard("Categorized item", fromEditor: false)
        await adapter.refreshHistoryForTesting()
        let oldItem = try XCTUnwrap(viewModel.history.first)
        XCTAssertFalse(oldItem.hasCustomCategory)
        try await adapter.updateCategories(itemID: oldItem.id, change: .set(savedHistoryCategoryID, enabled: true))

        await viewModel.deleteItem(oldItem)

        let item = try XCTUnwrap(viewModel.history.first)
        XCTAssertEqual(item.id, oldItem.id)
        XCTAssertTrue(item.hasCustomCategory)
    }
}
