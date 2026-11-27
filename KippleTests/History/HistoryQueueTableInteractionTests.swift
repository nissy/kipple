import AppKit
import Combine
import SwiftUI
import XCTest
@testable import Kipple

@MainActor
final class HistoryQueueTableInteractionTests: XCTestCase {
    func testDraggingBetweenNativeHistoryRowsReordersTheQueue() async throws {
        let fixture = QueueTableFixture()
        try await fixture.show()
        defer { fixture.close() }

        fixture.beginDrag(at: 1)
        XCTAssertEqual(fixture.drag.itemID, fixture.items[1].id)
        fixture.placePointer(inRow: 0, fraction: 0.25)
        fixture.drag.finish()

        XCTAssertEqual(fixture.model.pasteQueue, [1, 0, 2, 3].map { fixture.items[$0].id })
        XCTAssertNil(fixture.drag.insertionFrame)
    }

    func testDraggingDownwardAcrossPagesKeepsTheOriginalItemAndDropsAtTheNewRow() async throws {
        let fixture = QueueTableFixture(itemCount: 24, queueCount: 16, pageSize: 4, viewportHeight: 124)
        try await fixture.show()
        defer { fixture.close() }

        let start = fixture.model.pasteQueue
        let previousCopies = fixture.service.recopyFromHistoryCallCount
        let firstPageCount = fixture.model.history.count
        XCTAssertTrue(fixture.model.hasMoreHistory)
        fixture.beginDrag(at: 1)
        XCTAssertEqual(fixture.drag.itemID, fixture.items[1].id)
        fixture.pointNearBottom()

        let destination = 10
        try await fixture.waitUntil {
            fixture.model.history.count > firstPageCount && fixture.isFullyVisible(row: destination)
        }
        XCTAssertFalse(fixture.isVisible(row: 1))
        XCTAssertEqual(fixture.drag.itemID, fixture.items[1].id)
        XCTAssertEqual(fixture.model.pasteQueue, start)

        fixture.placePointer(inRow: destination, fraction: 0.25)
        fixture.drag.finish()

        var expected = start
        let moved = expected.remove(at: 1)
        expected.insert(moved, at: destination - 1)
        XCTAssertEqual(fixture.model.pasteQueue, expected)
        XCTAssertEqual(fixture.model.queueBadge(for: fixture.items[1]), destination)
        XCTAssertEqual(fixture.service.recopyFromHistoryCallCount, previousCopies)
    }

    func testChangingTheSearchWhileDraggingCancelsBeforeAnyDrop() async throws {
        let fixture = QueueTableFixture()
        try await fixture.show()
        defer { fixture.close() }

        let start = fixture.model.pasteQueue
        let previousCopies = fixture.service.recopyFromHistoryCallCount
        fixture.beginDrag(at: 1)
        XCTAssertEqual(fixture.drag.itemID, fixture.items[1].id)
        fixture.model.searchText = "different query"
        try await fixture.waitUntil { fixture.drag.itemID == nil }
        fixture.placePointer(inRow: 0, fraction: 0.25)
        fixture.drag.finish()

        XCTAssertEqual(fixture.model.pasteQueue, start)
        XCTAssertEqual(fixture.service.recopyFromHistoryCallCount, previousCopies)
        XCTAssertNil(fixture.drag.insertionFrame)
    }
}

@MainActor
private final class QueueTableFixture {
    private final class Pointer {
        var location = CGPoint.zero
    }

    private final class TestWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    private final class PasteMonitor: PasteCommandMonitoring {
        let hasPermission = true
        func start(handler: @escaping () -> Void) -> Bool { true }
        func stop() {}
    }

    let items: [ClipItem]
    let service = MockClipboardService()
    let model: MainViewModel
    let drag: HistoryQueueDragController
    private let pointer = Pointer()
    private let window: TestWindow
    private let surface = HistoryQueueDragAnchor.AnchorView()
    private let proxy = HistoryTableProxy()
    private var observation: AnyCancellable?
    private lazy var coordinator = historyTable().makeCoordinator()
    private lazy var scroll = coordinator.makeScrollView()
    private var table: NSTableView? { scroll.documentView as? NSTableView }

    init(itemCount: Int = 5, queueCount: Int = 4, pageSize: Int = 10, viewportHeight: CGFloat = 170) {
        items = (0..<itemCount).map { ClipItem(content: "Queue row \($0)") }
        service.history = items
        model = MainViewModel(clipboardService: service, pageSize: pageSize, pasteMonitor: PasteMonitor())
        model.toggleQueueMode()
        model.queueSelection(items: Array(items.prefix(queueCount)), anchor: items[queueCount - 1])
        drag = HistoryQueueDragController(
            pointerLocation: { [pointer] in pointer.location }, isPrimaryButtonPressed: { true }
        )
        window = TestWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: viewportHeight),
                            styleMask: [.titled], backing: .buffered, defer: false)
    }

    func show() async throws {
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        surface.frame = scroll.bounds
        scroll.addSubview(surface)
        drag.surface = surface
        drag.actions = QueueReorderActions(
            begin: model.beginQueueReorder, isValid: model.isQueueReorderValid
        ) { [model] session, target in
            _ = model.commitQueueReorder(session, target: target)
        }
        observation = model.$history.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.updateTable() }
        }
        updateTable()
        try await Task.sleep(for: .milliseconds(50))
    }

    func close() {
        observation = nil
        drag.cancel()
        coordinator.detach(from: scroll)
        window.orderOut(nil)
    }

    private func historyTable() -> HistoryTableView<AnyView> {
        HistoryTableView(
            entries: .full(model.history), hasMoreItems: model.hasMoreHistory, showsProgress: false, proxy: proxy,
            canScrollToTop: .constant(false), isScrollLocked: .constant(false),
            onLoadMore: model.loadMoreHistoryIfNeeded
        ) { [drag] entry in
            AnyView(
                Text(entry.fullItem?.content ?? "")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(HistoryQueueDragAnchor(controller: drag, itemID: entry.id))
                    .id(entry.id)
            )
        }
    }

    private func updateTable() {
        guard observation != nil else { return }
        drag.visibleIDs = model.history.map(\.id)
        coordinator.update(historyTable(), in: scroll)
        scroll.layoutSubtreeIfNeeded()
    }

    func beginDrag(at row: Int) {
        placePointer(inRow: row, fraction: 0.5)
        drag.begin(itemID: model.history[row].id, translation: .zero)
    }

    func placePointer(inRow row: Int, fraction: CGFloat) {
        guard let table, row < table.numberOfRows else { return }
        let rect = table.rect(ofRow: row)
        let point = CGPoint(x: rect.midX, y: rect.minY + rect.height * fraction)
        pointer.location = window.convertPoint(toScreen: table.convert(point, to: nil))
    }

    func pointNearBottom() {
        let point = CGPoint(x: surface.bounds.midX, y: surface.bounds.maxY - 2)
        pointer.location = window.convertPoint(toScreen: surface.convert(point, to: nil))
    }

    func isVisible(row: Int) -> Bool {
        guard let table else { return false }
        return NSLocationInRange(row, table.rows(in: table.visibleRect))
    }

    func isFullyVisible(row: Int) -> Bool {
        guard let table, row < table.numberOfRows else { return false }
        let rect = table.rect(ofRow: row)
        return rect.minY >= table.visibleRect.minY && rect.maxY <= table.visibleRect.maxY
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }
}
