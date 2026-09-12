import AppKit
import XCTest
@testable import Kipple

@MainActor
final class WindowSheetBehaviorTests: XCTestCase {
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: -2_000, y: -2_000, width: 420, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        return window
    }

    func testSheetKeepsParentVisibleAndAutoHideResumesAfterDismissal() async throws {
        let manager = WindowManager()
        let window = makeWindow()
        manager.setMainWindowForTesting(window)
        defer { window.close() }

        for response in [NSApplication.ModalResponse.cancel, .OK] {
            window.orderFront(nil)
            let sheet = makeWindow()
            defer { sheet.close() }

            // SwiftUI can attach its sheet after the parent's resign-key notification.
            let notification = Notification(name: NSWindow.didResignKeyNotification, object: window)
            manager.windowDidResignKey(notification)
            window.beginSheet(sheet, completionHandler: nil)
            XCTAssertTrue(window.attachedSheet === sheet)
            XCTAssertFalse(window.isKeyWindow)

            try await Task.sleep(for: .milliseconds(250))
            XCTAssertTrue(window.isVisible, "Opening details must not hide the history panel")

            window.endSheet(sheet, returnCode: response)
            sheet.orderOut(nil)
            XCTAssertNil(window.attachedSheet)
            XCTAssertTrue(window.isVisible, "Saving or cancelling details must retain the panel")

            manager.windowDidResignKey(notification)
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertFalse(window.isVisible, "Normal auto-hide must resume after the sheet closes")
        }
    }

    func testUnrelatedWindowResigningDoesNotHideMainWindow() async throws {
        let manager = WindowManager()
        let window = makeWindow()
        let otherWindow = makeWindow()
        manager.setMainWindowForTesting(window)
        defer {
            window.close()
            otherWindow.close()
        }
        window.orderFront(nil)

        manager.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: otherWindow))
        try await Task.sleep(for: .milliseconds(250))

        XCTAssertTrue(window.isVisible)
    }
}
