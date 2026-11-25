import XCTest
import SwiftUI
import AppKit
@testable import Kipple

@MainActor
final class HistoryPopoverLifecycleTests: XCTestCase {
    func testClipboardItemPopoverRenders() {
        let item = ClipItem(content: "Sample")
        let popover = ClipboardItemPopover(item: item)
        _ = popover.body
    }

    func testHistoryPopoverManagerShowAndHide() {
        let item = ClipItem(content: "Test")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        let anchor = NSView(frame: NSRect(x: 50, y: 50, width: 200, height: 40))
        window.contentView?.addSubview(anchor)
        window.makeKeyAndOrderFront(nil)

        HistoryPopoverManager.shared.forceClose()
        HistoryPopoverManager.shared.show(item: item, from: anchor, trailingEdge: true)

        // 共有ポップオーバーが表示された後でも close を呼んでも安全
        HistoryPopoverManager.shared.hide()
        HistoryPopoverManager.shared.forceClose()

        window.orderOut(nil)
    }

    func testPopoverStaysOpenWhilePointerCrossesFromTheRow() async throws {
        let manager = HistoryPopoverManager.shared
        manager.forceClose()
        let originalWindows = NSApp.windows
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 32))
        window.contentView?.addSubview(anchor)
        window.makeKeyAndOrderFront(nil)
        defer {
            manager.forceClose()
            window.orderOut(nil)
        }

        manager.show(item: ClipItem(content: "Pin from the details"), from: anchor, trailingEdge: true)
        let panel = try XCTUnwrap(NSApp.windows.first { window in
            window is NSPanel && !originalWindows.contains { $0 === window }
        })
        let content = try XCTUnwrap(panel.contentView)
        manager.scheduleHide(after: 0.01)
        content.mouseEntered(with: try hoverEvent(.mouseEntered, for: panel))
        manager.scheduleHide(after: 0.01)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(panel.isVisible)

        content.mouseExited(with: try hoverEvent(.mouseExited, for: panel))
        manager.scheduleHide(after: 0.01)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(panel.isVisible)
    }

    private func hoverEvent(_ type: NSEvent.EventType, for window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            trackingNumber: 0,
            userData: nil
        ))
    }
}
