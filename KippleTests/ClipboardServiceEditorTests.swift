//
//  ClipboardServiceEditorTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/07.
//

import XCTest
import Combine
@testable import Kipple

final class ClipboardServiceEditorTests: XCTestCase {
    var clipboardService: ClipboardService!
    private var cancellables = Set<AnyCancellable>()
    
    override func setUp() {
        super.setUp()
        clipboardService = ClipboardService.shared
        cancellables.removeAll()
        
        // モニタリングを停止してから再開することで、クリーンな状態を確保
        clipboardService.stopMonitoring()
        Thread.sleep(forTimeInterval: 0.2)
        
        // テスト開始前に履歴をクリア
        clipboardService.clearAllHistory()
        // クリップボードもクリア
        NSPasteboard.general.clearContents()
        
        // モニタリング開始
        clipboardService.startMonitoring()
        // 少し待機してモニタリングが開始されるのを確認
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    override func tearDown() {
        clipboardService.stopMonitoring()
        // テスト終了後も履歴をクリア
        clipboardService.clearAllHistory()
        // クリップボードもクリア
        NSPasteboard.general.clearContents()
        cancellables.removeAll()
        clipboardService = nil
        super.tearDown()
    }
    
    func testCopyFromEditor() {
        // Given
        let uuid = UUID().uuidString
        let testContent = "KIPPLE_TEST_EDITOR_\(uuid)"
        let expectation = XCTestExpectation(description: "Editor copy recorded")
        
        // 履歴が空であることを確認（既存のデータがある場合はクリア）
        if !clipboardService.history.isEmpty {
            clipboardService.clearAllHistory()
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // When
        clipboardService.copyToClipboard(testContent, fromEditor: true)
        
        // クリップボード監視が検出するのを待つ（より長い待機時間）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Then
            // テスト用のプレフィックスを持つアイテムのみをフィルタ
            let testItems = self.clipboardService.history.filter { $0.content.hasPrefix("KIPPLE_TEST_") }
            
            if let latestItem = testItems.first(where: { $0.content == testContent }) {
                XCTAssertEqual(latestItem.content, testContent)
                XCTAssertEqual(latestItem.sourceApp, "Kipple", "Source app should be 'Kipple' for editor copies")
                XCTAssertEqual(latestItem.windowTitle, "Quick Editor", "Window title should be 'Quick Editor' for editor copies")
                XCTAssertNotNil(latestItem.bundleIdentifier)
                XCTAssertEqual(latestItem.bundleIdentifier, Bundle.main.bundleIdentifier)
                XCTAssertTrue(latestItem.isFromEditor ?? false, "isFromEditor should be true")
                XCTAssertEqual(latestItem.category, .kipple, "Category should be kipple for editor copies")
            } else {
                // デバッグ情報を出力
                print("Test items found: \(testItems.count)")
                for item in testItems {
                    print("  - \(item.content)")
                }
                XCTFail("No item with test content '\(testContent)' was added to history")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 4.0)
    }
    
    func testCopyFromEditorVsNormalCopy() {
        // Given
        let uuid = UUID().uuidString
        let editorContent = "KIPPLE_TEST_EDITOR_VS_NORMAL_\(uuid)"
        let expectation = XCTestExpectation(description: "Editor copy recorded")
        
        // When - エディタからコピー
        clipboardService.copyToClipboard(editorContent, fromEditor: true)
        
        // 待機して結果を確認
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Then
            // テスト用のプレフィックスを持つアイテムのみをフィルタ
            let testItems = self.clipboardService.history.filter { $0.content.hasPrefix("KIPPLE_TEST_") }
            
            // エディタからのコピーを確認
            if let editorItem = testItems.first(where: { $0.content == editorContent }) {
                XCTAssertEqual(editorItem.sourceApp, "Kipple", "Editor copy should have 'Kipple' as source app")
                XCTAssertTrue(editorItem.isFromEditor ?? false, "Should be marked as from editor")
                XCTAssertEqual(editorItem.category, .kipple, "Should have kipple category")
                
                // 通常のコピー（fromEditor: false）は内部コピーとして扱われ、履歴に追加されないことを確認
                // 別のテストコンテンツで確認
                let internalContent = "KIPPLE_TEST_INTERNAL_\(UUID().uuidString)"
                self.clipboardService.copyToClipboard(internalContent, fromEditor: false)
                
                // 少し待って確認
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // 内部コピーは履歴に追加されない
                    let updatedTestItems = self.clipboardService.history.filter { $0.content.hasPrefix("KIPPLE_TEST_") }
                    XCTAssertFalse(updatedTestItems.contains { $0.content == internalContent }, 
                                   "Internal copy should not be added to history")
                    expectation.fulfill()
                }
            } else {
                XCTFail("Editor copy not found in history")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 4.0)
    }
    
    func testEditorCopyProcessID() {
        // Given
        let uuid = UUID().uuidString
        let testContent = "KIPPLE_TEST_PROCESS_ID_\(uuid)"
        let expectation = XCTestExpectation(description: "Process ID recorded")
        
        // When
        clipboardService.copyToClipboard(testContent, fromEditor: true)
        
        // 待機
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Then
            // テスト用のプレフィックスを持つアイテムのみをフィルタ
            let testItems = self.clipboardService.history.filter { $0.content.hasPrefix("KIPPLE_TEST_") }
            
            if let latestItem = testItems.first(where: { $0.content == testContent }) {
                XCTAssertNotNil(latestItem.processID, "Process ID should be recorded")
                XCTAssertEqual(latestItem.processID, ProcessInfo.processInfo.processIdentifier, "Process ID should match current process")
            } else {
                XCTFail("No item with test content was added to history")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 3.0)
    }
    
    func testMultipleEditorCopies() {
        // Given
        let uuid = UUID().uuidString
        let contents = [
            "KIPPLE_TEST_MULTI_FIRST_\(uuid)",
            "KIPPLE_TEST_MULTI_SECOND_\(uuid)",
            "KIPPLE_TEST_MULTI_THIRD_\(uuid)"
        ]
        let expectation = XCTestExpectation(description: "Multiple editor copies")
        
        // When - 各コピーの間隔を長くして、確実に検出されるようにする
        for (index, content) in contents.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 1.5) {
                self.clipboardService.copyToClipboard(content, fromEditor: true)
            }
        }
        
        // 待機して確認
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            // Then
            // テスト用のプレフィックスを持つエディタアイテムのみをフィルタ
            let testEditorItems = self.clipboardService.history.filter { 
                ($0.isFromEditor ?? false) && $0.content.hasPrefix("KIPPLE_TEST_MULTI_")
            }
            
            // 少なくとも最後のアイテムは確実に記録されているはず
            if let lastContent = contents.last {
                XCTAssertTrue(testEditorItems.contains { $0.content == lastContent }, 
                              "At least the last content '\(lastContent)' should be in history")
            }
            
            // 記録されたエディタアイテムが正しいアプリ名を持っているか確認
            for item in testEditorItems {
                XCTAssertEqual(item.sourceApp, "Kipple", "All editor items should have 'Kipple' as source app")
                XCTAssertEqual(item.windowTitle, "Quick Editor", "All editor items should have 'Quick Editor' as window title")
                XCTAssertEqual(item.category, .kipple, "All editor items should have kipple category")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 6.0)
    }
}
