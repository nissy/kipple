import AppKit
import XCTest
@testable import Kipple

@MainActor
final class ScreenSelectionOverlayControllerTests: XCTestCase {
    func testSelectionOverlaysTrackMouseMovementAndRestoreTheCrosshairOnEveryScreen() throws {
        let screens = NSScreen.screens
        XCTAssertFalse(screens.isEmpty)
        let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        var cancellations = 0
        let overlay = ScreenSelectionOverlayController(onSelection: { _, _ in
            XCTFail("Mouse movement alone must not select a region")
        }, onCancel: {
            cancellations += 1
        })
        overlay.present()
        defer { overlay.cancel() }

        let windows = NSApp.windows.filter { !previousWindows.contains(ObjectIdentifier($0)) && $0.isVisible }
        XCTAssertEqual(windows.count, screens.count)
        for window in windows {
            XCTAssertTrue(window.acceptsMouseMovedEvents)
            let view = try XCTUnwrap(window.contentView)
            view.updateTrackingAreas()
            let tracking = try XCTUnwrap(view.trackingAreas.first { $0.options.contains(.cursorUpdate) })
            XCTAssertTrue(tracking.options.contains([.activeInActiveApp, .mouseMoved]))
            XCTAssertFalse(tracking.options.contains(.activeAlways))

            let move = try XCTUnwrap(NSEvent.mouseEvent(
                with: .mouseMoved, location: NSPoint(x: 30, y: 30), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
            ))
            NSCursor.arrow.set()
            view.mouseMoved(with: move)
            XCTAssertTrue(NSCursor.current === NSCursor.crosshair)
            XCTAssertTrue(window.isVisible)
        }
        XCTAssertEqual(cancellations, 0)
    }
}
