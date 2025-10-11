import XCTest
@testable import Kipple

@MainActor
final class ActionKeyObserverTests: XCTestCase {
    func testSimulateModifierChangeUpdatesPublishedValue() {
#if DEBUG
        let observer = ActionKeyObserver.shared
        observer.simulateModifierChange([])
        XCTAssertEqual(observer.modifiers.intersection(.deviceIndependentFlagsMask), [])

        observer.simulateModifierChange([.command, .shift])
        let current = observer.modifiers.intersection(.deviceIndependentFlagsMask)
        XCTAssertTrue(current.contains(.command))
        XCTAssertTrue(current.contains(.shift))
#else
        throw XCTSkip("DEBUGビルド専用APIのため、この構成ではスキップします。")
#endif
    }
}
