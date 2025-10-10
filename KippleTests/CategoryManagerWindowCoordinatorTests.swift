@testable import Kipple
import AppKit
import XCTest

@MainActor
final class CategoryManagerWindowCoordinatorTests: XCTestCase {
    func testPositionPlacesWindowToRightWhenSpaceAvailable() throws {
        guard let screen = NSScreen.main else {
            throw XCTSkip("No screen available")
        }

        let anchorFrame = NSRect(x: screen.visibleFrame.midX - 200, y: screen.visibleFrame.midY - 150, width: 300, height: 200)
        let anchorWindow = NSWindow(contentRect: anchorFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        anchorWindow.setFrame(anchorFrame, display: false)

        let windowFrame = NSRect(x: 0, y: 0, width: 240, height: 220)
        let testWindow = NSWindow(contentRect: windowFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        testWindow.setFrame(windowFrame, display: false)

        let expected = expectedPosition(anchorFrame: anchorFrame, windowSize: windowFrame.size, screenFrame: screen.visibleFrame)

        CategoryManagerWindowCoordinator.shared.test_position(window: testWindow, near: anchorWindow)

        XCTAssertEqual(testWindow.frame.origin.x, expected.x, accuracy: 0.5)
        XCTAssertEqual(testWindow.frame.origin.y, expected.y, accuracy: 0.5)
    }

    func testPositionMovesWindowToLeftWhenSpaceUnavailable() throws {
        guard let screen = NSScreen.main else {
            throw XCTSkip("No screen available")
        }

        let anchorWidth: CGFloat = 320
        let anchorFrame = NSRect(
            x: screen.visibleFrame.maxX - anchorWidth - 4,
            y: screen.visibleFrame.midY - 150,
            width: anchorWidth,
            height: 240
        )
        let anchorWindow = NSWindow(contentRect: anchorFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        anchorWindow.setFrame(anchorFrame, display: false)

        let windowFrame = NSRect(x: 0, y: 0, width: 280, height: 260)
        let testWindow = NSWindow(contentRect: windowFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        testWindow.setFrame(windowFrame, display: false)

        let expected = expectedPosition(anchorFrame: anchorFrame, windowSize: windowFrame.size, screenFrame: screen.visibleFrame)

        CategoryManagerWindowCoordinator.shared.test_position(window: testWindow, near: anchorWindow)

        XCTAssertEqual(testWindow.frame.origin.x, expected.x, accuracy: 0.5)
        XCTAssertEqual(testWindow.frame.origin.y, expected.y, accuracy: 0.5)
        XCTAssertLessThan(testWindow.frame.origin.x, anchorFrame.minX)
    }

    // MARK: - Helpers

    private func expectedPosition(anchorFrame: NSRect, windowSize: NSSize, screenFrame: NSRect) -> NSPoint {
        var targetOrigin = NSPoint(
            x: anchorFrame.maxX + 16,
            y: anchorFrame.maxY - windowSize.height
        )

        if targetOrigin.x + windowSize.width > screenFrame.maxX {
            targetOrigin.x = anchorFrame.minX - windowSize.width - 16
        }

        targetOrigin.x = max(screenFrame.minX, min(targetOrigin.x, screenFrame.maxX - windowSize.width))
        targetOrigin.y = max(screenFrame.minY, min(targetOrigin.y, screenFrame.maxY - windowSize.height))
        return targetOrigin
    }
}
