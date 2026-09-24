import AppKit
import XCTest
@testable import Kipple

@MainActor
final class WindowPositionRestorationTests: XCTestCase {
    func testOCRRestorationKeepsVisibleAndHiddenFramesForEveryAnimationStyle() async throws {
        let previousStyle = UserDefaults.standard.object(forKey: "windowAnimation")
        defer { UserDefaults.standard.set(previousStyle, forKey: "windowAnimation") }

        for style in ["none", "fade", "slide"] {
            UserDefaults.standard.set(style, forKey: "windowAnimation")
            for wasVisible in [false, true] {
                let manager = WindowManager()
                let window = makeWindow(visible: wasVisible)
                defer { window.close() }
                manager.setMainWindowForTesting(window)
                let frame = window.frame

                manager.openMainWindow(preservingPosition: true)

                XCTAssertEqual(window.frame, frame)
                XCTAssertEqual(window.frameMutationCount, 0)
                XCTAssertEqual(window.orderOutCount, 0)
                XCTAssertTrue(window.isVisible)
                XCTAssertTrue(window.isKeyWindow)
                XCTAssertEqual(window.alphaValue, 1)
                // A delayed slide or focus callback must not move the restored window either.
                try await Task.sleep(for: .milliseconds(300))
                XCTAssertEqual(window.frame, frame)
                XCTAssertEqual(window.frameMutationCount, 0)
            }
        }
    }

    func testExplicitOpenStillPositionsVisibleAndHiddenWindowsAtCursor() {
        let previousStyle = UserDefaults.standard.object(forKey: "windowAnimation")
        UserDefaults.standard.set("none", forKey: "windowAnimation")
        defer { UserDefaults.standard.set(previousStyle, forKey: "windowAnimation") }

        for wasVisible in [false, true] {
            let manager = WindowManager()
            let window = makeWindow(visible: wasVisible)
            defer { window.close() }
            manager.setMainWindowForTesting(window)
            let originalFrame = window.frame

            manager.openMainWindow()

            XCTAssertNotEqual(window.frame.origin, originalFrame.origin)
            XCTAssertEqual(window.frame.size, originalFrame.size)
            XCTAssertGreaterThan(window.frameMutationCount, 0)
            XCTAssertTrue(window.isVisible)
        }
    }

    private func makeWindow(visible: Bool) -> PositionTrackingWindow {
        let window = PositionTrackingWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 420, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.simulatedVisibility = visible
        window.alphaValue = visible ? 1 : 0
        window.frameMutationCount = 0
        return window
    }
}

// Keep these tests offscreen while observing WindowManager's real frame mutations.
@MainActor
private final class PositionTrackingWindow: NSWindow {
    var simulatedVisibility = false
    private var simulatedKey = false
    var frameMutationCount = 0
    private(set) var orderOutCount = 0

    override var isVisible: Bool { simulatedVisibility }
    override var isKeyWindow: Bool { simulatedKey }

    override func orderFrontRegardless() {
        simulatedVisibility = true
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        simulatedVisibility = true
        simulatedKey = true
    }

    override func orderOut(_ sender: Any?) {
        orderOutCount += 1
        simulatedVisibility = false
        simulatedKey = false
    }

    override func setFrameOrigin(_ point: NSPoint) {
        frameMutationCount += 1
        super.setFrameOrigin(point)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        frameMutationCount += 1
        super.setFrame(frameRect, display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate: Bool) {
        frameMutationCount += 1
        super.setFrame(frameRect, display: flag, animate: animate)
    }
}
