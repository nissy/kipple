import AppKit
import SwiftData
import XCTest
@testable import Kipple

final class MultipleCategoryTests: XCTestCase, @unchecked Sendable {
    func testAutomaticCategoriesCombineWithManualCategories() {
        let custom = UUID()
        var item = ClipItem(content: "https://example.com", userCategoryId: custom,
                            metadata: ClipMetadata(source: .ocr))
        XCTAssertEqual(item.categoryIDs, [custom, BuiltInCategory.url, BuiltInCategory.ocr])
        item.setCategory(BuiltInCategory.ai, enabled: true)
        XCTAssertTrue(item.categoryIDs.contains(BuiltInCategory.ai))
        XCTAssertEqual(item.metadata?.sources, [.ocr], "Manual AI assignment must not fabricate MCP provenance")
    }

    func testLegacyNoneAndLegacyMetadataRemainReadable() throws {
        let oldData = Data("{\"source\":\"mcp\",\"title\":\"Legacy\"}".utf8)
        let metadata = try JSONDecoder().decode(ClipMetadata.self, from: oldData)
        var item = ClipItem(content: "https://example.com", userCategoryId: BuiltInCategory.none, metadata: metadata)
        XCTAssertTrue(item.categoryIDs.isEmpty)
        item.setCategory(BuiltInCategory.ai, enabled: true)
        XCTAssertEqual(item.categoryIDs, [BuiltInCategory.ai])
        XCTAssertEqual(item.title, "Legacy")
        XCTAssertEqual(item.metadata?.sources, [.mcp])
    }

    func testRemovingAutomaticCategorySurvivesCodingAndDuplicateImport() throws {
        var item = ClipItem(content: "https://example.com", metadata: ClipMetadata(source: .ocr))
        item.setCategory(BuiltInCategory.url, enabled: false)
        item.setCategory(BuiltInCategory.ocr, enabled: false)
        let decoded = try JSONDecoder().decode(ClipItem.self, from: JSONEncoder().encode(item))
        var imported = ClipItem(content: item.content, metadata: ClipMetadata(source: .mcp))
        imported.metadata = imported.metadata?.inheritingDetails(from: decoded.metadata)
        XCTAssertEqual(imported.categoryIDs, [BuiltInCategory.ai])
        XCTAssertEqual(imported.metadata?.sources, [.mcp, .ocr])
        imported.setCategory(BuiltInCategory.url, enabled: true)
        XCTAssertEqual(imported.categoryIDs, [BuiltInCategory.url, BuiltInCategory.ai])
    }

    func testMatchAllAnyAndUncategorized() {
        let item = ClipItem(content: "https://example.com", metadata: ClipMetadata(source: .ocr))
        var filter = CategoryFilter(ids: [BuiltInCategory.url, BuiltInCategory.ocr])
        XCTAssertTrue(filter.includes(item))
        filter.toggle(BuiltInCategory.ai)
        XCTAssertFalse(filter.includes(item))
        filter.match = .any
        XCTAssertTrue(filter.includes(item))
        filter.toggle(BuiltInCategory.none)
        XCTAssertEqual(filter.ids, [BuiltInCategory.none])
        XCTAssertFalse(filter.includes(item))
        XCTAssertTrue(filter.includes(ClipItem(content: "memo")))
        filter.toggle(BuiltInCategory.url)
        XCTAssertEqual(filter.ids, [BuiltInCategory.url])
    }

    @MainActor
    func testSavedCategoryKeepsAnIconRemovedFromThePicker() throws {
        let suite = "CategoryIconsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let saved = UserCategory(name: "Travel", iconSystemName: "tram")
        defaults.set(try JSONEncoder().encode([saved]), forKey: "userCategories.v1")

        let store = UserCategoryStore(defaults: defaults)
        let reopened = try XCTUnwrap(store.category(id: saved.id))
        XCTAssertFalse(UserCategoryStore.availableSymbols.contains(saved.iconSystemName))
        XCTAssertEqual(store.iconName(for: reopened), saved.iconSystemName)

        store.changeIcon(id: saved.id, to: "graduationcap")
        XCTAssertEqual(UserCategoryStore(defaults: defaults).category(id: saved.id)?.iconSystemName, "graduationcap")
    }

