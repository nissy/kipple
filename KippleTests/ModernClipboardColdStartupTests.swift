import AppKit
import XCTest
@testable import Kipple

@MainActor
final class ModernClipboardColdStartupTests: XCTestCase {
    func testFirstOCRCopySurvivesColdStartupAndIsPersistedThirtyTimes() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        for index in 0..<30 {
            let repository = MockClipboardRepository()
            let existing = ClipItem(content: "Saved history")
            await repository.configure(items: [existing], loadDelay: 0)
            let service = makeService(repository: repository, pasteboard: pasteboard)
            let content = "First OCR copy \(index)"
            let copiedID = await service.copyRecognizedText(content) { true }
            XCTAssertNotNil(copiedID)
            XCTAssertEqual(pasteboard.string(forType: .string), content)
            let history = await service.getHistory()
            XCTAssertEqual(history.count, 2)
            XCTAssertEqual(history.first?.id, copiedID)
            XCTAssertEqual(history.first?.content, content)
            XCTAssertEqual(history.first?.metadata?.source, .ocr)
            XCTAssertNil(history.first?.sourceApp)
            XCTAssertNil(history.first?.bundleIdentifier)
            XCTAssertNil(history.first?.processID)
            XCTAssertNil(history.first?.windowTitle)
            XCTAssertTrue(history.contains { $0.id == existing.id })
            await service.flushPendingSaves()
            let persisted = try await repository.loadAll()
            XCTAssertTrue(persisted.contains { $0.content == content })
        }
    }

    func testCancellingCopyDuringStartupDoesNotWriteOrCancelInitialization() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let repository = MockClipboardRepository()
        let existing = ClipItem(content: "Saved history")
        await repository.configure(items: [existing], loadDelay: 0)
        let started = expectation(description: "initial load started")
        await repository.suspendLoad { started.fulfill() }
        let service = makeService(repository: repository, pasteboard: pasteboard)
        await fulfillment(of: [started], timeout: 1)
        let copy = Task { await service.copyToClipboard("Cancelled OCR", fromEditor: false, source: .ocr) { true } }
        copy.cancel()
        await repository.resumeLoad()
        let copied = await copy.value
        XCTAssertFalse(copied)
        XCTAssertNil(pasteboard.string(forType: .string))
        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.id), [existing.id])
        let nextCopy = await service.copyToClipboard("Next OCR", fromEditor: false, source: .ocr) { true }
        XCTAssertTrue(nextCopy)
    }

    func testFailedInitialLoadRejectsCopyAndCanRecoverWithoutLosingSavedHistory() async throws {
        let repository = MockClipboardRepository()
        var categorized = ClipItem(content: "Saved categorized item")
        categorized.setCategory(savedHistoryCategoryID, enabled: true)
        await repository.configure(items: [categorized], loadDelay: 0)
        await repository.failNextLoads(2)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let service = makeService(repository: repository, pasteboard: pasteboard)
        let failed = await service.copyToClipboard("OCR while loading fails", fromEditor: false, source: .ocr) { true }
        XCTAssertFalse(failed)
        XCTAssertNil(pasteboard.string(forType: .string))
        let partialHistory = await service.getHistory()
        XCTAssertTrue(partialHistory.isEmpty)
        await service.flushPendingSaves()
        let saved = try await repository.loadAll()
        XCTAssertEqual(saved.map(\.id), [categorized.id])

        let recovered = await service.copyToClipboard("OCR after recovery", fromEditor: false, source: .ocr) { true }
        XCTAssertTrue(recovered)
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertTrue(history.contains { $0.id == categorized.id })
    }

    func testPasteboardWriteFailureIsReturnedWithoutAddingOCRHistory() async {
        let repository = MockClipboardRepository()
        let service = ModernClipboardService(testRepository: repository, loadOnStartup: true) { _ in -1 }
        let copied = await service.copyToClipboard("Failed OCR", fromEditor: false, source: .ocr) { true }
        XCTAssertFalse(copied)
        let history = await service.getHistory()
        XCTAssertTrue(history.isEmpty)
    }

    func testInitialPartialHistoryDoesNotReorderExistingCategoryFilters() async throws {
        let suite = "ColdStartupCategoryOrderTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserCategoryStore(defaults: defaults)
        store.add(name: "Saved", iconSystemName: "tag", id: savedHistoryCategoryID)
        let originalOrder = store.orderedForFiltering().map(\.id)
        let saved = ClipItem(content: "Memo", userCategoryId: savedHistoryCategoryID)
        let url = ClipItem(content: "https://example.com")
        let repository = MockClipboardRepository()
        await repository.configure(items: [saved, url], loadDelay: 0)
        let loadingRecent = expectation(description: "recent history load suspended")
        await repository.suspendLoad { loadingRecent.fulfill() }
        let service = ModernClipboardService(testRepository: repository, loadOnStartup: true, categoryStore: store)
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        let model = MainViewModel(clipboardService: adapter, categoryStore: store)

        await fulfillment(of: [loadingRecent], timeout: 1)
        await adapter.refreshHistoryForTesting()
        XCTAssertFalse(adapter.isHistoryLoaded)
        XCTAssertEqual(model.historyCategoryIDs, [savedHistoryCategoryID])
        XCTAssertEqual(store.orderedForFiltering().map(\.id), originalOrder)

        await repository.resumeLoad()
        await service.flushPendingSaves()
        await adapter.refreshHistoryForTesting()
        XCTAssertTrue(adapter.isHistoryLoaded)
        XCTAssertEqual(model.historyCategoryIDs, [BuiltInCategory.url, savedHistoryCategoryID])
        XCTAssertEqual(store.orderedForFiltering().map(\.id), originalOrder)
    }

    private func makeService(repository: MockClipboardRepository, pasteboard: NSPasteboard) -> ModernClipboardService {
        ModernClipboardService(testRepository: repository, loadOnStartup: true) { content in
            pasteboard.clearContents()
            return pasteboard.setString(content.content, forType: .string) ? pasteboard.changeCount : -1
        }
    }
}
