import XCTest
@testable import Kipple

@MainActor
final class ClipboardServiceProviderTests: XCTestCase {
    func testResolveReturnsModernServiceAdapter() {
        let service = ClipboardServiceProvider.resolve()
        XCTAssertTrue(service is ModernClipboardServiceAdapter,
                     "Provider should return ModernClipboardServiceAdapter")
    }

    func testResolveReturnsSameInstance() {
        let first = ClipboardServiceProvider.resolve()
        let second = ClipboardServiceProvider.resolve()
        XCTAssertTrue(first === second,
                     "Provider should return the same singleton instance")
    }
}
