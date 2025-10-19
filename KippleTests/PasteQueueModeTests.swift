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

        viewModel.queueSelection(items: items, anchor: items.last)

        XCTAssertEqual(viewModel.pasteMode, .queueOnce)
        XCTAssertEqual(viewModel.pasteQueue, items.map(\.id))
        XCTAssertEqual(viewModel.queueBadge(for: items[0]), 1)
        XCTAssertEqual(viewModel.queueBadge(for: items[1]), 2)
    }

    func testEnqueueIgnoresDuplicatesAndAppends() {
        let items = Array(mockService.history.prefix(3))
        viewModel.queueSelection(items: [items[0], items[1]], anchor: items[1])
        viewModel.queueSelection(items: [items[1], items[2]], anchor: items[2])

        XCTAssertEqual(viewModel.pasteQueue.count, 3)
        XCTAssertEqual(viewModel.pasteQueue, [items[0].id, items[1].id, items[2].id])
        XCTAssertEqual(viewModel.queueBadge(for: items[2]), 3)
    }

    func testHandleQueueSelectionWithShiftSelectsRange() {
        let items = Array(mockService.history.prefix(4))

        viewModel.handleQueueSelection(for: items[1], modifiers: [.command])
        viewModel.handleQueueSelection(for: items[3], modifiers: [.command, .shift])
        let expectedPreview = Set([items[1], items[0], items[2], items[3]].map(\.id))
        XCTAssertEqual(viewModel.queueSelectionPreview, expectedPreview)
        XCTAssertEqual(viewModel.pasteQueue, [items[1].id])

        viewModel.handleModifierFlagsChanged([.command])

        XCTAssertTrue(viewModel.queueSelectionPreview.isEmpty)
        XCTAssertEqual(viewModel.pasteQueue, [items[0].id, items[2].id, items[3].id])
        XCTAssertFalse(viewModel.pasteQueue.contains(items[1].id))
    }

    func testShiftSelectionTogglesExistingRange() {
        let items = Array(mockService.history.prefix(3))
        viewModel.queueSelection(items: items, anchor: items.first)

        viewModel.handleQueueSelection(for: items[0], modifiers: [.command, .shift])
        viewModel.handleQueueSelection(for: items[2], modifiers: [.command, .shift])
        XCTAssertEqual(viewModel.queueSelectionPreview, Set(items.map(\.id)))

        viewModel.handleModifierFlagsChanged([.command])

        XCTAssertTrue(viewModel.pasteQueue.isEmpty)
        XCTAssertEqual(viewModel.pasteMode, .clipboard)
        XCTAssertTrue(viewModel.queueSelectionPreview.isEmpty)
    }

    func testShiftSelectionAddsAndRemovesMixedItems() {
        let items = Array(mockService.history.prefix(4))

        viewModel.handleQueueSelection(for: items[0], modifiers: [.command])
        viewModel.handleQueueSelection(for: items[3], modifiers: [.command, .shift])

        XCTAssertEqual(viewModel.queueSelectionPreview, Set(items[0...3].map(\.id)))

        viewModel.handleModifierFlagsChanged([.command])

        XCTAssertEqual(Set(viewModel.pasteQueue), Set([items[1].id, items[2].id, items[3].id]))
        XCTAssertFalse(viewModel.pasteQueue.contains(items[0].id))
        XCTAssertTrue(viewModel.queueSelectionPreview.isEmpty)
    }

    func testShiftSelectionIgnoresItemsAboveAnchor() {
        let items = Array(mockService.history.prefix(4))

        viewModel.handleQueueSelection(for: items[0], modifiers: [.command])
        viewModel.handleQueueSelection(for: items[1], modifiers: [.command])
        XCTAssertEqual(viewModel.pasteQueue, [items[0].id, items[1].id])

        viewModel.handleQueueSelection(for: items[0], modifiers: [.command, .shift])

        XCTAssertTrue(viewModel.queueSelectionPreview.isEmpty)
        XCTAssertEqual(viewModel.pasteQueue, [items[0].id, items[1].id])

        viewModel.handleModifierFlagsChanged([.command])

        XCTAssertEqual(viewModel.pasteQueue, [items[0].id, items[1].id])
        XCTAssertTrue(viewModel.queueSelectionPreview.isEmpty)
    }

    func testShiftSelectionRecoversAfterIgnoringUpwardSelection() {
        let items = Array(mockService.history.prefix(5))

        viewModel.handleQueueSelection(for: items[0], modifiers: [.command])
        viewModel.handleQueueSelection(for: items[1], modifiers: [.command])
        XCTAssertEqual(viewModel.pasteQueue, [items[0].id, items[1].id])

        viewModel.handleQueueSelection(for: items[0], modifiers: [.command, .shift])

        XCTAssertTrue(viewModel.queueSelectionPreview.isEmpty)
        XCTAssertEqual(viewModel.pasteQueue, [items[0].id, items[1].id])

        viewModel.handleQueueSelection(for: items[4], modifiers: [.command, .shift])
        let expectedPreview = Set([items[1], items[2], items[3], items[4]].map(\.id))
        XCTAssertEqual(viewModel.queueSelectionPreview, expectedPreview)

        viewModel.handleModifierFlagsChanged([.command])

        XCTAssertEqual(viewModel.pasteQueue, [items[0].id, items[2].id, items[3].id, items[4].id])
        XCTAssertTrue(viewModel.queueSelectionPreview.isEmpty)
    }

    func testShiftSelectionWithQueuedAnchorUsesDisplayOrderRange() {
        let items = Array(mockService.history.prefix(5))

        viewModel.handleQueueSelection(for: items[3], modifiers: [.command])
        XCTAssertEqual(viewModel.pasteQueue, [items[3].id])

        viewModel.handleQueueSelection(for: items[4], modifiers: [.command, .shift])

        let expectedPreview = Set([items[3], items[0], items[1], items[2], items[4]].map(\.id))
        XCTAssertEqual(viewModel.queueSelectionPreview, expectedPreview)

        viewModel.handleModifierFlagsChanged([.command])

        XCTAssertFalse(viewModel.pasteQueue.contains(items[3].id))
        XCTAssertEqual(viewModel.pasteQueue, [items[0].id, items[1].id, items[2].id, items[4].id])
        XCTAssertTrue(viewModel.queueSelectionPreview.isEmpty)
    }
    func testQueueSelectionStartsMonitoringAndCopiesFirstItem() {
        let items = Array(mockService.history.prefix(2))

        viewModel.queueSelection(items: items, anchor: items.last)

        XCTAssertTrue(pasteMonitor.isMonitoring)
        XCTAssertEqual(mockService.lastRecopiedItem?.id, items[0].id)
    }

    func testQueueSelectionIgnoredWhenPermissionMissing() {
        pasteMonitor.hasAccessibilityPermission = false
        let items = Array(mockService.history.prefix(2))

        viewModel.queueSelection(items: items, anchor: items.last)

        XCTAssertTrue(viewModel.pasteQueue.isEmpty)
        XCTAssertEqual(viewModel.pasteMode, .clipboard)
        XCTAssertFalse(pasteMonitor.isMonitoring)
    }

    func testPasteCommandAdvancesQueueInQueueMode() async {
        let items = Array(mockService.history.prefix(2))
        viewModel.queueSelection(items: items, anchor: items.last)

        pasteMonitor.simulatePasteCommand()

        await Task.yield()

        XCTAssertEqual(viewModel.pasteQueue, [items[1].id])
        XCTAssertEqual(mockService.lastRecopiedItem?.id, items[1].id)
    }

    func testPasteCommandCyclesQueueInToggleMode() async {
        let items = Array(mockService.history.prefix(2))
        viewModel.queueSelection(items: items, anchor: items.last)
        viewModel.togglePasteMode()

        pasteMonitor.simulatePasteCommand()

        await Task.yield()

        XCTAssertEqual(viewModel.pasteQueue, [items[1].id, items[0].id])
        XCTAssertEqual(mockService.lastRecopiedItem?.id, items[1].id)
    }

    func testResetPasteQueueClearsStateAndStopsMonitoring() {
        let items = Array(mockService.history.prefix(2))
        viewModel.queueSelection(items: items, anchor: items.last)

        viewModel.resetPasteQueue()

        XCTAssertEqual(viewModel.pasteMode, .clipboard)
        XCTAssertTrue(viewModel.pasteQueue.isEmpty)
        XCTAssertFalse(pasteMonitor.isMonitoring)
    }

    func testPasteCommandUntilQueueEmptiesStopsMonitoring() async {
        let items = Array(mockService.history.prefix(2))
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
        viewModel.queueSelection(items: [items[2], items[0]], anchor: items[0])
        viewModel.loadHistory()

        XCTAssertEqual(viewModel.history.prefix(2).map(\.id), [items[2].id, items[0].id])
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
