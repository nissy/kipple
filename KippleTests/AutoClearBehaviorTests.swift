import XCTest
import AppKit
@testable import Kipple

/// Tests for auto-clear behavior to ensure it only clears clipboard, not history
@MainActor
final class AutoClearBehaviorTests: XCTestCase {

    // MARK: - Modern Implementation Tests

    func testModernAutoClearPreservesHistory() async {
        // Given: ModernClipboardServiceAdapter with some history
        let adapter = ModernClipboardServiceAdapter.shared
        let service = ModernClipboardService.shared
        await service.resetForTesting()

        // Add some items to history
        await service.copyToClipboard("Modern Item 1", fromEditor: false)
        await service.copyToClipboard("Modern Item 2", fromEditor: false)
        await service.copyToClipboard("Modern Item 3", fromEditor: false)

        // Wait for adapter to sync
        try? await Task.sleep(for: .milliseconds(600))

        // Store initial history
        let historyCountBefore = adapter.history.count

        // When: Trigger auto-clear directly
        adapter.performAutoClear()

        // Then: History should be preserved
        XCTAssertEqual(adapter.history.count, historyCountBefore,
                      "Modern auto-clear should preserve history")
        XCTAssertNil(adapter.currentClipboardContent,
                    "Current clipboard content should be cleared")
    }

    func testModernAutoClearOnlySystemClipboard() async {
        // Given: System clipboard with text and history
        let testContent = "Modern test content"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(testContent, forType: .string)

        let adapter = ModernClipboardServiceAdapter.shared

        // When: Perform auto-clear
        adapter.performAutoClear()

        // Then: System clipboard should be empty
        let clipboardContent = NSPasteboard.general.string(forType: .string)
        XCTAssertNil(clipboardContent,
                    "System clipboard should be cleared after auto-clear")
    }

    func testModernAutoClearWithPinnedItems() async {
        // Given: ModernClipboardService with pinned and regular items
        let adapter = ModernClipboardServiceAdapter.shared
        let service = ModernClipboardService.shared
        await service.resetForTesting()

        // Clear existing history
        await service.clearHistory(keepPinned: false)

        // Add items
        await service.copyToClipboard("Regular 1", fromEditor: false)
        await service.copyToClipboard("Pinned Item", fromEditor: false)
        await service.copyToClipboard("Regular 2", fromEditor: false)

        // Pin one item
        let history = await service.getHistory()
        if let pinnedItem = history.first(where: { $0.content == "Pinned Item" }) {
            _ = await service.togglePin(for: pinnedItem)
        }

        // Wait for sync
        try? await Task.sleep(for: .milliseconds(600))

        // Store counts before auto-clear
        let totalCountBefore = adapter.history.count
        let pinnedCountBefore = adapter.pinnedItems.count

        // When: Perform auto-clear
        adapter.performAutoClear()

        // Then: All history (including pinned) should be preserved
        XCTAssertEqual(adapter.history.count, totalCountBefore,
                      "Auto-clear should preserve all history items")
        XCTAssertEqual(adapter.pinnedItems.count, pinnedCountBefore,
                      "Auto-clear should preserve pinned items")
    }

    // MARK: - Timer Behavior Tests

    func testAutoClearTimerBehavior() async {
        // Given: ModernClipboardServiceAdapter
        let adapter = ModernClipboardServiceAdapter.shared
        let service = ModernClipboardService.shared
        await service.resetForTesting()

        // Add test data
        await service.copyToClipboard("Timer test content", fromEditor: false)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Clipboard content", forType: .string)

        // Wait for sync
        try? await Task.sleep(for: .milliseconds(600))

        let historyCountBefore = adapter.history.count

        // When: Start auto-clear timer with minimal time (simulated immediate trigger)
        adapter.autoClearRemainingTime = 0.1 // Almost immediate

        // Manually trigger what timer would do
        adapter.performAutoClear()
        adapter.stopAutoClearTimer()

        // Then: History preserved, clipboard cleared
        XCTAssertEqual(adapter.history.count, historyCountBefore,
                      "Timer-triggered auto-clear should preserve history")
        XCTAssertNil(NSPasteboard.general.string(forType: .string),
                    "Timer-triggered auto-clear should clear system clipboard")
    }

    // MARK: - Edge Cases

    func testAutoClearWithNonTextContent() {
        // Given: Clipboard with non-text content
        NSPasteboard.general.clearContents()
        // Don't set any text content

        let adapter = ModernClipboardServiceAdapter.shared

        // When: Try to auto-clear
        adapter.performAutoClear()

        // Then: Should handle gracefully (no crash, logged skip)
        XCTAssertTrue(true, "Auto-clear with non-text content should not crash")
    }
}
