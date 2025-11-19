@testable import Kipple
import XCTest

final class HistoryItemViewDisplayContentTests: XCTestCase {
    func testMakeDisplayContentStopsAtNewline() {
        let result = HistoryItemView.makeDisplayContent(from: "first line\nsecond line")
        XCTAssertEqual(result, "first line…")
    }

    func testMakeDisplayContentReturnsOriginalWhenSingleLine() {
        let source = "single line"
        XCTAssertEqual(HistoryItemView.makeDisplayContent(from: source), source)
    }
}
