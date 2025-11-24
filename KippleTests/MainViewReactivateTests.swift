// swiftlint:disable trailing_closure
import XCTest
@testable import Kipple

@MainActor
final class MainViewReactivateTests: XCTestCase {
    func testReactivateCalledWhenAlwaysOnTop() async throws {
        var reactivateCount = 0

        let view = MainView(
            onReactivatePreviousApp: { reactivateCount += 1 }
        )

        view.reactivatePreviousAppAfterCopy()

        XCTAssertEqual(reactivateCount, 1)
    }
}
// swiftlint:enable trailing_closure
