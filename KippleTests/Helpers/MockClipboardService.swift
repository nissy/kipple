//
//  MockClipboardService.swift
//  KippleTests
//
//  Core Dataに依存しないテスト用のMock実装
//

import Foundation
import Combine
@testable import Kipple

/// Core Dataを使用しないテスト用のClipboardService実装
final class MockClipboardService: ObservableObject, ClipboardServiceProtocol {
    @Published var history: [ClipItem] = []
    @Published var currentClipboardContent: String?
    
    var pinnedItems: [ClipItem] {
        history.filter { $0.isPinned }
    }
    
    var onHistoryChanged: ((ClipItem) -> Void)?
    
    // Test tracking properties
    var startMonitoringCalled = false
    var stopMonitoringCalled = false
    var copyToClipboardCalled = false
    var lastCopiedContent: String?
    var fromEditor = false
    var togglePinCalled = false
    var lastToggledItem: ClipItem?
    var deleteItemCalled = false
    var lastDeletedItem: ClipItem?
    var clearAllHistoryCalled = false
    
    func startMonitoring() {
        startMonitoringCalled = true
    }
    
    func stopMonitoring() {
        stopMonitoringCalled = true
    }
    
    func copyToClipboard(_ content: String, fromEditor: Bool = false) {
        copyToClipboardCalled = true
        lastCopiedContent = content
        self.fromEditor = fromEditor
        
        // 新しいアイテムを履歴に追加
        let newItem = ClipItem(content: content, isFromEditor: fromEditor)
        history.insert(newItem, at: 0)
        currentClipboardContent = content
        
        // コールバックを呼び出す
        onHistoryChanged?(newItem)
    }
    
    func togglePin(for item: ClipItem) -> Bool {
        togglePinCalled = true
        lastToggledItem = item
        
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            history[index].isPinned.toggle()
            return true
        }
        return false
    }
    
    func clearAllHistory() {
        clearAllHistoryCalled = true
        history.removeAll()
    }
    
    func deleteItem(_ item: ClipItem) {
        deleteItemCalled = true
        lastDeletedItem = item
        history.removeAll { $0.id == item.id }
    }
    
    // テスト用のヘルパーメソッド
    func addTestItem(_ item: ClipItem) {
        history.append(item)
    }
    
    func reset() {
        history.removeAll()
        currentClipboardContent = nil
        startMonitoringCalled = false
        stopMonitoringCalled = false
        copyToClipboardCalled = false
        lastCopiedContent = nil
        fromEditor = false
        togglePinCalled = false
        lastToggledItem = nil
        deleteItemCalled = false
        lastDeletedItem = nil
        clearAllHistoryCalled = false
    }
}
