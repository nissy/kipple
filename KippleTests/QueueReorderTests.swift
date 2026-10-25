import AppKit
import XCTest
@testable import Kipple

@MainActor
final class QueueReorderTests: XCTestCase {
    private var service: MockClipboardService!
    private var monitor: ReorderPasteMonitor!
    private var model: MainViewModel!
    private var items: [ClipItem] = []

    override func setUp() async throws {
        service = MockClipboardService()
        monitor = ReorderPasteMonitor()
        items = (0..<5).map { ClipItem(content: "Reorder \($0)") }
        service.history = items
        model = MainViewModel(clipboardService: service, pageSize: 2, pasteMonitor: monitor)
        model.toggleQueueMode()
        model.queueSelection(items: Array(items.prefix(4)), anchor: items[3])
    }

    override func tearDown() async throws {
        model = nil
        service = nil
        monitor = nil
        items = []
    }

    func testMoveToHeadUpdatesQueueBadgesAndVisiblePageWithoutCopying() throws {
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[3].id))
        let copies = service.recopyFromHistoryCallCount
        let clipboard = service.currentClipboardContent
        let editor = model.editorText
        let savedOrder = service.history.map(\.id)
        XCTAssertTrue(model.commitQueueReorder(session, target: target(0)))
        XCTAssertEqual(model.pasteQueue, [items[3], items[0], items[1], items[2]].map(\.id))
        XCTAssertEqual(model.history.map(\.id), [items[3], items[0]].map(\.id))
        XCTAssertEqual(model.queueBadge(for: items[3]), 1)
        XCTAssertEqual(model.nextQueuedItem()?.id, items[3].id)
        XCTAssertEqual(service.recopyFromHistoryCallCount, copies)
        XCTAssertEqual(service.currentClipboardContent, clipboard)
        XCTAssertEqual(model.editorText, editor)
        XCTAssertEqual(service.history.map(\.id), savedOrder)
        XCTAssertEqual(model.pasteQueueEpoch, session.epoch + 1)
    }

    func testMoveDownInsertsAfterTargetWithoutSwapping() throws {
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[0].id))
        XCTAssertTrue(model.commitQueueReorder(session, target: target(2, after: true)))
        XCTAssertEqual(model.pasteQueue, [items[1], items[2], items[0], items[3]].map(\.id))
    }

    func testMoveToTail() throws {
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[0].id))
        XCTAssertTrue(model.commitQueueReorder(session, target: target(3, after: true)))
        XCTAssertEqual(model.pasteQueue, [items[1], items[2], items[3], items[0]].map(\.id))
    }

    func testSameSlotAndSelfDropDoNotInvalidatePendingQueueState() throws {
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[1].id))
        for destination in [target(1), target(1, after: true), target(0, after: true), target(2)] {
            XCTAssertFalse(model.commitQueueReorder(session, target: destination))
        }
        XCTAssertEqual(model.pasteQueue, session.queue)
        XCTAssertEqual(model.pasteQueueEpoch, session.epoch)
    }

    func testUnknownSourceAndUnqueuedTargetAreRejected() throws {
        XCTAssertNil(model.beginQueueReorder(itemID: UUID()))
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[0].id))
        XCTAssertFalse(model.commitQueueReorder(session, target: target(4)))
        XCTAssertEqual(model.pasteQueue, session.queue)
    }

    func testUnqueuedItemIsInsertedOnlyOnDropWithoutCopying() throws {
        let copies = service.recopyFromHistoryCallCount
        let clipboard = service.currentClipboardContent
        let savedHistory = service.history.map(\.id)
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[4].id))
        XCTAssertEqual(model.pasteQueue, session.queue)
        XCTAssertNil(model.queueBadge(for: items[4]))
        XCTAssertTrue(model.commitQueueReorder(session, target: target(1)))
        XCTAssertEqual(model.pasteQueue, [items[0], items[4], items[1], items[2], items[3]].map(\.id))
        XCTAssertEqual(model.queueBadge(for: items[4]), 2)
        XCTAssertEqual(service.recopyFromHistoryCallCount, copies)
        XCTAssertEqual(service.currentClipboardContent, clipboard)
        XCTAssertEqual(service.history.map(\.id), savedHistory)
        XCTAssertFalse(model.commitQueueReorder(session, target: target(1)), "A drop cannot add the item twice")
    }

    func testUnqueuedItemCanBeInsertedAtHeadOrTail() throws {
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[4].id))
        XCTAssertEqual(target(0).applying(to: session), [items[4], items[0], items[1], items[2], items[3]].map(\.id))
        XCTAssertTrue(model.commitQueueReorder(session, target: target(3, after: true)))
        XCTAssertEqual(model.pasteQueue, items.map(\.id))
        XCTAssertEqual(model.queueBadge(for: items[4]), 5)
    }

    func testCancelledUnqueuedDragLeavesSelectionAndClipboardUnchanged() throws {
        let epoch = model.pasteQueueEpoch
        let clipboard = service.currentClipboardContent
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[4].id))
        // Cancellation discards the session without committing it.
        XCTAssertEqual(model.pasteQueue, session.queue)
        XCTAssertEqual(model.pasteQueueEpoch, epoch)
        XCTAssertNil(model.queueBadge(for: items[4]))
        XCTAssertEqual(service.currentClipboardContent, clipboard)
    }

    func testDropIntoEmptyQueueStartsMonitoringWithoutPreloadingClipboard() throws {
        model.resetPasteQueue()
        model.toggleQueueMode()
        let copies = service.recopyFromHistoryCallCount
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[4].id))
        XCTAssertTrue(model.pasteQueue.isEmpty)
        XCTAssertFalse(monitor.isMonitoring)
        XCTAssertTrue(model.commitQueueReorder(session, target: .end))
        XCTAssertEqual(model.pasteQueue, [items[4].id])
        XCTAssertEqual(model.nextQueuedItem()?.id, items[4].id)
        XCTAssertTrue(monitor.isMonitoring)
        XCTAssertEqual(service.recopyFromHistoryCallCount, copies)
    }

    func testUnqueuedDropWithAllQueueItemsFilteredOutAppendsWithoutLosingHiddenItems() throws {
        service.history[4].isPinned = true
        model.showOnlyPinned = true
        XCTAssertEqual(model.filteredHistory.map(\.id), [items[4].id])
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[4].id))
        XCTAssertTrue(model.commitQueueReorder(session, target: .end))
        XCTAssertEqual(model.pasteQueue, items.map(\.id))
        XCTAssertEqual(model.queueBadge(for: items[4]), 5)
    }

    func testExternalCopyOrDeletedSourcePreventsUnqueuedDrop() throws {
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[4].id))
        service.history.removeAll { $0.id == items[4].id }
        model.loadHistory()
        XCTAssertFalse(model.commitQueueReorder(session, target: target(0)))
        XCTAssertEqual(model.pasteQueue, session.queue)
        service.copyToClipboard("External", fromEditor: false)
        XCTAssertFalse(model.commitQueueReorder(session, target: .end))
        XCTAssertTrue(model.pasteQueue.isEmpty)
    }

    func testChangedQueueCannotBeOverwrittenByOldDrag() throws {
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[3].id))
        model.handleQueueSelection(for: items[1], modifiers: [])
        let updated = model.pasteQueue
        XCTAssertFalse(model.isQueueReorderValid(session))
        XCTAssertFalse(model.commitQueueReorder(session, target: target(0)))
        XCTAssertEqual(model.pasteQueue, updated)
    }

    func testConsumedItemIsNeverRestoredByOldDrag() throws {
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[3].id))
        model.didSendQueuedPaste(items[0])
        XCTAssertFalse(model.commitQueueReorder(session, target: target(1)))
        XCTAssertEqual(model.pasteQueue, [items[1], items[2], items[3]].map(\.id))
    }

    func testLoopingQueueContinuesFromReorderedHead() throws {
        model.toggleQueueRepetition()
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[3].id))
        XCTAssertTrue(model.commitQueueReorder(session, target: target(0)))
        model.didSendQueuedPaste(items[3])
        XCTAssertEqual(model.pasteMode, .queueToggle)
        XCTAssertEqual(model.pasteQueue, Array(items.prefix(4)).map(\.id))
    }

    func testFilterChangeCancelsEvenWhenSameRowsStillMatch() throws {
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[0].id))
        model.searchText = "Reorder"
        XCTAssertFalse(model.commitQueueReorder(session, target: target(3)))
        XCTAssertEqual(model.pasteQueue, session.queue)
    }

    func testFilteredInsertionKeepsHiddenItemsInTheQueue() throws {
        for index in [0, 2, 3] { service.history[index].isPinned = true }
        model.showOnlyPinned = true
        let visible = Set(model.filteredHistory.map(\.id))
        let hidden = try XCTUnwrap(model.pasteQueue.first { !visible.contains($0) })
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[3].id))
        XCTAssertTrue(model.commitQueueReorder(session, target: target(0)))
        XCTAssertEqual(model.pasteQueue, [items[3], items[0], items[1], items[2]].map(\.id))
        XCTAssertTrue(model.pasteQueue.contains(hidden))
    }

    func testPermissionLossModeChangeAndShiftSelectionRejectDragging() throws {
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[0].id))
        monitor.hasPermission = false
        XCTAssertFalse(model.isQueueReorderValid(session))
        monitor.hasPermission = true
        model.toggleQueueRepetition()
        XCTAssertFalse(model.isQueueReorderValid(session))
        model.handleModifierFlagsChanged(.shift)
        XCTAssertNil(model.beginQueueReorder(itemID: items[0].id))
        model.resetPasteQueue()
        XCTAssertFalse(model.commitQueueReorder(session, target: target(3)))
    }

    func testBeginningAndCancellingDoNotChangeQueueOrClipboard() throws {
        let epoch = model.pasteQueueEpoch
        let copies = service.recopyFromHistoryCallCount
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[0].id))
        // A cancelled drag never commits its snapshot.
        XCTAssertEqual(model.pasteQueue, session.queue)
        XCTAssertEqual(model.pasteQueueEpoch, epoch)
        XCTAssertEqual(service.recopyFromHistoryCallCount, copies)
    }

    func testInsertionGeometryAcceptsTailWhitespaceAndRejectsOutsideViewport() throws {
        let viewport = CGRect(x: 0, y: 0, width: 200, height: 200)
        let rows = items.prefix(2).enumerated().map { index, item in
            HistoryQueueRowFrame(itemID: item.id, frame: CGRect(x: 0, y: index * 34 + 4, width: 200, height: 32))
        }
        let queue = Array(items.prefix(2)).map(\.id)
        for point in [CGPoint(x: -1, y: 20), CGPoint(x: 40, y: 201)] {
            XCTAssertNil(destination(at: point, rows: rows, queue: queue, viewport: viewport))
        }
        let before = destination(at: CGPoint(x: 40, y: 8), rows: rows, queue: queue, viewport: viewport)
        XCTAssertEqual(before?.target, target(0))
        for position in [65, 100, 199] {
            let after = try XCTUnwrap(destination(
                at: CGPoint(x: 40, y: position), rows: rows, queue: queue, viewport: viewport
            ))
            XCTAssertEqual(after.target, .end)
            XCTAssertEqual(after.line.midY, rows[1].frame.maxY)
        }
    }

    func testAutoscrollOnlyMovesNearViewportEdges() {
        let viewport = CGRect(x: 0, y: 0, width: 200, height: 200)
        XCTAssertLessThan(HistoryQueueDropGeometry.scrollDelta(at: 5, viewport: viewport), 0)
        XCTAssertEqual(HistoryQueueDropGeometry.scrollDelta(at: 100, viewport: viewport), 0)
        XCTAssertGreaterThan(HistoryQueueDropGeometry.scrollDelta(at: 195, viewport: viewport), 0)
    }

    func testEmptyQueueAcceptsDropAnywhereInViewportIncludingBelowLastRow() {
        let viewport = CGRect(x: 0, y: 0, width: 200, height: 200)
        let rows = [HistoryQueueRowFrame(itemID: items[4].id, frame: CGRect(x: 0, y: -12, width: 200, height: 32))]
        for position in [8, 80, 199] {
            let drop = destination(at: CGPoint(x: 30, y: position), rows: rows, queue: [], viewport: viewport)
            XCTAssertEqual(drop?.target, .end)
            XCTAssertEqual(drop?.line.minY, viewport.minY)
        }
        for point in [CGPoint(x: -1, y: 8), CGPoint(x: 30, y: 201)] {
            XCTAssertNil(destination(at: point, rows: rows, queue: [], viewport: viewport))
        }
    }

    func testDraggingFromNormalModeCanBeCancelledWithoutChangingModeClipboardOrDraft() throws {
        model.resetPasteQueue()
        model.editorText = "Draft to preserve"
        let copies = service.recopyFromHistoryCallCount
        let epoch = model.pasteQueueEpoch
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[4].id))
        XCTAssertEqual(session.mode, .clipboard)
        XCTAssertTrue(model.isQueueReorderValid(session))
        XCTAssertEqual(model.pasteMode, .clipboard)
        XCTAssertTrue(model.pasteQueue.isEmpty)
        XCTAssertEqual(model.editorText, "Draft to preserve")
        XCTAssertEqual(model.pasteQueueEpoch, epoch)
        XCTAssertEqual(service.recopyFromHistoryCallCount, copies)
        XCTAssertFalse(monitor.isMonitoring)
    }

    func testLongPressStartsQueueWithoutDraggingOrCopying() {
        model.resetPasteQueue()
        let copies = service.recopyFromHistoryCallCount
        let clipboard = service.currentClipboardContent

        queueActions.startQueue(itemID: items[4].id)

        XCTAssertEqual(model.pasteMode, .queueOnce)
        XCTAssertEqual(model.pasteQueue, [items[4].id])
        XCTAssertEqual(model.queueBadge(for: items[4]), 1)
        XCTAssertTrue(monitor.isMonitoring)
        XCTAssertEqual(service.recopyFromHistoryCallCount, copies)
        XCTAssertEqual(service.currentClipboardContent, clipboard)
    }

    func testRepeatedLongPressDoesNotToggleOrAppendAfterQueueStarts() {
        model.resetPasteQueue()
        queueActions.startQueue(itemID: items[0].id)
        let epoch = model.pasteQueueEpoch

        queueActions.startQueue(itemID: items[0].id)
        queueActions.startQueue(itemID: items[4].id)

        XCTAssertEqual(model.pasteMode, .queueOnce)
        XCTAssertEqual(model.pasteQueue, [items[0].id])
        XCTAssertEqual(model.pasteQueueEpoch, epoch)
    }

    func testLongPressWithoutPermissionOrValidItemPreservesNormalModeAndDraft() {
        model.resetPasteQueue()
        model.editorText = "Draft to preserve"
        queueActions.startQueue(itemID: UUID())
        monitor.hasPermission = false
        queueActions.startQueue(itemID: items[4].id)

        XCTAssertEqual(model.pasteMode, .clipboard)
        XCTAssertTrue(model.pasteQueue.isEmpty)
        XCTAssertEqual(model.editorText, "Draft to preserve")
        XCTAssertFalse(monitor.isMonitoring)
    }

    func testNormalDragDoesNotOverwriteModeChangedDuringDrag() throws {
        model.resetPasteQueue()
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[4].id))
        model.toggleQueueMode()
        model.queueSelection(items: [items[0]], anchor: items[0])
        model.toggleQueueRepetition()
        XCTAssertFalse(model.commitQueueReorder(session, target: .end))
        XCTAssertEqual(model.pasteMode, .queueToggle)
        XCTAssertEqual(model.pasteQueue, [items[0].id])
    }

    func testDropBelowUnqueuedRowAddsItemAtActualQueueTail() throws {
        let viewport = CGRect(x: 0, y: 0, width: 200, height: 200)
        let rows = items.enumerated().map { index, item in
            HistoryQueueRowFrame(itemID: item.id, frame: CGRect(x: 0, y: index * 34 + 4, width: 200, height: 32))
        }
        let drop = try XCTUnwrap(destination(
            at: CGPoint(x: 40, y: 195), rows: rows, queue: model.pasteQueue, viewport: viewport
        ))
        XCTAssertEqual(drop.target, .end)
        let session = try XCTUnwrap(model.beginQueueReorder(itemID: items[4].id))
        XCTAssertTrue(model.commitQueueReorder(session, target: drop.target))
        XCTAssertEqual(model.pasteQueue, items.map(\.id))
        XCTAssertEqual(model.queueBadge(for: items[4]), 5)
    }

    func testTailInsertionLineRemainsVisibleWhenLastQueueRowTouchesBottom() throws {
        let viewport = CGRect(x: 0, y: 0, width: 200, height: 200)
        for rowBottom in [200, 204] {
            let rows = [
                HistoryQueueRowFrame(
                    itemID: items[3].id, frame: CGRect(x: 0, y: rowBottom - 32, width: 200, height: 32)
                )
            ]
            let drop = try XCTUnwrap(destination(
                at: CGPoint(x: 40, y: 199), rows: rows, queue: model.pasteQueue, viewport: viewport
            ))
            XCTAssertEqual(drop.target, .end)
            XCTAssertEqual(drop.line.maxY, viewport.maxY)
            XCTAssertTrue(viewport.contains(drop.line))
        }
    }

    func testScrollingPastQueueStillAllowsAppendingButNotBeforeUnseenQueueTail() {
        let viewport = CGRect(x: 0, y: 0, width: 200, height: 200)
        let rows = [HistoryQueueRowFrame(itemID: items[4].id, frame: CGRect(x: 0, y: 4, width: 200, height: 32))]
        XCTAssertEqual(destination(
            at: CGPoint(x: 40, y: 120), rows: rows, queue: model.pasteQueue, viewport: viewport
        )?.target, .end)
        XCTAssertNil(HistoryQueueDropGeometry.destination(
            at: CGPoint(x: 40, y: 120), rows: rows, queue: model.pasteQueue,
            orderedIDs: [items[4].id, items[3].id], viewport: viewport
        ))
    }

    private func destination(
        at point: CGPoint, rows: [HistoryQueueRowFrame], queue: [UUID], viewport: CGRect
    ) -> HistoryQueueDropGeometry.Destination? {
        HistoryQueueDropGeometry.destination(at: point, rows: rows, queue: queue, orderedIDs: items.map(\.id),
                                             viewport: viewport)
    }

    private var queueActions: QueueReorderActions {
        QueueReorderActions(
            begin: model.beginQueueReorder(itemID:), isValid: model.isQueueReorderValid
        ) { session, target in
            _ = self.model.commitQueueReorder(session, target: target)
        }
    }

    private func target(_ index: Int, after: Bool = false) -> QueueReorderTarget {
        QueueReorderTarget(itemID: items[index].id, insertAfter: after)
    }
}

private final class ReorderPasteMonitor: PasteCommandMonitoring {
    var hasPermission = true
    private(set) var isMonitoring = false
    func start(handler: @escaping () -> Void) -> Bool { isMonitoring = hasPermission; return hasPermission }
    func stop() { isMonitoring = false }
}
