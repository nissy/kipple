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
    
    // 内部コピーフラグ（実際のClipboardServiceの動作を模倣）
    private var isInternalCopy = false
    
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
        
        // 現在のクリップボード内容を更新
        currentClipboardContent = content
        
        // 実際のClipboardServiceの動作を模倣
        if !fromEditor {
            // 内部コピー（fromEditor: false）は履歴に記録しない
            return
        }
        
        // エディターからのコピーの場合のみ履歴に追加
        let newItem = ClipItem(
            content: content,
            sourceApp: "Kipple",
            windowTitle: "Quick Editor",
            bundleIdentifier: Bundle.main.bundleIdentifier,
            processID: ProcessInfo.processInfo.processIdentifier,
            isFromEditor: true
        )
        
        history.insert(newItem, at: 0)
        
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