    @MainActor
    func testCategoryIconMenuSymbolsHaveDistinctLocalizedTitles() throws {
        let symbols = UserCategoryStore.availableSymbols
        XCTAssertFalse(symbols.isEmpty)
        XCTAssertEqual(Set(symbols).count, symbols.count)

        let keys = symbols.map(UserCategoryStore.iconTitleKey(for:))
        for language in ["ja", "en"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            let titles = keys.map { bundle.localizedString(forKey: $0, value: nil, table: nil) }
            let missing = zip(keys, titles).filter { key, title in title.isEmpty || title == key }.map(\.0)

            XCTAssertTrue(missing.isEmpty, "Missing \(language) icon names: \(missing)")
            XCTAssertEqual(Set(titles).count, symbols.count, "Duplicate \(language) icon names")
        }
    }

    @MainActor
    func testFilterOrderPersistsWhileHiddenCategoriesKeepTheirSlots() throws {
        let suite = "CategoryFilterOrderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = UserCategoryStore(defaults: defaults)
        store.add(name: "Memo", iconSystemName: "doc.text")
        let memo = try XCTUnwrap(store.userDefined().first?.id)
        let url = BuiltInCategory.url
        let ocr = BuiltInCategory.ocr
        let ai = BuiltInCategory.ai
        let none = BuiltInCategory.none
        XCTAssertEqual(store.orderedForFiltering().map(\.id), [url, ocr, ai, memo, none])

        store.moveFilter(memo, to: url, among: [url, memo, none])
        XCTAssertEqual(store.orderedForFiltering().map(\.id), [memo, ocr, ai, url, none])

        let reopened = UserCategoryStore(defaults: defaults)
        XCTAssertEqual(reopened.orderedForFiltering().map(\.id), [memo, ocr, ai, url, none])
        reopened.moveFilter(none, to: memo, among: [memo, url, none])
        XCTAssertEqual(reopened.orderedForFiltering().map(\.id), [none, ocr, ai, memo, url])
        reopened.remove(id: memo)
        XCTAssertEqual(UserCategoryStore(defaults: defaults).orderedForFiltering().map(\.id), [none, ocr, ai, url])
    }

