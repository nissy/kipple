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
}
