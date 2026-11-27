@testable import Kipple
import AppKit
import SwiftUI
import XCTest

@MainActor
final class HistoryListViewHelperTests: XCTestCase {
    func testIsCurrentClipboardItemMatchesID() {
        let item = ClipItem(content: "match")
        XCTAssertTrue(HistoryListView.isCurrentClipboardItem(item, currentID: item.id))
    }

    func testIsCurrentClipboardItemReturnsFalseWhenIDDiffers() {
        let item = ClipItem(content: "diff")
        XCTAssertFalse(HistoryListView.isCurrentClipboardItem(item, currentID: UUID()))
    }

    func testIsCurrentClipboardItemReturnsFalseWhenIDMissing() {
        let item = ClipItem(content: "none")
        XCTAssertFalse(HistoryListView.isCurrentClipboardItem(item, currentID: nil))
    }

    func testNativeTableUpdatesAStartupRowAndScrollsToTheGivenItem() async throws {
        let items = (0..<30).map { ClipItem(content: "Full text \($0)") }
        let previews = items.map {
            HistoryRowPreview(id: $0.id, text: "Preview", title: nil, categoryIDs: [], isActionable: false)
        }
        let proxy = HistoryTableProxy()
        var requested: [UUID] = []
        let previewTable = makeTable(.startup(previews), proxy: proxy) { requested.append($0.id) }
        let coordinator = previewTable.makeCoordinator()
        let scroll = coordinator.makeScrollView()
        let window = makeWindow(for: scroll)
        defer {
            coordinator.detach(from: scroll)
            window.orderOut(nil)
        }
        coordinator.update(previewTable, in: scroll)
        scroll.layoutSubtreeIfNeeded()

        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        let first = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSHostingView<TestRow?>)
        XCTAssertEqual(first.rootView?.content, "Preview")
        let fullTable = makeTable(.full(items), proxy: proxy) { requested.append($0.id) }
        coordinator.update(fullTable, in: scroll)
        XCTAssertEqual(first.rootView?.content, items[0].content)
        XCTAssertEqual(table.numberOfRows, items.count)