    func testEditsSurviveRecopyMCPAndRestartWithoutReplacingOtherDetails() async throws {
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository)
        let custom = UUID()
        await service.copyToClipboard("https://example.com", fromEditor: false, source: .ocr) { true }
        let initialHistory = await service.getHistory()
        let original = try XCTUnwrap(initialHistory.first)
        try await service.setCategory(itemID: original.id, categoryID: BuiltInCategory.ocr, enabled: false)
        try await service.setCategory(itemID: original.id, categoryID: custom, enabled: true)
        await service.recopyFromHistory(original) // Deliberately stale UI snapshot.
        let imported = ClipItem(content: original.content, metadata: ClipMetadata(title: "MCP title", source: .mcp))
        let requestID = UUID()
        let record = MCPStoredReceipt(key: requestID.uuidString, digest: Data([1]), receivedAt: Date(),
                                      result: MCPReceipt(requestId: requestID, status: "clipboard_unknown"))
        _ = try await service.registerMCP([imported], record: record)
        await service.flushPendingSaves()
        let restarted = ModernClipboardService(testRepository: repository)
        await restarted.loadHistoryFromRepository()
        let history = await restarted.getHistory()
        let saved = try XCTUnwrap(history.first)
        XCTAssertEqual(saved.id, original.id)
        XCTAssertTrue(saved.hasCustomCategory)
        XCTAssertEqual(saved.categoryIDs, [custom, BuiltInCategory.url, BuiltInCategory.ai])
        XCTAssertEqual(saved.title, "MCP title")
        XCTAssertEqual(saved.metadata?.sources, [.ocr, .mcp])
    }

    func testHistoryCleanupKeepsItemsUntilTheirLastCustomCategoryIsRemoved() async throws {
        let repository = try SwiftDataRepository.make(inMemory: true)
        let template = ClipItem(content: "Template")
        var builtIn = ClipItem(content: "Built-in only")
        builtIn.setCategory(BuiltInCategory.ai, enabled: true)
        var recent = ClipItem(content: "Recent")
        recent.timestamp = Date().addingTimeInterval(1)
        try await repository.save([template, builtIn, recent])
        let service = ModernClipboardService(testRepository: repository)
        await service.loadHistoryFromRepository()

        let first = UUID()
        let second = UUID()
        try await service.setCategory(itemID: template.id, categoryID: first, enabled: true)
        try await service.setCategory(itemID: template.id, categoryID: second, enabled: true)
        await service.setMaxHistoryItems(1)
        let trimmed = await service.getHistory()
        XCTAssertEqual(Set(trimmed.map(\.id)), [template.id, recent.id])

        try await service.setCategory(itemID: template.id, categoryID: first, enabled: false)
        await service.clearHistory(keepingCategories: true)
        let cleared = await service.getHistory()
        XCTAssertEqual(Set(cleared.map(\.id)), [template.id])

        try await service.removeCategoryDefinition(second)
        let edited = await service.getHistory()
        XCTAssertEqual(Set(edited.map(\.id)), [template.id])
        await service.clearHistory(keepingCategories: true)
        await service.flushPendingSaves()
        let saved = try await repository.loadAll()
        XCTAssertTrue(saved.isEmpty)
    }

    @MainActor
    func testOnlyExistingCustomCategoriesProtectHistory() async throws {
        let suite = "CategoryRetentionTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserCategoryStore(defaults: defaults)
        store.add(name: "Keep", iconSystemName: "tag")
        let category = try XCTUnwrap(store.userDefined().first)
        let kept = ClipItem(content: "Keep", userCategoryId: category.id)
        let orphan = ClipItem(content: "Delete", userCategoryId: UUID())

        let repository = try SwiftDataRepository.make(inMemory: true)
        try await repository.save([kept, orphan])
        let service = ModernClipboardService(testRepository: repository, categoryStore: store)
        await service.loadHistoryFromRepository()
        let loaded = await service.getHistory()
        let loadedOrphan = try XCTUnwrap(loaded.first { $0.id == orphan.id })
        XCTAssertTrue(loadedOrphan.categoryIDs.isEmpty)

        let firstClear = await service.clearHistory(keepingCategories: true)
        XCTAssertEqual(try firstClear.get(), 1)
        try await service.removeCategoryDefinition(category.id)
        XCTAssertNil(store.category(id: category.id))
        do {
            try await service.setCategory(itemID: kept.id, categoryID: category.id, enabled: true)
            XCTFail("An edit queued before deletion must not restore the deleted category.")
        } catch {
            XCTAssertEqual(error as? MCPFailure, .invalidInput)
        }

        let lastClear = await service.clearHistory(keepingCategories: true)
        XCTAssertEqual(try lastClear.get(), 1)
        let saved = try await repository.loadAll()
        XCTAssertTrue(saved.isEmpty)
    }

    func testStartupLoadsOldCustomCategoriesBeyondTheRecentHistoryWindow() async throws {
        let repository = try SwiftDataRepository.make(inMemory: true)
        let old = Date().addingTimeInterval(-86_400)
        let category = UUID()
        var legacy = ClipItem(content: "Legacy category", userCategoryId: category)
        legacy.timestamp = old
        var template = ClipItem(content: "Template")
        template.timestamp = old
        template.setCategory(category, enabled: true)
        let recent = (0..<350).map { index in
            var item = ClipItem(content: "History \(index)")
            item.timestamp = old.addingTimeInterval(TimeInterval(index + 1))
            return item
        }
        try await repository.save([legacy, template] + recent)
        let service = ModernClipboardService(testRepository: repository)
        await service.setMaxHistoryItems(2)
        await service.loadHistoryFromRepository()

        let history = await service.getHistory()
        XCTAssertEqual(Set(history.map(\.id)), Set([legacy, template].map(\.id) + recent.suffix(2).map(\.id)))
    }

    func testCategoryDeletionPreservesOtherCategoriesAndClipboard() async throws {
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository)
        let removed = UUID()
        let retained = UUID()
        await service.copyToClipboard("https://example.com", fromEditor: false)
        let initial = await service.getHistory()
        let item = try XCTUnwrap(initial.first)
        try await service.setCategory(itemID: item.id, categoryID: removed, enabled: true)
        try await service.setCategory(itemID: item.id, categoryID: retained, enabled: true)
        let before = await MainActor.run { NSPasteboard.general.changeCount }
        try await service.removeCategoryDefinition(removed)
        let saved = try await repository.loadAll()
        XCTAssertEqual(saved.first?.categoryIDs, [retained, BuiltInCategory.url])
        XCTAssertEqual(saved.first?.id, item.id)
        XCTAssertEqual(saved.first?.timestamp, item.timestamp)
        let after = await MainActor.run { NSPasteboard.general.changeCount }
        XCTAssertEqual(before, after)
    }

    func testClearingCategoriesPersistsAndPreservesOtherItemDetails() async throws {
        let repository = try SwiftDataRepository.make(inMemory: true)
        let custom = UUID()
        let item = ClipItem(content: "https://example.com", userCategoryId: custom,
                            metadata: ClipMetadata(title: "Example", source: .ocr))
        XCTAssertEqual(item.categoryIDs, [BuiltInCategory.url, BuiltInCategory.ocr, custom])
        try await repository.save([item])

        let service = ModernClipboardService(testRepository: repository)
        await service.loadHistoryFromRepository()
        try await service.updateCategories(itemID: item.id, change: .clear)

        let savedItems = try await repository.loadAll()
        let saved = try XCTUnwrap(savedItems.first)
        XCTAssertTrue(saved.categoryIDs.isEmpty)
        XCTAssertEqual(saved.id, item.id)
        XCTAssertEqual(saved.content, item.content)
        XCTAssertEqual(saved.timestamp, item.timestamp)
        XCTAssertEqual(saved.title, item.title)
        XCTAssertEqual(saved.metadata?.sources, item.metadata?.sources)
    }

    func testConcurrentCategoryEditsAreMerged() async throws {
        let service = ModernClipboardService(testRepository: try SwiftDataRepository.make(inMemory: true))
        await service.copyToClipboard("memo", fromEditor: false)
        let history = await service.getHistory()
        let item = try XCTUnwrap(history.first)
        let first = UUID()
        let second = UUID()
        async let firstEdit: Void = service.setCategory(itemID: item.id, categoryID: first, enabled: true)
        async let secondEdit: Void = service.setCategory(itemID: item.id, categoryID: second, enabled: true)
        _ = try await (firstEdit, secondEdit)
        let updated = await service.getHistory()
        XCTAssertEqual(updated.first?.categoryIDs, [first, second])
    }
}

