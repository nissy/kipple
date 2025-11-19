@testable import Kipple
import XCTest

final class HistoryListViewHelperTests: XCTestCase {
    func testIsCurrentClipboardItemMatchesID() {
        let item = ClipItem(content: "match")
        XCTAssertTrue(HistoryListView.isCurrentClipboardItem(item, currentID: item.id))
    }

    func testIsCurrentClipboardItemReturnsFalseWhenIDDiffers() {
        let item = ClipItem(content: "diff")
        XCTAssertFalse(HistoryListView.isCurrentClipboardItem(item, currentID: UUID()))
    }

    func testIsCurrentClipboardItemReturnsFalseWhenIDMissing() {
        let item = ClipItem(content: "none")
        XCTAssertFalse(HistoryListView.isCurrentClipboardItem(item, currentID: nil))
    }
}