        let last = try XCTUnwrap(items.last)
        proxy.scrollTo(last.id)
        scroll.layoutSubtreeIfNeeded()
        await Task.yield()
        XCTAssertTrue(NSLocationInRange(items.count - 1, table.rows(in: table.visibleRect)))
        XCTAssertEqual(requested, [last.id])
        proxy.scrollTo(items[0].id)
        XCTAssertTrue(NSLocationInRange(0, table.rows(in: table.visibleRect)))
    }

    func testNativeTableLoadsOlderHistoryWhenTheLastVisibleItemIsUnchanged() async throws {
        let items = (0..<6).map { ClipItem(content: "Page item \($0)") }
        let service = MockClipboardService()
        service.history = Array(items.prefix(4))
        let model = MainViewModel(clipboardService: service, pageSize: 4)
        let proxy = HistoryTableProxy()
        let initial = makeTable(
            .full(model.history), proxy: proxy, hasMoreItems: model.hasMoreHistory,
            onLoadMore: model.loadMoreHistoryIfNeeded
        )
        let coordinator = initial.makeCoordinator()
        let scroll = coordinator.makeScrollView()
        let window = makeWindow(for: scroll)
        defer {
            coordinator.detach(from: scroll)
            window.orderOut(nil)
        }
        coordinator.update(initial, in: scroll)
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        _ = table.view(atColumn: 0, row: 3, makeIfNecessary: true)
        await Task.yield()
        XCTAssertEqual(model.history.map(\.id), items.prefix(4).map(\.id))

        model.updateFilteredItems(items)
        XCTAssertEqual(model.history.map(\.id), items.prefix(4).map(\.id))
        XCTAssertTrue(model.hasMoreHistory)
        let expanded = makeTable(
            .full(model.history), proxy: proxy, hasMoreItems: model.hasMoreHistory,
            onLoadMore: model.loadMoreHistoryIfNeeded
        )
        coordinator.update(expanded, in: scroll)
        await Task.yield()
        XCTAssertEqual(model.history.map(\.id), items.map(\.id))
    }

    func testNativeTableRefreshesCachedRowsThatMoveBackIntoView() throws {
        let items = (0..<30).map { ClipItem(content: "Cell \($0)") }
        let proxy = HistoryTableProxy()
        let initial = makeTable(.full(items), proxy: proxy) { _ in }
        let coordinator = initial.makeCoordinator()
        let scroll = coordinator.makeScrollView()
        let window = makeWindow(for: scroll)
        defer {
            coordinator.detach(from: scroll)
            window.orderOut(nil)
        }
        coordinator.update(initial, in: scroll)
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        let offscreenIndex = 6
        XCTAssertFalse(NSLocationInRange(offscreenIndex, table.rows(in: table.visibleRect)))
        let oldView = try XCTUnwrap(
            table.view(atColumn: 0, row: offscreenIndex, makeIfNecessary: true) as? NSHostingView<TestRow?>
        )
        XCTAssertEqual(oldView.rootView?.content, items[offscreenIndex].content)

        var changedItems = items
        changedItems[offscreenIndex] = items[offscreenIndex].replacingContent(with: "Updated")
        coordinator.update(makeTable(.full(changedItems), proxy: proxy) { _ in }, in: scroll)
        proxy.scrollTo(items[offscreenIndex].id)
        scroll.layoutSubtreeIfNeeded()
        let updated = try XCTUnwrap(
            table.view(atColumn: 0, row: offscreenIndex, makeIfNecessary: true) as? NSHostingView<TestRow?>
        )
        XCTAssertEqual(updated.rootView?.content, "Updated")
    }

    func testPendingPageRequestIsCancelledWhenTheTableIsRemoved() async throws {
        let item = ClipItem(content: "Last visible item")
        let proxy = HistoryTableProxy()
        var requested = false
        let history = makeTable(.full([item]), proxy: proxy) { _ in requested = true }
        let coordinator = history.makeCoordinator()
        let scroll = coordinator.makeScrollView()
        let window = makeWindow(for: scroll)
        defer { window.orderOut(nil) }
        coordinator.update(history, in: scroll)
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        _ = table.view(atColumn: 0, row: 0, makeIfNecessary: true)
        coordinator.detach(from: scroll)
        await Task.yield()
        XCTAssertFalse(requested)
    }

    func testNewFilterResultsReplaceRowsAfterTheTableWasEmpty() throws {
        let items = (0..<30).map { ClipItem(content: "Old result \($0)") }
        let proxy = HistoryTableProxy()
        let history = makeTable(.full(items), proxy: proxy, hasMoreItems: false) { _ in }
        let coordinator = history.makeCoordinator()
        let scroll = coordinator.makeScrollView()
        let window = makeWindow(for: scroll)
        defer {
            coordinator.detach(from: scroll)
            window.orderOut(nil)
        }
        coordinator.update(history, in: scroll)
        proxy.scrollTo(try XCTUnwrap(items.last).id)
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        XCTAssertFalse(NSLocationInRange(0, table.rows(in: table.visibleRect)))

        coordinator.update(makeTable(.full([]), proxy: proxy, hasMoreItems: false) { _ in }, in: scroll)
        XCTAssertEqual(table.numberOfRows, 0)
        let result = ClipItem(content: "新しい検索結果 👩🏽‍💻")
        coordinator.update(makeTable(.full([result]), proxy: proxy, hasMoreItems: false) { _ in }, in: scroll)
        scroll.layoutSubtreeIfNeeded()
        XCTAssertTrue(NSLocationInRange(0, table.rows(in: table.visibleRect)))
        let visible = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSHostingView<TestRow?>)
        XCTAssertEqual(visible.rootView?.content, result.content)
    }

    private func makeTable(
        _ entries: HistoryListEntries,
        proxy: HistoryTableProxy,
        hasMoreItems: Bool = true,
        onLoadMore: @escaping (ClipItem) -> Void
    ) -> HistoryTableView<TestRow> {
        HistoryTableView(
            entries: entries, hasMoreItems: hasMoreItems, showsProgress: false, proxy: proxy,
            canScrollToTop: .constant(false), isScrollLocked: .constant(false), onLoadMore: onLoadMore
        ) { entry in
            TestRow(content: entry.fullItem?.content ?? "Preview")
        }
    }

    private func makeWindow(for scroll: NSScrollView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 170),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private struct TestRow: View {
        let content: String
        var body: some View { Text(content) }
    }
}