extension MultipleCategoryTests {
    func testCreateHistoryItemSavesDetailsWithoutCopyingAndAppliesHistoryLimit() async throws {
        let repository = try SwiftDataRepository.make(inMemory: true)
        let older = ClipItem(content: "Older history")
        try await repository.save([older])
        let service = ModernClipboardService(testRepository: repository) { _ in
            XCTFail("Adding history must not write to the clipboard")
            return -1
        }
        await service.loadHistoryFromRepository()
        await service.setMaxHistoryItems(1)
        let category = UUID()
        let content = "https://example.org/template"

        try await service.createHistoryItem(
            title: "  Example template  ", content: content,
            categoryChanges: [category: true, BuiltInCategory.url: false]
        )

        let history = await service.getHistory()
        let added = try XCTUnwrap(history.first)
        XCTAssertEqual(history.map(\.id), [added.id, older.id])
        XCTAssertEqual(added.title, "Example template")
        XCTAssertEqual(added.content, content)
        XCTAssertEqual(added.kind, .url)
        XCTAssertEqual(added.categoryIDs, [category])
        XCTAssertEqual(added.metadata?.source, .editor)
        XCTAssertEqual(added.metadata?.createdAt, added.timestamp)
        let saved = try await repository.loadAll()
        XCTAssertEqual(saved.first { $0.id == added.id }, added)

        try await service.createHistoryItem(title: nil, content: "New ordinary history", categoryChanges: [:])
        let limited = await service.getHistory()
        XCTAssertEqual(limited.map(\.content), ["New ordinary history", content])
        let persisted = try await repository.loadAll()
        XCTAssertEqual(Set(persisted.map(\.id)), Set(limited.map(\.id)))
    }

    func testCreateHistoryItemRejectsDuplicatesAndDoesNotPublishFailedSaves() async throws {
        let existing = ClipItem(content: "Existing body", metadata: ClipMetadata(title: "Existing title"))
        let service = ModernClipboardService(testRepository: RejectingCategoryRepository(item: existing))
        await service.loadHistoryFromRepository()

        do {
            try await service.createHistoryItem(title: "New title", content: existing.content, categoryChanges: [UUID(): true])
            XCTFail("Duplicate content must not replace an existing item")
        } catch ClipItemEditError.duplicateContent {}

        do {
            try await service.createHistoryItem(title: "New title", content: "New body", categoryChanges: [UUID(): true])
            XCTFail("A failed save must be reported")
        } catch { XCTAssertEqual(error as? MCPFailure, .persistence) }

        let history = await service.getHistory()
        XCTAssertEqual(history, [existing])
    }

