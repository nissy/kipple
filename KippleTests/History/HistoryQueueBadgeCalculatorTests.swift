@testable import Kipple
import XCTest

final class HistoryQueueBadgeCalculatorTests: XCTestCase {
    func testSkipsProviderWhenPasteModeIsClipboard() {
        let item = ClipItem(content: "sample")
        var callCount = 0
        let value = HistoryQueueBadgeCalculator.queueBadgeValue(
            for: item,
            pasteMode: .clipboard
        ) { _ in
            callCount += 1
            return 1
        }

        XCTAssertNil(value)
        XCTAssertEqual(callCount, 0)
    }

    func testReturnsProviderValueWhenAvailable() {
        let item = ClipItem(content: "queue")
        let value = HistoryQueueBadgeCalculator.queueBadgeValue(
            for: item,
            pasteMode: .queueOnce
        ) { _ in 2 }

        XCTAssertEqual(value, 2)
    }

    func testFallsBackToZeroWhenProviderReturnsNil() {
        let item = ClipItem(content: "missing")
        let value = HistoryQueueBadgeCalculator.queueBadgeValue(
            for: item,
            pasteMode: .queueToggle
        ) { _ in nil }

        XCTAssertEqual(value, 0)
    }

    func testReturnsProviderNegativeValueUnchanged() {
        let item = ClipItem(content: "negative")
        let value = HistoryQueueBadgeCalculator.queueBadgeValue(
            for: item,
            pasteMode: .queueOnce
        ) { _ in -3 }

        XCTAssertEqual(value, -3)
    }
}
