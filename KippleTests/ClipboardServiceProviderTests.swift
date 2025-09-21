import XCTest
@testable import Kipple

@MainActor
final class ClipboardServiceProviderTests: XCTestCase {
    func testResolveReturnsExpectedService() {
        let service = ClipboardServiceProvider.resolve()
        if #available(macOS 13.0, *) {
            XCTAssertTrue(service is ModernClipboardServiceAdapter)
        } else {
            XCTAssertTrue(service === ClipboardService.shared)
        }
    }

    func testResolveIsDeterministic() {
        let first = ClipboardServiceProvider.resolve()
        let second = ClipboardServiceProvider.resolve()

        if #available(macOS 13.0, *) {
            XCTAssertTrue(first is ModernClipboardServiceAdapter)
            XCTAssertTrue(second is ModernClipboardServiceAdapter)
            XCTAssertTrue(first === second)
        } else {
            XCTAssertTrue(first === ClipboardService.shared)
            XCTAssertTrue(second === ClipboardService.shared)
        }
    }
}
