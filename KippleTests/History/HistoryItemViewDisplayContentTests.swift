@testable import Kipple
import XCTest

@MainActor
final class HistoryItemViewDisplayContentTests: XCTestCase {
    func testMakeDisplayContentStopsAtNewline() {
        let result = HistoryRowPreview.displayText(from: "first line\nsecond line")
        XCTAssertEqual(result.text, "first line…")
        XCTAssertFalse(result.isLengthLimited)
    }

    func testMakeDisplayContentReturnsOriginalWhenSingleLine() {
        let source = "single line"
        let result = HistoryRowPreview.displayText(from: source)
        XCTAssertEqual(result.text, source)
        XCTAssertFalse(result.isLengthLimited)
    }

    func testPreviewStopsAtPlatformAndUnicodeLineBreaks() {
        for separator in ["\r\n", "\r", "\u{2028}", "\u{2029}"] {
            let content = "👩🏽‍💻 first" + separator + "second"
            let result = HistoryRowPreview.displayText(from: content)
            XCTAssertEqual(result.text, "👩🏽‍💻 first…")
            XCTAssertEqual(HistoryRowPreview.firstLine(from: content), result.text)
            XCTAssertFalse(result.isLengthLimited)
        }
    }

    func testLongPreviewKeepsCompleteCharactersAndIndicatesThereIsMoreAccessibleText() {
        let prefix = String(repeating: "👩🏽‍💻", count: 512)
        XCTAssertFalse(HistoryRowPreview.displayText(from: prefix).isLengthLimited)
        XCTAssertFalse(HistoryRowPreview.displayText(from: prefix + "\nnext line").isLengthLimited)

        let result = HistoryRowPreview.displayText(from: prefix + "full text continues\nnext line")
        XCTAssertEqual(result.text, prefix + "…")
        XCTAssertTrue(result.isLengthLimited)
    }
}
