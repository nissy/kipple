import AppKit
import XCTest
@testable import Kipple

@MainActor
final class PlainTextPasteIntegrationTests: XCTestCase {
    func testQueueKeepsFirstItemUntilSlowReceiverReads() async throws {
        try await verifyQueueReception(count: 2)
    }

    func testLastQueueItemSurvivesUntilSlowReceiverReads() async throws {
        try await verifyQueueReception(count: 1)
    }

    func testAlternatingPlainAndRichPasteCopiesOnlyOnTheNextRequest() async throws {
        try await verifyQueueSequence(styles: [true, false, true], repeats: false)
    }

    func testLoopingQueuePreservesEachRequestedStyle() async throws {
        try await verifyQueueSequence(styles: [false, true, false], repeats: true)
    }

    private func verifyQueueSequence(styles: [Bool], repeats: Bool) async throws {
        let items = try ["Queue A", "Queue B", "Queue C"].prefix(repeats ? 2 : 3).map(putStyledItem)
        let repository = MockClipboardRepository()
        await repository.configure(items: items, loadDelay: 0)
        let service = ModernClipboardService(testRepository: repository)
        await service.loadHistoryFromRepository()
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        await adapter.refreshHistoryForTesting()
        let viewModel = MainViewModel(clipboardService: adapter, pasteMonitor: IntegrationPasteCommandMonitor())
        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: items, anchor: items.last)
        if repeats { viewModel.toggleQueueRepetition() }
        await adapter.flushPendingAdapterOperationForTesting()
        var received: [String] = []
        let controller = PlainTextPasteController(
            clipboardService: adapter, isTargetActive: { _ in true }, sendPaste: { _ in
                received.append(NSPasteboard.general.string(forType: .string) ?? "")
                return true
            }
        )
        viewModel.connectPasteController(controller)
        for (index, plain) in styles.enumerated() {
            controller.paste(into: 101, removingFormatting: plain)
            await controller.waitForPendingPastes()
            let expected = items[index % items.count]
            let count = NSPasteboard.general.changeCount
            // Completing the logical queue must not clear or preload the next item, however late the read.
            try await Task.sleep(for: .milliseconds(650))
            XCTAssertEqual(NSPasteboard.general.changeCount, count)
            XCTAssertEqual(NSPasteboard.general.string(forType: .string), expected.content)
            XCTAssertEqual(ClipboardRichText(pasteboard: .general), plain ? nil : expected.richText)
            let saved = await service.getHistory().first
            XCTAssertEqual(saved?.id, expected.id)
            XCTAssertEqual(saved?.richText, expected.richText, "Plain paste must retain the rich history entry")
            XCTAssertGreaterThan(try XCTUnwrap(saved?.timestamp), expected.timestamp)
        }
        XCTAssertEqual(received, styles.indices.map { items[$0 % items.count].content })
        XCTAssertEqual(viewModel.pasteQueue, repeats ? [items[1].id, items[0].id] : [])
        viewModel.resetPasteQueue()
    }

    private func verifyQueueReception(count: Int) async throws {
        let first = try putStyledItem("Queue A")
        let second = try putStyledItem("Queue B")
        let items = Array([first, second].prefix(count))
        let repository = MockClipboardRepository()
        await repository.configure(items: items, loadDelay: 0)
        let service = ModernClipboardService(testRepository: repository)
        await service.loadHistoryFromRepository()
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        await adapter.refreshHistoryForTesting()
        let viewModel = MainViewModel(clipboardService: adapter, pasteMonitor: IntegrationPasteCommandMonitor())
        viewModel.toggleQueueMode()
        viewModel.queueSelection(items: items, anchor: items.last)
        await adapter.recopyFromHistoryAndWait(first)
        XCTAssertEqual(viewModel.nextQueuedItem()?.id, first.id)
        let read = expectation(description: "Receiver reads clipboard after 650ms")
        let controller = PlainTextPasteController(
            clipboardService: adapter, isTargetActive: { _ in true }, sendPaste: { _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(650))
                    XCTAssertEqual(NSPasteboard.general.string(forType: .string), first.content)
                    XCTAssertNil(ClipboardRichText(pasteboard: .general))
                    read.fulfill()
                }
                return true
            }
        )
        viewModel.connectPasteController(controller)
        controller.paste(into: 101)
        await controller.waitForPendingPastes()
        await fulfillment(of: [read], timeout: 3)
        XCTAssertEqual(viewModel.pasteQueue, Array(items.dropFirst()).map(\.id))
        viewModel.resetPasteQueue()
    }

    func testFailedHistoryLoadDoesNotDiscardOnlyRemainingFormatting() async throws {
        let original = try putStyledItem("Original styled text")
        let repository = MockClipboardRepository()
        await repository.failNextLoads(1)
        let service = ModernClipboardService(testRepository: repository, loadOnStartup: true)
        await service.startMonitoring()
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        let controller = PlainTextPasteController(
            clipboardService: adapter, isTargetActive: { _ in true }, sendPaste: { _ in
                XCTFail("Paste must stop when the original formatting cannot be saved")
                return true
            }
        )
        var failures: [PlainTextPasteController.Failure] = []
        controller.onFailure = { failures.append($0) }
        controller.paste(into: 101)
        await controller.waitForPendingPastes()
        let history = await service.getHistory()
        let originalWasPreserved = history.contains { $0.richText == original.richText }
            || ClipboardRichText(pasteboard: .general) == original.richText
        XCTAssertTrue(originalWasPreserved, "Original formatting must survive in history or on the clipboard")
        XCTAssertEqual(failures, [.historyUnavailable])
        XCTAssertEqual(ClipboardRichText(pasteboard: .general), original.richText)
        await service.stopMonitoring()
    }

    func testMCPInvalidationAlsoCancelsSecondQueuedShortcut() async throws {
        _ = try putStyledItem("Old clipboard")
        let repository = MockClipboardRepository()
        let loading = expectation(description: "Initial load is suspended")
        await repository.suspendLoad { loading.fulfill() }
        let service = ModernClipboardService(testRepository: repository, loadOnStartup: true)
        await fulfillment(of: [loading], timeout: 2)
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        var pasted: [String] = []
        let controller = PlainTextPasteController(
            clipboardService: adapter, isTargetActive: { _ in true }, sendPaste: { _ in
                pasted.append(NSPasteboard.general.string(forType: .string) ?? "<empty>")
                return true
            }
        )
        let mcpCopy = Task { await service.copyMCPConfiguration("New MCP content") { true } }
        try await Task.sleep(for: .milliseconds(40))
        controller.paste(into: 101)
        controller.paste(into: 101)
        try await Task.sleep(for: .milliseconds(40))
        await repository.resumeLoad()
        let copied = await mcpCopy.value
        XCTAssertTrue(copied)
        await controller.waitForPendingPastes()
        XCTAssertEqual(pasted, [], "All shortcuts queued before the MCP copy must be invalidated together")
        controller.paste(into: 101)
        await controller.waitForPendingPastes()
        XCTAssertEqual(pasted, ["New MCP content"])
    }

    private func putStyledItem(_ text: String) throws -> ClipItem {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        NSPasteboard.general.setString("<b>\(text)</b>", forType: .html)
        return ClipItem(content: text, richText: try XCTUnwrap(ClipboardRichText(pasteboard: .general)))
    }
}

private final class IntegrationPasteCommandMonitor: PasteCommandMonitoring {
    var isMonitoring = false
    var hasPermission = true
    func start(handler: @escaping () -> Void) -> Bool { isMonitoring = true; return true }
    func stop() { isMonitoring = false }
}
