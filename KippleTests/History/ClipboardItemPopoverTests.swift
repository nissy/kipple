@testable import Kipple
import XCTest

final class ClipboardItemPopoverTests: XCTestCase {
    func testResolveItemFallsBackToInitialWhenNotFound() {
        let item = ClipItem(content: "initial")
        let resolved = ClipboardItemPopover.resolveItem(
            initialItem: item,
            itemID: item.id,
            history: []
        )
        XCTAssertEqual(resolved.id, item.id)
        XCTAssertEqual(resolved.content, "initial")
    }

    func testResolveItemPrefersLatestHistoryInstance() {
        let identifier = UUID()
        let initial = makeClipItem(id: identifier, content: "initial")
        let updated = makeClipItem(id: identifier, content: "updated")

        let resolved = ClipboardItemPopover.resolveItem(
            initialItem: initial,
            itemID: identifier,
            history: [updated]
        )

        XCTAssertEqual(resolved.id, identifier)
        XCTAssertEqual(resolved.content, "updated")
    }

    func testMakePreviewTextTruncatesToMaxLength() {
        let longContent = String(repeating: "A", count: 600)
        let item = ClipItem(content: longContent)
        let preview = ClipboardItemPopover.makePreviewText(for: item)

        XCTAssertEqual(preview.count, 500)
        XCTAssertTrue(preview.allSatisfy { $0 == "A" })
    }

    func testMakePreviewTextHandlesEmptyContent() {
        let item = ClipItem(content: "")
        XCTAssertEqual(ClipboardItemPopover.makePreviewText(for: item), "")
    }

    func testMakePreviewTextKeepsNewlineOnlyContent() {
        let item = ClipItem(content: "\n\n")
        XCTAssertEqual(ClipboardItemPopover.makePreviewText(for: item), "\n\n")
    }

    private func makeClipItem(id: UUID, content: String) -> ClipItem {
        ClipItem(
            id: id,
            content: content,
            timestamp: Date(),
            isPinned: false,
            kind: .text,
            sourceApp: nil,
            windowTitle: nil,
            bundleIdentifier: nil,
            processID: nil,
            isFromEditor: nil
        )
    }
}
