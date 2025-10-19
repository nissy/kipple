//
//  PasteQueueModeTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/10/17.
//

import XCTest
import AppKit
@testable import Kipple

@MainActor
final class PasteQueueModeTests: XCTestCase {
    private var viewModel: MainViewModel!
    private var mockService: MockClipboardService!
    private var pasteMonitor: MockPasteCommandMonitor!

    override func setUp() {
        super.setUp()
        mockService = MockClipboardService()
        pasteMonitor = MockPasteCommandMonitor()
        viewModel = MainViewModel(
            clipboardService: mockService,
            pasteMonitor: pasteMonitor
        )
        mockService.history = (0..<5).map { index in
            ClipItem(content: "Item \(index)")
        }
        viewModel.loadHistory()
    }

    override func tearDown() {
        viewModel = nil
        mockService = nil
        pasteMonitor = nil
        super.tearDown()
    }

    func testEnqueueAddsItemsInOrder() {
        let items = Array(mockService.history.prefix(2))

        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: items, anchor: items.last)

        XCTAssertEqual(viewModel.pasteMode, .queueOnce)
        XCTAssertEqual(viewModel.pasteQueue, items.map(\.id))
        XCTAssertEqual(viewModel.queueBadge(for: items[0]), 1)
        XCTAssertEqual(viewModel.queueBadge(for: items[1]), 2)
    }

    func testEnqueueIgnoresDuplicatesAndAppends() {
        let items = Array(mockService.history.prefix(3))
        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: [items[0], items[1]], anchor: items[1])
        viewModel.queueSelection(items: [items[1], items[2]], anchor: items[2])

        XCTAssertEqual(viewModel.pasteQueue.count, 3)
        XCTAssertEqual(viewModel.pasteQueue, [items[0].id, items[1].id, items[2].id])
        XCTAssertEqual(viewModel.queueBadge(for: items[2]), 3)
    }

    func testHandleQueueSelectionWithShiftSelectsRange() {
        let items = Array(mockService.history.prefix(4))

        viewModel.toggleQueueMode()

        viewModel.handleQueueSelection(for: items[1], modifiers: [])
        viewModel.handleQueueSelection(for: items[3], modifiers: [.shift])
        let expectedPreview = Set([items[1], items[0], items[2], items[3]].map(\.id))
        XCTAssertEqual(viewModel.queueSelectionPreview, expectedPreview)
        XCTAssertEqual(viewModel.pasteQueue, [items[1].id])

        viewModel.handleModifierFlagsChanged([])

        XCTAssertTrue(viewModel.queueSelectionPreview.isEmpty)
        XCTAssertEqual(viewModel.pasteQueue, [items[0].id, items[2].id, items[3].id])
    }

    func testShiftSelectionTogglesExistingRange() {
        let items = Array(mockService.history.prefix(3))
        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: items, anchor: items.first)

        viewModel.handleQueueSelection(for: items[0], modifiers: [.shift])
        viewModel.handleQueueSelection(for: items[2], modifiers: [.shift])
        XCTAssertEqual(viewModel.queueSelectionPreview, Set(items.map(\.id)))

        viewModel.handleModifierFlagsChanged([])

        XCTAssertTrue(viewModel.pasteQueue.isEmpty)
        XCTAssertEqual(viewModel.pasteMode, .clipboard)
        XCTAssertTrue(viewModel.queueSelectionPreview.isEmpty)
    }

    func testShiftSelectionAddsAndRemovesMixedItems() {
        let items = Array(mockService.history.prefix(4))

        viewModel.toggleQueueMode()

        viewModel.handleQueueSelection(for: items[0], modifiers: [])
        viewModel.handleQueueSelection(for: items[3], modifiers: [.shift])

        XCTAssertEqual(viewModel.queueSelectionPreview, Set(items[0...3].map(\.id)))

        viewModel.handleModifierFlagsChanged([])

        XCTAssertEqual(viewModel.pasteQueue, [items[1].id, items[2].id, items[3].id])
        XCTAssertTrue(viewModel.queueSelectionPreview.isEmpty)
    }

    func testShiftSelectionAddsRangeAboveAnchorAnchorsFirst() {
        let items = Array(mockService.history.prefix(4))
        let baseline = [items[0], items[1], items[2], items[3]]

        let selection = viewModel.makeShiftSelectionRange(
            baselineItems: baseline,
            anchorIndex: 3,
            currentIndex: 1
        )

        XCTAssertEqual(selection.map(\.id), [items[3].id, items[2].id, items[1].id])
    }

    func testShiftSelectionFirstShiftClickShowsPreview() {
        let items = Array(mockService.history.prefix(3))

        viewModel.toggleQueueMode()

        viewModel.handleQueueSelection(for: items[1], modifiers: [.shift])

        XCTAssertEqual(viewModel.queueSelectionPreview, Set([items[1].id]))
        XCTAssertTrue(viewModel.pasteQueue.isEmpty)
    }

    func testShiftSelectionStartingWithShiftProducesRange() {
        let items = Array(mockService.history.prefix(4))

        viewModel.toggleQueueMode()

        viewModel.handleQueueSelection(for: items[3], modifiers: [.shift])
        XCTAssertEqual(viewModel.queueSelectionPreview, Set([items[3].id]))
        XCTAssertTrue(viewModel.pasteQueue.isEmpty)

        viewModel.handleQueueSelection(for: items[1], modifiers: [.shift])
        let expectedPreview = Set([items[3], items[2], items[1]].map(\.id))
        XCTAssertEqual(viewModel.queueSelectionPreview, expectedPreview)

        viewModel.handleModifierFlagsChanged([])

        XCTAssertEqual(viewModel.pasteQueue, [items[3].id, items[2].id, items[1].id])
        XCTAssertTrue(viewModel.queueSelectionPreview.isEmpty)
    }

    func testQueueBadgeReflectsShiftSelectionPreview() {
        let items = Array(mockService.history.prefix(3))

        viewModel.toggleQueueMode()

        viewModel.handleQueueSelection(for: items[0], modifiers: [])
        XCTAssertEqual(viewModel.queueBadge(for: items[0]), 1)

        viewModel.handleQueueSelection(for: items[2], modifiers: [.shift])

        XCTAssertNil(viewModel.queueBadge(for: items[0]))
        XCTAssertEqual(viewModel.queueBadge(for: items[1]), 1)
        XCTAssertEqual(viewModel.queueBadge(for: items[2]), 2)

        viewModel.handleModifierFlagsChanged([])

        XCTAssertNil(viewModel.queueBadge(for: items[0]))
        XCTAssertEqual(viewModel.queueBadge(for: items[1]), 1)
        XCTAssertEqual(viewModel.queueBadge(for: items[2]), 2)
        XCTAssertEqual(viewModel.pasteQueue, [items[1].id, items[2].id])
    }

    func testShiftSelectionUpwardOverExistingRangeRemovesIt() {
        let items = Array(mockService.history.prefix(4))

        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: items, anchor: items[3])

        viewModel.handleQueueSelection(for: items[1], modifiers: [.shift])

        let expectedPreview = Set([items[3], items[2], items[1]].map(\.id))
        XCTAssertEqual(viewModel.queueSelectionPreview, expectedPreview)

        viewModel.handleModifierFlagsChanged([])

        XCTAssertEqual(viewModel.pasteQueue, [items[0].id])
        XCTAssertTrue(viewModel.queueSelectionPreview.isEmpty)
    }

    func testQueueBadgeKeepsExistingOrderDuringPreview() {
        let items = Array(mockService.history.prefix(3))

        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: items, anchor: items.last)

        XCTAssertEqual(viewModel.queueBadge(for: items[0]), 1)
        XCTAssertEqual(viewModel.queueBadge(for: items[1]), 2)
        XCTAssertEqual(viewModel.queueBadge(for: items[2]), 3)

        viewModel.handleQueueSelection(for: items[0], modifiers: [.shift])

        XCTAssertNil(viewModel.queueBadge(for: items[0]))
        XCTAssertNil(viewModel.queueBadge(for: items[1]))
        XCTAssertNil(viewModel.queueBadge(for: items[2]))
    }

    func testShiftSelectionUpwardFromAnchorReordersQueue() {
        let items = Array(mockService.history.prefix(4))

        viewModel.toggleQueueMode()

        viewModel.handleQueueSelection(for: items[0], modifiers: [])
        viewModel.handleQueueSelection(for: items[1], modifiers: [])
        XCTAssertEqual(viewModel.pasteQueue, [items[0].id, items[1].id])

        viewModel.handleQueueSelection(for: items[0], modifiers: [.shift])

        let expectedPreview = Set([items[1], items[0]].map(\.id))
        XCTAssertEqual(viewModel.queueSelectionPreview, expectedPreview)
        XCTAssertEqual(viewModel.pasteQueue, [items[0].id, items[1].id])

        viewModel.handleModifierFlagsChanged([])

        XCTAssertTrue(viewModel.pasteQueue.isEmpty)
        XCTAssertEqual(viewModel.pasteMode, .clipboard)
        XCTAssertTrue(viewModel.queueSelectionPreview.isEmpty)
    }

    func testShiftSelectionWithQueuedAnchorUsesDisplayOrderRange() {
        let items = Array(mockService.history.prefix(5))

        viewModel.toggleQueueMode()

        viewModel.handleQueueSelection(for: items[3], modifiers: [])
        XCTAssertEqual(viewModel.pasteQueue, [items[3].id])

        viewModel.handleQueueSelection(for: items[4], modifiers: [.shift])

        let expectedPreview = Set([items[3], items[0], items[1], items[2], items[4]].map(\.id))
        XCTAssertEqual(viewModel.queueSelectionPreview, expectedPreview)

        viewModel.handleModifierFlagsChanged([])

        XCTAssertEqual(viewModel.pasteQueue, [items[0].id, items[1].id, items[2].id, items[4].id])
        XCTAssertTrue(viewModel.queueSelectionPreview.isEmpty)
    }
    func testQueueSelectionStartsMonitoringAndCopiesFirstItem() {
        let items = Array(mockService.history.prefix(2))

        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: items, anchor: items.last)

        XCTAssertTrue(pasteMonitor.isMonitoring)
        XCTAssertEqual(mockService.lastRecopiedItem?.id, items[0].id)
    }

    func testQueueSelectionIgnoredWhenPermissionMissing() {
        pasteMonitor.hasAccessibilityPermission = false
        let items = Array(mockService.history.prefix(2))

        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: items, anchor: items.last)

        XCTAssertTrue(viewModel.pasteQueue.isEmpty)
        XCTAssertEqual(viewModel.pasteMode, .clipboard)
        XCTAssertFalse(pasteMonitor.isMonitoring)
    }

    func testQueueSelectionIgnoredWhenQueueModeDisabled() {
        let target = mockService.history[0]

        viewModel.handleQueueSelection(for: target, modifiers: [])

        XCTAssertTrue(viewModel.pasteQueue.isEmpty)
        XCTAssertEqual(viewModel.pasteMode, .clipboard)
    }

    func testToggleQueueModePausesAndResumesAutoClear() {
        viewModel.toggleQueueMode()

        XCTAssertTrue(mockService.pauseAutoClearCalled)

        viewModel.toggleQueueMode()

        XCTAssertTrue(mockService.resumeAutoClearCalled)
    }

    func testExternalCopyWhileQueueModeActiveResetsQueue() {
        let items = Array(mockService.history.prefix(2))

        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: items, anchor: items.last)

        mockService.copyToClipboard("External Copy", fromEditor: false)

        XCTAssertTrue(viewModel.pasteQueue.isEmpty)
        XCTAssertEqual(viewModel.pasteMode, .clipboard)
        XCTAssertTrue(mockService.resumeAutoClearCalled)
    }

    func testPasteCommandAdvancesQueueInQueueMode() async {
        let items = Array(mockService.history.prefix(2))
        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: items, anchor: items.last)

        pasteMonitor.simulatePasteCommand()

        await Task.yield()

        XCTAssertEqual(viewModel.pasteQueue, [items[1].id])
        XCTAssertEqual(mockService.lastRecopiedItem?.id, items[1].id)
    }

    func testPasteCommandCyclesQueueInToggleMode() async {
        let items = Array(mockService.history.prefix(2))
        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: items, anchor: items.last)
        viewModel.toggleQueueRepetition()

        pasteMonitor.simulatePasteCommand()

        await Task.yield()

        XCTAssertEqual(viewModel.pasteQueue, [items[1].id, items[0].id])
        XCTAssertEqual(mockService.lastRecopiedItem?.id, items[1].id)
    }

    func testResetPasteQueueClearsStateAndStopsMonitoring() {
        let items = Array(mockService.history.prefix(2))
        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: items, anchor: items.last)

        viewModel.resetPasteQueue()

        XCTAssertEqual(viewModel.pasteMode, .clipboard)
        XCTAssertTrue(viewModel.pasteQueue.isEmpty)
        XCTAssertFalse(pasteMonitor.isMonitoring)
        XCTAssertTrue(mockService.resumeAutoClearCalled)
    }

    func testPasteCommandUntilQueueEmptiesStopsMonitoring() async {
        let items = Array(mockService.history.prefix(2))
        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: items, anchor: items.last)

        pasteMonitor.simulatePasteCommand()
        await Task.yield()
        pasteMonitor.simulatePasteCommand()
        await Task.yield()

        XCTAssertTrue(viewModel.pasteQueue.isEmpty)
        XCTAssertFalse(pasteMonitor.isMonitoring)
        XCTAssertEqual(viewModel.pasteMode, .clipboard)
    }

    func testUpdateFilteredItemsRespectsQueueOrdering() {
        let items = mockService.history
        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: [items[2], items[0]], anchor: items[0])
        viewModel.loadHistory()

        XCTAssertEqual(viewModel.history.prefix(2).map(\.id), [items[2].id, items[0].id])
    }

    func testQueueOnceCompletionClearsClipboardAndResumesAutoClear() async {
        let items = Array(mockService.history.prefix(2))

        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: items, anchor: items.last)

        pasteMonitor.simulatePasteCommand()
        await Task.yield()
        pasteMonitor.simulatePasteCommand()
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(viewModel.pasteQueue.isEmpty)
        XCTAssertEqual(viewModel.pasteMode, .clipboard)
        XCTAssertNil(mockService.currentClipboardContent)
        XCTAssertTrue(mockService.resumeAutoClearCalled)
    }

    func testManualCopyClearsQueueAndReturnsToClipboardMode() {
        let items = Array(mockService.history.prefix(2))

        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: [items[0]], anchor: items[0])

        viewModel.selectHistoryItem(items[1])

        XCTAssertTrue(viewModel.pasteQueue.isEmpty)
        XCTAssertEqual(viewModel.pasteMode, .clipboard)
        XCTAssertTrue(mockService.resumeAutoClearCalled)
    }
    func testShiftSelectionMixedQueueAndNewItemsRemovesQueuedOnes() {
        let items = Array(mockService.history.prefix(4))

        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: Array(items[0...1]), anchor: items[1])

        viewModel.handleQueueSelection(for: items[3], modifiers: [.shift])

        XCTAssertEqual(viewModel.queueBadge(for: items[0]), 1)
        XCTAssertNil(viewModel.queueBadge(for: items[1]))
        XCTAssertEqual(viewModel.queueBadge(for: items[2]), 2)
        XCTAssertEqual(viewModel.queueBadge(for: items[3]), 3)

        viewModel.handleModifierFlagsChanged([])

        XCTAssertEqual(viewModel.pasteQueue, [items[0].id, items[2].id, items[3].id])
    }
}

private final class MockPasteCommandMonitor: PasteCommandMonitoring {
    private var handler: (() -> Void)?
    private(set) var isMonitoring = false
    var hasAccessibilityPermission: Bool = true

    func start(handler: @escaping () -> Void) -> Bool {
        guard hasAccessibilityPermission else { return false }
        self.handler = handler
        isMonitoring = true
        return true
    }

    func stop() {
        handler = nil
        isMonitoring = false
    }

    func simulatePasteCommand() {
        handler?()
    }
}
