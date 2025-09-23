//
//  ClearClipboardSyncTests.swift
//  KippleTests
//
//  Tests for Clear Clipboard button synchronization between UI and Service
//

import XCTest
import AppKit
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class ClearClipboardSyncTests: XCTestCase {
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
        await service.clearAllHistory()
        await service.stopMonitoring()
    }

    override func tearDown() async throws {
        // Clean up
        await service.clearAllHistory()
        await service.stopMonitoring()

        service = nil
        adapter = nil
        viewModel = nil

        try await super.tearDown()
    }

    // MARK: - Clear System Clipboard Tests

    func testClearSystemClipboardSynchronization() async throws {
        // Given: Some content in clipboard
        adapter.copyToClipboard("Test Content", fromEditor: false)

        // Wait for update
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        XCTAssertEqual(viewModel.currentClipboardContent, "Test Content")
        XCTAssertEqual(adapter.currentClipboardContent, "Test Content")

        // Verify system pasteboard has content
        let pasteboardContent = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(pasteboardContent, "Test Content")

        // When: Clear system clipboard through service
        adapter.clearSystemClipboard()

        // Wait for update
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Then: Everything should be synchronized
        XCTAssertNil(viewModel.currentClipboardContent, "ViewModel should show nil")
        XCTAssertNil(adapter.currentClipboardContent, "Adapter should show nil")

        let clearedContent = NSPasteboard.general.string(forType: .string)
        XCTAssertNil(clearedContent, "System pasteboard should be empty")
    }

    func testClearClipboardDoesNotAffectHistory() async throws {
        // Given: Items in history and current clipboard
        adapter.copyToClipboard("History Item 1", fromEditor: false)
        adapter.copyToClipboard("History Item 2", fromEditor: false)
        adapter.copyToClipboard("Current Content", fromEditor: false)

        // Wait for updates
        try await Task.sleep(nanoseconds: 500_000_000)

        let historyBefore = adapter.history
        XCTAssertEqual(historyBefore.count, 3)
        XCTAssertEqual(adapter.currentClipboardContent, "Current Content")

        // When: Clear system clipboard
        adapter.clearSystemClipboard()

        // Wait for update
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then: History should remain, only clipboard cleared
        let historyAfter = adapter.history
        XCTAssertEqual(historyAfter.count, 3, "History should not be affected")
        XCTAssertNil(adapter.currentClipboardContent, "Current clipboard should be nil")
    }

    func testRapidClearAndCopyOperations() async throws {
        // Given: Initial content
        adapter.copyToClipboard("Initial", fromEditor: false)
        try await Task.sleep(nanoseconds: 100_000_000)

        // When: Rapid clear and copy operations
        for i in 1...5 {
            adapter.clearSystemClipboard()
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

            XCTAssertNil(adapter.currentClipboardContent, "Should be nil after clear \(i)")

            adapter.copyToClipboard("Content \(i)", fromEditor: false)
            try await Task.sleep(nanoseconds: 50_000_000)

            XCTAssertEqual(adapter.currentClipboardContent, "Content \(i)")
        }

        // Then: Final state should be consistent
        XCTAssertEqual(adapter.currentClipboardContent, "Content 5")
        XCTAssertEqual(viewModel.currentClipboardContent, "Content 5")
    }

    func testClearClipboardWhileMonitoring() async throws {
        // Given: Monitoring is active
        await service.startMonitoring()

        adapter.copyToClipboard("Monitored Content", fromEditor: false)
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(adapter.currentClipboardContent, "Monitored Content")

        // When: Clear clipboard while monitoring
        adapter.clearSystemClipboard()
        try await Task.sleep(nanoseconds: 500_000_000)

        // Then: Should remain cleared even with monitoring
        XCTAssertNil(adapter.currentClipboardContent)
        XCTAssertNil(viewModel.currentClipboardContent)

        // Monitoring should not restore cleared content
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        XCTAssertNil(adapter.currentClipboardContent, "Should remain nil even after monitoring cycle")

        await service.stopMonitoring()
    }

    func testViewModelSyncAfterClear() async throws {
        // Given: Content in clipboard and viewModel synced
        adapter.copyToClipboard("Synced Content", fromEditor: false)
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(viewModel.currentClipboardContent, "Synced Content")

        // When: Clear through adapter
        adapter.clearSystemClipboard()

        // Then: ViewModel should update immediately or very quickly
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        XCTAssertNil(
            viewModel.currentClipboardContent,
            "ViewModel should sync with adapter after clear"
        )

        // Verify it stays nil (no reversion)
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        XCTAssertNil(
            viewModel.currentClipboardContent,
            "ViewModel should not revert to old value"
        )
    }

    // MARK: - Mock Service Test

    func testClearSystemClipboardWithMockService() async throws {
        // Given: Mock service
        let mockService = MockClipboardService()
        let testViewModel = MainViewModel(clipboardService: mockService)

        mockService.copyToClipboard("Mock Content", fromEditor: false)
        XCTAssertEqual(mockService.currentClipboardContent, "Mock Content")
        // MainViewModelは初期化時のcurrentClipboardContentしか持たない（Mockではバインディングなし）
        XCTAssertNil(testViewModel.currentClipboardContent)

        // When: Clear system clipboard
        mockService.clearSystemClipboard()

        // Then: Mock service should be cleared
        XCTAssertNil(mockService.currentClipboardContent)
        // MainViewModelは初期値のままでNil
        XCTAssertNil(testViewModel.currentClipboardContent)
    }
}
