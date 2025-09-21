//
//  MockClipboardService.swift
//  KippleTests
//
//  Mock implementation of ClipboardServiceProtocol for testing
//

import Foundation
@testable import Kipple

class MockClipboardService: ClipboardServiceProtocol {
    var history: [ClipItem] = []
    var pinnedItems: [ClipItem] = []
    var currentClipboardContent: String?
    var onHistoryChanged: ((ClipItem) -> Void)?

    var isMonitoringActive = false
    var lastCopiedContent: String?
    var lastCopiedFromEditor: Bool?
    var lastRecopiedItem: ClipItem?

    // Additional test properties
    var copyToClipboardCalled = false
    var fromEditor: Bool?
    var togglePinCalled = false
    var lastToggledItem: ClipItem?
    var deleteItemCalled = false
    var lastDeletedItem: ClipItem?
    var clearAllHistoryCalled = false
    var autoClearRemainingTime: TimeInterval?

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

        let item = ClipItem(content: content, isFromEditor: fromEditor)
        history.insert(item, at: 0)
        currentClipboardContent = content
        onHistoryChanged?(item)
    }

    func recopyFromHistory(_ item: ClipItem) {
        lastRecopiedItem = item

        // Remove existing item with same content
        if let index = history.firstIndex(where: { $0.content == item.content }) {
            history.remove(at: index)
        }

        // Add to top with preserved metadata
        history.insert(item, at: 0)
        currentClipboardContent = item.content
        onHistoryChanged?(item)
    }

    func clearSystemClipboard() {
        currentClipboardContent = nil
    }

    func clearAllHistory() {
        clearAllHistoryCalled = true
        history.removeAll()
        pinnedItems.removeAll()
        currentClipboardContent = nil
    }

    func clearHistory(keepPinned: Bool) async {
        if keepPinned {
            history = history.filter { $0.isPinned }
            pinnedItems = history.filter { $0.isPinned }
        } else {
            clearAllHistory()
        }
    }

    func togglePin(for item: ClipItem) -> Bool {
        togglePinCalled = true
        lastToggledItem = item

        if let index = history.firstIndex(where: { $0.id == item.id }) {
            history[index].isPinned.toggle()

            if history[index].isPinned {
                pinnedItems.append(history[index])
            } else {
                pinnedItems.removeAll { $0.id == item.id }
            }

            return history[index].isPinned
        }
        return false
    }

    func deleteItem(_ item: ClipItem) {
        deleteItemCalled = true
        lastDeletedItem = item
        history.removeAll { $0.id == item.id }
        pinnedItems.removeAll { $0.id == item.id }
    }

    func deleteItem(_ item: ClipItem) async {
        deleteItemCalled = true
        lastDeletedItem = item
        history.removeAll { $0.id == item.id }
        pinnedItems.removeAll { $0.id == item.id }
    }

    func flushPendingSaves() async {
        // No-op for mock
    }

    // Helper methods for testing
    func addTestItem(_ content: String, isPinned: Bool = false, sourceApp: String? = nil) {
        var item = ClipItem(content: content, sourceApp: sourceApp)
        item.isPinned = isPinned
        history.append(item)

        if isPinned {
            pinnedItems.append(item)
        }
    }

    func addTestItem(_ item: ClipItem) {
        history.append(item)

        if item.isPinned {
            pinnedItems.append(item)
        }
    }

    func reset() {
        history.removeAll()
        pinnedItems.removeAll()
        currentClipboardContent = nil
        isMonitoringActive = false
        lastCopiedContent = nil
        lastCopiedFromEditor = nil
        lastRecopiedItem = nil
        copyToClipboardCalled = false
        fromEditor = nil
        togglePinCalled = false
        lastToggledItem = nil
        deleteItemCalled = false
        lastDeletedItem = nil
        clearAllHistoryCalled = false
        autoClearRemainingTime = nil
    }
}
