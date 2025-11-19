@testable import Kipple
import AppKit
import XCTest

@MainActor
final class HoverTrackingViewTests: XCTestCase {
    func testRefreshTrackingAreaDoesNotRecreateForSameBounds() {
        let view = TrackingOverlayView { _, _ in }
        view.frame = NSRect(x: 0, y: 0, width: 120, height: 32)

        view.refreshTrackingArea()
        let initialArea = view.trackingArea

        view.refreshTrackingArea()

        XCTAssertNotNil(initialArea)
        XCTAssertTrue(initialArea === view.trackingArea)
    }

    func testRefreshTrackingAreaCreatesNewAreaWhenBoundsChange() {
        let view = TrackingOverlayView { _, _ in }
        view.frame = NSRect(x: 0, y: 0, width: 120, height: 32)

        view.refreshTrackingArea()
        let initialArea = view.trackingArea

        view.setFrameSize(NSSize(width: 200, height: 48))
        view.refreshTrackingArea()

        XCTAssertNotNil(initialArea)
        XCTAssertNotNil(view.trackingArea)
        XCTAssertFalse(initialArea === view.trackingArea)
    }
}
