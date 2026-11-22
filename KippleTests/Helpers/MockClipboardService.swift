//
//  MockClipboardService.swift
//  KippleTests
//
//  Mock implementation of ClipboardServiceProtocol for testing
//

import Foundation
@testable import Kipple

@MainActor
class MockClipboardService: ClipboardServiceProtocol, ClipboardServiceAsyncRecopying {
    var history: [ClipItem] = []
    var currentClipboardContent: String?
    var onHistoryChanged: ((ClipItem) -> Void)?

    var isMonitoringActive = false
    var lastCopiedContent: String?
    var lastCopiedFromEditor: Bool?
    var recognizedCopyHandler: ((String) async -> UUID?)?
    var lastRecopiedItem: ClipItem?

    // Additional test properties
    var copyToClipboardCalled = false
    var writeToClipboardOnlyCalled = false
    var fromEditor: Bool?
    var deleteItemCalled = false
    var lastDeletedItem: ClipItem?
    var recopyFromHistoryAndWaitCallCount = 0
    var recopyFromHistoryCallCount = 0
    var addEditorItemsCallCount = 0
    var lastAddEditorItemsInput: [String]?

    func startMonitoring() {
        isMonitoringActive = true
    }

    func stopMonitoring() {
        isMonitoringActive = false
    }

    func copyToClipboard(_ content: String, fromEditor: Bool) {
        copyToClipboardCalled = true
        self.fromEditor = fromEditor
        lastCopiedContent = content
        lastCopiedFromEditor = fromEditor

        let item: ClipItem
        if fromEditor {
            // エディターからのコピーの場合、Kippleのメタデータを設定
            item = ClipItem(
                content: content,
                sourceApp: "Kipple",
                windowTitle: "Live Editor",
                bundleIdentifier: Bundle.main.bundleIdentifier,
                processID: ProcessInfo.processInfo.processIdentifier,
                isFromEditor: true
            )
        } else {
            item = ClipItem(content: content, isFromEditor: false)
        }

        history.insert(item, at: 0)
        currentClipboardContent = content
        onHistoryChanged?(item)
    }

    func copyRecognizedText(_ content: String) async -> UUID? {
        if let recognizedCopyHandler { return await recognizedCopyHandler(content) }
        copyToClipboard(content, fromEditor: false)
        guard let index = history.firstIndex(where: { $0.content == content }) else { return nil }
        history[index].metadata = ClipMetadata(source: .ocr)
        return history[index].id
    }

    func writeToClipboardOnly(_ content: String) {
        writeToClipboardOnlyCalled = true
        lastCopiedContent = content
        currentClipboardContent = content.isEmpty ? nil : content
    }

    @discardableResult
    func addEditorItems(_ contents: [String]) async -> [ClipItem] {
        addEditorItemsCallCount += 1
        let sanitized = contents
            .filter { !$0.isEmpty }

        lastAddEditorItemsInput = sanitized

        guard !sanitized.isEmpty else { return [] }

        let createdItems = sanitized.map { content -> ClipItem in
            ClipItem(
                content: content,
                sourceApp: "Kipple",
                windowTitle: "Live Editor",
                bundleIdentifier: Bundle.main.bundleIdentifier,
                processID: ProcessInfo.processInfo.processIdentifier,
                isFromEditor: true
            )
        }

        for item in createdItems.reversed() {
            history.insert(item, at: 0)
            onHistoryChanged?(item)
        }

        return createdItems
    }

    func recopyFromHistory(_ item: ClipItem) {
        recopyFromHistoryCallCount += 1
        lastRecopiedItem = item

        var updatedItem = item

        if let index = history.firstIndex(where: { $0.id == item.id }) {
            let existing = history.remove(at: index)
            updatedItem.userCategoryId = existing.userCategoryId
        } else if let index = history.firstIndex(where: { $0.content == item.content }) {
            let existing = history.remove(at: index)
            updatedItem.userCategoryId = existing.userCategoryId
        }

        // Add to top with preserved metadata
        history.insert(updatedItem, at: 0)
        currentClipboardContent = updatedItem.content
        onHistoryChanged?(updatedItem)
    }

    func recopyFromHistoryAndWait(_ item: ClipItem) async {
        recopyFromHistoryAndWaitCallCount += 1
        recopyFromHistory(item)
    }

    func clearSystemClipboard() async {
        currentClipboardContent = nil
    }

    @discardableResult
    func clearHistory(keepingCategories: Bool) async -> Result<Int, Error> {
        let originalCount = history.count
        if keepingCategories {
            history = history.filter(\.hasCustomCategory)
        } else {
            history.removeAll()
        }
        return .success(originalCount - history.count)
    }

    func deleteItem(_ item: ClipItem) {
        deleteItemCalled = true
        lastDeletedItem = item
        history.removeAll { $0.id == item.id && !$0.hasCustomCategory }
    }

    func deleteItem(_ item: ClipItem) async {
        deleteItemCalled = true
        lastDeletedItem = item
        history.removeAll { $0.id == item.id && !$0.hasCustomCategory }
    }

    func flushPendingSaves() async {
        // No-op for mock
    }

    func saveBeforeTermination() async throws {
        await flushPendingSaves()
    }

    // Helper methods for testing
    func addTestItem(_ content: String, sourceApp: String? = nil) {
        let item = ClipItem(content: content, sourceApp: sourceApp)
        history.append(item)
    }

    func addTestItem(_ item: ClipItem) {
        history.append(item)
    }

    func reset() {
        history.removeAll()
        currentClipboardContent = nil
        isMonitoringActive = false
        lastCopiedContent = nil
        lastCopiedFromEditor = nil
        lastRecopiedItem = nil
        lastAddEditorItemsInput = nil
        addEditorItemsCallCount = 0
        recopyFromHistoryCallCount = 0
        copyToClipboardCalled = false
        writeToClipboardOnlyCalled = false
        fromEditor = nil
        deleteItemCalled = false
        lastDeletedItem = nil
        recopyFromHistoryAndWaitCallCount = 0
    }
}
