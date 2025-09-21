import XCTest
@testable import Kipple

@MainActor
final class HotkeyManagerProviderTests: XCTestCase {
    func testResolveReturnsSimplifiedHotkeyManager() {
        let manager = HotkeyManagerProvider.resolve()
        XCTAssertTrue(manager is SimplifiedHotkeyManager, "HotkeyManagerProvider should return SimplifiedHotkeyManager")
    }

    func testResolveSyncReturnsSimplifiedHotkeyManager() {
        let manager = HotkeyManagerProvider.resolveSync()
        XCTAssertTrue(manager is SimplifiedHotkeyManager, "HotkeyManagerProvider.resolveSync should return SimplifiedHotkeyManager")
    }
}
