import XCTest
@testable import Kipple

final class ClipItemEqualityTests: XCTestCase {

    func testEqualityWithDifferentContent() {
        // Given: Two items with different content
        let item1 = ClipItem(content: "Content 1")
        let item2 = ClipItem(content: "Content 2")

        // Then: They should NOT be equal
        XCTAssertNotEqual(item1, item2)
    }

    func testEqualityWithCategoryChange() {
        // Given: Same item
        let item1 = ClipItem(content: "Test")

        // When: Create a copy and change category
        var item2 = item1
        item2.setCategory(savedHistoryCategoryID, enabled: true)

        // Then: They should NOT be equal due to different category
        XCTAssertNotEqual(item1, item2)
    }

    func testEqualityWithMetadataChange() {
        // Given: Same item with different metadata
        let item1 = ClipItem(
            content: "Test",
            sourceApp: "App1",
            windowTitle: "Window1"
        )

        let item2 = ClipItem(
            content: item1.content,
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
            ClipItem(content: "Item 1"),
            ClipItem(content: "Item 2"),
            ClipItem(content: "Item 3", userCategoryId: savedHistoryCategoryID)
        ]

        // When: Add a category state (create modified item)
        var modifiedFirst = originalItems[0]
        modifiedFirst.setCategory(savedHistoryCategoryID, enabled: true)  // Changed
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
            ClipItem(content: "Original")
        ]

        // When: Update content (create modified item - note: content is immutable)
        // Since content is immutable, we create a new item
        let modifiedItems = [
            ClipItem(
                content: "Updated"
            )
        ]

        // Then: Arrays should not be equal
        XCTAssertNotEqual(modifiedItems, originalItems)
    }
}
