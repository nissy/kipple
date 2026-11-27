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

    func testSourceLinkLabelOmitsOnlyTheLeadingWebScheme() throws {
        let cases = [
            ("HTTPS://example.com:8443/task%20list?next=https://example.net/#details",
             "example.com:8443/task%20list?next=https://example.net/#details"),
            ("http://example.com/page#section", "example.com/page#section"),
            ("slack://channel?id=C123", "slack://channel?id=C123")
        ]
        for (address, expected) in cases {
            let url = try XCTUnwrap(URL(string: address))
            let link = HistorySourceLink(url: url)
            XCTAssertEqual(HistorySourceLink.displayAddress(for: link.url), expected)
            XCTAssertEqual(link.url.absoluteString, address)
        }
    }

    func testHistoryPreviewWrapsLongWebURLsToTwoLinesAndOmitsAppURIs() {
        func size(for item: ClipItem) -> NSSize {
            NSHostingController(rootView: HistoryItemPreviewContent(
                item: item, categories: [], historyFont: .systemFont(ofSize: 13)
            ))
            .sizeThatFits(in: NSSize(width: 320, height: 1000))
        }

        var item = ClipItem(content: "Selected text from a web page")
        let original = size(for: item)
        item.metadata?.sourceURI = "slack://channel?team=T123&id=C456"
        XCTAssertEqual(size(for: item), original)

        item.metadata?.sourceURI = "https://example.com/"
        let shortLink = size(for: item)
        XCTAssertGreaterThan(shortLink.height, original.height)

        let longURL = "https://example.com/" + String(repeating: "path/", count: 80)
        item.metadata?.sourceURI = longURL
        let wrappedLink = size(for: item)
        XCTAssertEqual(wrappedLink.width, original.width)
        XCTAssertGreaterThan(wrappedLink.height, shortLink.height)
        XCTAssertLessThan(wrappedLink.height - shortLink.height, 22)

        item.metadata?.sourceURI = longURL + String(repeating: "additional-path/", count: 100)
        XCTAssertEqual(size(for: item), wrappedLink)
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

    func testScrollingAReusableHistoryRowOutOfViewDismissesItsDetails() async throws {
        let manager = HistoryPopoverManager.shared
        manager.forceClose()
        let items = (0..<40).map { ClipItem(content: "Row \($0)") }
        let proxy = HistoryTableProxy()
        let hover = HistoryHoverCoordinator()
        let keys = HistoryActionKeyMonitor()
        let history = HistoryTableView(
            entries: .full(items), hasMoreItems: false, showsProgress: false, proxy: proxy,
            canScrollToTop: .constant(false), isScrollLocked: .constant(false), onLoadMore: { _ in },
            row: { entry in
                HistoryItemView(
                    entry: entry, isSelected: false, isCurrentClipboardItem: false, queueBadge: nil,
                    isQueuePreviewed: false, isScrollLocked: false, onTap: { _ in }, onDelete: nil,
                    onChangeCategory: nil, onOpenCategoryManager: nil, historyFont: .body, onOpenItem: nil,
                    onSplitEditorIntoHistory: nil, hoverResetSignal: UUID(), hoverCoordinator: hover
                )
                .id(entry.id)
                .environmentObject(keys)
            }
        )
        let coordinator = history.makeCoordinator()
        let scroll = coordinator.makeScrollView()
        let window = HoverTestWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 170),
                                     styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        defer {
            manager.forceClose()
            coordinator.detach(from: scroll)
            window.orderOut(nil)
        }
        coordinator.update(history, in: scroll)
        try await Task.sleep(for: .milliseconds(50))
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        let first = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true))
        scroll.layoutSubtreeIfNeeded()
        let anchor = try XCTUnwrap(trackingOverlay(in: first))
        XCTAssertTrue(anchor.window === window)
        anchor.mouseEntered(with: try hoverEvent(.mouseEntered, for: window))
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(hover.hoveredItemID, items[0].id)
        let panel = try XCTUnwrap(NSApp.windows.first { $0 is NSPanel && $0.isVisible })

        proxy.scrollTo(try XCTUnwrap(items.last).id)
        scroll.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(panel.isVisible)
    }

    private func trackingOverlay(in view: NSView) -> TrackingOverlayView? {
        if let overlay = view as? TrackingOverlayView { return overlay }
        return view.subviews.lazy.compactMap { self.trackingOverlay(in: $0) }.first
    }

    private final class HoverTestWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    func testReopeningReusesThePanelAndResizesForTheNewItem() throws {
        let manager = HistoryPopoverManager { .zero }
        let originalWindows = NSApp.windows
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let firstRow = NSView(frame: NSRect(x: 0, y: 220, width: 200, height: 32))
        let secondRow = NSView(frame: NSRect(x: 0, y: 180, width: 200, height: 32))
        window.contentView?.addSubview(firstRow)
        window.contentView?.addSubview(secondRow)
        window.makeKeyAndOrderFront(nil)
        defer {
            manager.forceClose()
            window.orderOut(nil)
        }

        manager.show(item: ClipItem(content: "First row"), from: firstRow, trailingEdge: true)
        let panel = try XCTUnwrap(NSApp.windows.first {
            $0 is NSPanel && $0.isVisible && !originalWindows.contains($0)
        })
        let container = try XCTUnwrap(panel.contentView)
        let firstHeight = panel.frame.height
        manager.hide()
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(manager.prepareForRowHover(secondRow))

        let secondItem = ClipItem(content: "Second row\nMore details\nA third preview line")
        manager.show(item: secondItem, from: secondRow, trailingEdge: true)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.contentView === container)
        XCTAssertGreaterThan(panel.frame.height, firstHeight)
        manager.hide(ifAnchoredTo: firstRow)
        XCTAssertTrue(panel.isVisible)
    }

    func testCrossingAnotherRowKeepsThePanelUntilTheNewRowSettles() async throws {
        let manager = HistoryPopoverManager { .zero }
        let originalWindows = NSApp.windows
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let firstRow = NSView(frame: NSRect(x: 0, y: 220, width: 200, height: 32))
        let secondRow = NSView(frame: NSRect(x: 0, y: 180, width: 200, height: 32))
        window.contentView?.addSubview(firstRow)
        window.contentView?.addSubview(secondRow)
        window.makeKeyAndOrderFront(nil)
        defer {
            manager.forceClose()
            window.orderOut(nil)
        }

        manager.show(item: ClipItem(content: "First row"), from: firstRow, trailingEdge: true)
        let firstPanel = try XCTUnwrap(NSApp.windows.first { panel in
            panel is NSPanel && panel.isVisible && !originalWindows.contains { $0 === panel }
        })
        manager.scheduleHide(after: 0.01, ifAnchoredTo: firstRow)
        XCTAssertFalse(manager.prepareForRowHover(firstRow))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(firstPanel.isVisible)

        XCTAssertTrue(manager.prepareForRowHover(secondRow))
        let firstFrame = firstPanel.frame
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(firstPanel.isVisible)
        XCTAssertEqual(firstPanel.frame, firstFrame)

        manager.show(item: ClipItem(content: "Second row"), from: secondRow, trailingEdge: true)
        XCTAssertTrue(firstPanel.isVisible)
        XCTAssertNotEqual(firstPanel.frame, firstFrame)
        manager.scheduleHide(after: 0.01, ifAnchoredTo: firstRow)
        manager.hide(ifAnchoredTo: firstRow)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(firstPanel.isVisible)
    }

    func testPopoverStaysOpenWhilePointerCrossesFromTheRow() async throws {
        let manager = HistoryPopoverManager { .zero }
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

    func testPendingDismissalRechecksThePointerWhenTheEnterEventHasNotArrived() async throws {
        var pointer = CGPoint.zero
        let manager = HistoryPopoverManager { pointer }
        let originalWindows = NSApp.windows
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let anchor = NSView(frame: NSRect(x: 50, y: 50, width: 200, height: 32))
        window.contentView?.addSubview(anchor)
        window.makeKeyAndOrderFront(nil)
        defer {
            manager.forceClose()
            window.orderOut(nil)
        }

        manager.show(item: ClipItem(content: "Source link"), from: anchor, trailingEdge: true)
        let panel = try XCTUnwrap(NSApp.windows.first {
            $0 is NSPanel && $0.isVisible && !originalWindows.contains($0)
        })
        manager.scheduleHide(after: 0.01)
        pointer = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(panel.isVisible)

        pointer = .zero
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
