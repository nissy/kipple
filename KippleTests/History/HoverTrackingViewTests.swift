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

    func testHoverNotificationWaitsUntilViewUpdateHasFinished() async throws {
        var notifications: [Bool] = []
        let view = TrackingOverlayView { hovering, _ in notifications.append(hovering) }

        view.mouseEntered(with: try mouseEvent(.mouseEntered))

        XCTAssertTrue(notifications.isEmpty)
        await drainMainQueue()
        XCTAssertEqual(notifications, [true])
    }

    func testUnlockRestoresHoverAsynchronously() async throws {
        var notifications: [Bool] = []
        let view = TrackingOverlayView { hovering, _ in notifications.append(hovering) }
        view.isScrollLocked = true
        view.mouseEntered(with: try mouseEvent(.mouseEntered))

        view.isScrollLocked = false

        XCTAssertTrue(notifications.isEmpty)
        await drainMainQueue()
        XCTAssertEqual(notifications, [true])
    }

    func testMouseExitCancelsPendingHoverRestoration() async throws {
        var notifications: [Bool] = []
        let view = TrackingOverlayView { hovering, _ in notifications.append(hovering) }
        view.isScrollLocked = true
        view.mouseEntered(with: try mouseEvent(.mouseEntered))
        view.isScrollLocked = false

        view.mouseExited(with: try mouseEvent(.mouseExited))

        XCTAssertTrue(notifications.isEmpty)
        await drainMainQueue()
        XCTAssertEqual(notifications, [false])
    }

    func testRelockingCancelsPendingHoverRestoration() async throws {
        var notifications: [Bool] = []
        let view = TrackingOverlayView { hovering, _ in notifications.append(hovering) }
        view.isScrollLocked = true
        view.mouseEntered(with: try mouseEvent(.mouseEntered))
        view.isScrollLocked = false

        view.isScrollLocked = true

        await drainMainQueue()
        XCTAssertTrue(notifications.isEmpty)
    }

    func testRemovingViewCancelsHoverAndDeliversExitAfterViewUpdate() async throws {
        var notifications: [Bool] = []
        weak var removedView: TrackingOverlayView?
        let parent = NSView()
        do {
            let view = TrackingOverlayView { hovering, _ in notifications.append(hovering) }
            removedView = view
            parent.addSubview(view)
            view.mouseEntered(with: try mouseEvent(.mouseEntered))

            view.removeFromSuperview()
        }

        XCTAssertTrue(notifications.isEmpty)
        await drainMainQueue()
        XCTAssertEqual(notifications, [false])
        XCTAssertNil(removedView)
    }

    func testRepeatedUnlocksDeliverOnlyLatestHoverState() async throws {
        var notifications: [Bool] = []
        let view = TrackingOverlayView { hovering, _ in notifications.append(hovering) }
        view.isScrollLocked = true
        view.mouseEntered(with: try mouseEvent(.mouseEntered))

        view.isScrollLocked = false
        view.isScrollLocked = true
        view.isScrollLocked = false

        await drainMainQueue()
        XCTAssertEqual(notifications, [true])
    }

    func testUnlockAfterMouseExitDoesNotRestoreHover() async throws {
        var notifications: [Bool] = []
        let view = TrackingOverlayView { hovering, _ in notifications.append(hovering) }
        view.isScrollLocked = true
        view.mouseEntered(with: try mouseEvent(.mouseEntered))
        view.mouseExited(with: try mouseEvent(.mouseExited))

        view.isScrollLocked = false

        await drainMainQueue()
        XCTAssertTrue(notifications.isEmpty)
    }

    private func mouseEvent(_ type: NSEvent.EventType) throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(
            with: type, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        ))
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