    @MainActor
    func testItemEditSavesAllFieldsInPlaceAndRecopyUsesEditedContent() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let originalContent = "Original formatted content"
        let entry = NSPasteboardItem()
        entry.setString(originalContent, forType: .string)
        entry.setString("<b>Original formatted content</b>", forType: .html)
        XCTAssertTrue(pasteboard.writeObjects([entry]))
        let richText = try XCTUnwrap(ClipboardRichText(pasteboard: pasteboard))
        let metadata = ClipMetadata(title: "Old title", createdAt: Date(timeIntervalSince1970: 100), source: .ocr)
        let original = ClipItem(content: originalContent, sourceApp: "Source app", metadata: metadata, richText: richText)
        let repository = try SwiftDataRepository.make(inMemory: true)
        try await repository.save([original, ClipItem(content: "Other item")])
        let service = ModernClipboardService(testRepository: repository) { ClipboardRichText.write($0, to: pasteboard) }
        await service.loadHistoryFromRepository()
        let before = await service.getHistory()
        let clipboardChangeCount = pasteboard.changeCount
        try await service.updateDetails(id: original.id, title: "Short title")
        let renamedHistory = await service.getHistory()
        XCTAssertEqual(renamedHistory.first { $0.id == original.id }?.richText, richText)

        let custom = UUID()
        let editedContent = "https://example.org/edited"
        XCTAssertEqual(original.categoryIDs(forDraftContent: editedContent), [BuiltInCategory.url, BuiltInCategory.ocr])
        try await assertUnconfirmedEditPreservesFormatting(
            service, id: original.id, editedContent: editedContent, history: renamedHistory
        )
        try await service.updateDetails(
            id: original.id, title: "Edited title", content: editedContent,
            categoryChanges: [custom: true, BuiltInCategory.ocr: false]
        )
        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.id), before.map(\.id))
        let edited = try XCTUnwrap(history.first { $0.id == original.id })
        XCTAssertEqual(edited.title, "Edited title")
        XCTAssertEqual(edited.content, editedContent)
        XCTAssertEqual(edited.kind, .url)
        XCTAssertEqual(edited.categoryIDs, [custom, BuiltInCategory.url])
        XCTAssertEqual(edited.sourceApp, original.sourceApp)
        XCTAssertEqual(edited.metadata?.createdAt, original.metadata?.createdAt)
        XCTAssertEqual(edited.timestamp, original.timestamp)
        XCTAssertNil(edited.richText)
        XCTAssertEqual(pasteboard.changeCount, clipboardChangeCount)
        let persisted = try await repository.loadAll()
        XCTAssertEqual(persisted.first { $0.id == original.id }, edited)

        await service.recopyFromHistory(original)
        XCTAssertEqual(pasteboard.string(forType: .string), editedContent)
        _ = await service.addEditorItems([originalContent])
        let afterRecopy = await service.getHistory()
        XCTAssertEqual(afterRecopy.first?.content, originalContent)
        XCTAssertNotEqual(afterRecopy.first?.id, original.id)
        XCTAssertEqual(afterRecopy.first { $0.id == original.id }?.title, "Edited title")
    }

    private func assertUnconfirmedEditPreservesFormatting(
        _ service: ModernClipboardService, id: UUID, editedContent: String, history: [ClipItem]
    ) async throws {
        do {
            try await service.updateDetails(id: id, content: editedContent, allowsRemovingRichText: false)
            XCTFail("An unconfirmed edit must preserve formatting")
        } catch ClipItemEditError.richTextLossRequiresConfirmation {
            let protectedHistory = await service.getHistory()
            XCTAssertEqual(protectedHistory, history)
        }
    }

    func testDuplicateItemEditLeavesBothItemsUntouched() async throws {
        let repository = try SwiftDataRepository.make(inMemory: true)
        let first = ClipItem(content: "First item")
        let second = ClipItem(content: "Second item")
        try await repository.save([first, second])
        let service = ModernClipboardService(testRepository: repository)
        await service.loadHistoryFromRepository()
        let before = await service.getHistory()

        do {
            try await service.updateDetails(
                id: first.id, title: "New name", content: second.content, categoryChanges: [UUID(): true]
            )
            XCTFail("An edit must not overwrite another item with the same body")
        } catch ClipItemEditError.duplicateContent {}

        let after = await service.getHistory()
        let persisted = try await repository.loadAll()
        XCTAssertEqual(after, before)
        XCTAssertEqual(Set(persisted.map(\.id)), Set(before.map(\.id)))
        XCTAssertTrue(persisted.allSatisfy(before.contains))
    }

    @MainActor
    func testFailedPersistenceKeepsCategoryStateUnchanged() async throws {
        let suite = "CategoryPersistenceTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserCategoryStore(defaults: defaults)
        store.add(name: "Keep on failure", iconSystemName: "tag")
        let custom = try XCTUnwrap(store.userDefined().first?.id)
        let item = ClipItem(content: "memo", userCategoryId: custom)
        let service = ModernClipboardService(testRepository: RejectingCategoryRepository(item: item), categoryStore: store)
        await service.loadHistoryFromRepository()
        do {
            try await service.setCategory(itemID: item.id, categoryID: BuiltInCategory.ai, enabled: true)
            XCTFail("A failed save must be reported")
        } catch { XCTAssertEqual(error as? MCPFailure, .persistence) }
        do {
            try await service.updateCategories(itemID: item.id, change: .clear)
            XCTFail("A failed clear must be reported")
        } catch { XCTAssertEqual(error as? MCPFailure, .persistence) }
        do {
            try await service.updateDetails(
                id: item.id, title: "New title", content: "New body",
                categoryChanges: [custom: false, BuiltInCategory.ai: true]
            )
            XCTFail("A failed item edit must be reported")
        } catch { XCTAssertEqual(error as? MCPFailure, .persistence) }
        do {
            try await service.removeCategoryDefinition(custom)
            XCTFail("A failed deletion must be reported")
        } catch { XCTAssertEqual(error as? MCPFailure, .persistence) }
        let history = await service.getHistory()
        XCTAssertEqual(history, [item])
        XCTAssertNotNil(store.category(id: custom))
    }

    @MainActor
    func testEditingRowRemainsVisibleUntilPopoverCloses() {
        let clipboard = MockClipboardService()
        var item = ClipItem(content: "https://example.com", userCategoryId: savedHistoryCategoryID)
        clipboard.history = [item, ClipItem(content: "https://second.example.com")]
        let model = MainViewModel(clipboardService: clipboard)
        model.categoryFilter.ids = [BuiltInCategory.url, savedHistoryCategoryID]
        model.searchText = "example.com"
        model.categoryEditingItemID = item.id
        item.setCategory(BuiltInCategory.url, enabled: false)
        clipboard.history[0] = item
        model.updateFilteredItems(clipboard.history)
        XCTAssertEqual(model.filteredHistory.map(\.id), [item.id])
        model.categoryEditingItemID = nil
        XCTAssertTrue(model.filteredHistory.isEmpty)
    }

    @MainActor
    func testLegacySwiftDataMetadataCanBeEditedAndReopened() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([ClipItemModel.self])
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("history.store"))
        let custom = UUID()
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let legacy = ClipItemModel(content: "https://example.com", userCategoryId: custom)
        legacy.metadataData = Data("{\"source\":\"mcp\",\"title\":\"Old title\"}".utf8)
        context.insert(legacy)
        try context.save()
        let repository = try SwiftDataRepository.make(container: container)
        let loaded = try await repository.loadAll()
        var item = try XCTUnwrap(loaded.first)
        XCTAssertEqual(item.categoryIDs, [custom, BuiltInCategory.url, BuiltInCategory.ai])
        item.setCategory(BuiltInCategory.ai, enabled: false)
        try await repository.save([item])
        let reopened = try ModelContainer(for: schema, configurations: [config])
        let reopenedRepository = try SwiftDataRepository.make(container: reopened)
        let saved = try await reopenedRepository.loadAll()
        XCTAssertEqual(saved.first?.categoryIDs, [custom, BuiltInCategory.url])
        XCTAssertEqual(saved.first?.title, "Old title")
        XCTAssertEqual(saved.first?.metadata?.sources, [.mcp])
    }
}

private actor RejectingCategoryRepository: ClipboardRepositoryProtocol {
    let item: ClipItem
    init(item: ClipItem) { self.item = item }
    func load(limit: Int) async throws -> [ClipItem] { [item] }
    func loadAll() async throws -> [ClipItem] { [item] }
    func save(_ items: [ClipItem]) async throws { throw MCPFailure.persistence }
    func replaceAll(with items: [ClipItem]) async throws { throw MCPFailure.persistence }
    func delete(_ item: ClipItem) async throws { throw MCPFailure.persistence }
    func clear() async throws { throw MCPFailure.persistence }
    func applyChanges(inserted: [ClipItem], updated: [ClipItem], removed: [UUID]) async throws {
        throw MCPFailure.persistence
    }
}
