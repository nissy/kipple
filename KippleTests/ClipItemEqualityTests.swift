import XCTest
@testable import Kipple

final class ClipItemEqualityTests: XCTestCase {

    func testEqualityWithDifferentContent() {
        // Given: Two items with different content
        let item1 = ClipItem(content: "Content 1", isPinned: false)
        let item2 = ClipItem(content: "Content 2", isPinned: false)

        // Then: They should NOT be equal
        XCTAssertNotEqual(item1, item2)
    }

    func testEqualityWithPinStateChange() {
        // Given: Same item
        let item1 = ClipItem(content: "Test", isPinned: false)

        // When: Create a copy and change pin state
        var item2 = item1
        item2.isPinned = true

        // Then: They should NOT be equal due to different pin state
        XCTAssertNotEqual(item1, item2)
    }

    func testEqualityWithMetadataChange() {
        // Given: Same item with different metadata
        let item1 = ClipItem(
            content: "Test",
            isPinned: false,
            sourceApp: "App1",
            windowTitle: "Window1"
        )

        let item2 = ClipItem(
            content: item1.content,
            isPinned: item1.isPinned,
            sourceApp: "App2",
            windowTitle: "Window2"
        )

        // Then: They should NOT be equal
        XCTAssertNotEqual(item1, item2)
    }

    func testEqualityWithAllFieldsMatching() {
        // Given: An item
        let item1 = ClipItem(
            content: "Test Content",
            isPinned: true,
            sourceApp: "TestApp",
            windowTitle: "TestWindow",
            bundleIdentifier: "com.test.app",
            processID: 1234,
            isFromEditor: false
        )

        // Create item2 as exact copy
        let item2 = item1

        // Then: They should be equal
        XCTAssertEqual(item1, item2)
    }

    func testArrayComparisonDetectsChanges() {
        // Given: Array of items
        let originalItems = [
            ClipItem(content: "Item 1", isPinned: false),
            ClipItem(content: "Item 2", isPinned: false),
            ClipItem(content: "Item 3", isPinned: true)
        ]

        // When: Toggle pin state (create modified item)
        var modifiedFirst = originalItems[0]
        modifiedFirst.isPinned = true  // Changed
        let modifiedItems = [
            modifiedFirst,
            originalItems[1],
            originalItems[2]
        ]

        // Then: Arrays should not be equal
        XCTAssertNotEqual(modifiedItems, originalItems)
    }

    func testArrayComparisonWithContentUpdate() {
        // Given: Array of items
        let originalItems = [
            ClipItem(content: "Original", isPinned: false)
        ]

        // When: Update content (create modified item - note: content is immutable)
        // Since content is immutable, we create a new item
        let modifiedItems = [
            ClipItem(
                content: "Updated",  // Changed
                isPinned: originalItems[0].isPinned
            )
        ]

        // Then: Arrays should not be equal
        XCTAssertNotEqual(modifiedItems, originalItems)
    }
}
