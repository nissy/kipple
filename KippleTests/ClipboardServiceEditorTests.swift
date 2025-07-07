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
        
        // モニタリングを停止してクリーンな状態を確保
        clipboardService.stopMonitoring()
        Thread.sleep(forTimeInterval: 0.2)
        
        // テスト開始前に履歴をクリア
        clipboardService.clearAllHistory()
        // クリップボードもクリア
        NSPasteboard.general.clearContents()
        
        // エディタコピーのテストではモニタリングを開始しない
        // （外部からのクリップボード変更の影響を避けるため）
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
        
        // テスト開始時の履歴を確認
        let initialHistoryCount = clipboardService.history.count
        
        // モニタリングを開始してエディタコピーを検出できるようにする
        clipboardService.startMonitoring()
        Thread.sleep(forTimeInterval: 0.5)
        
        // When
        clipboardService.copyToClipboard(testContent, fromEditor: true)
        
        // クリップボード監視が検出するのを待つ
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Then
            // 履歴から該当するアイテムを探す（履歴は新しいものが先頭に来る）
            if let latestItem = self.clipboardService.history.first(where: { $0.content == testContent }) {
                XCTAssertEqual(latestItem.content, testContent)
                XCTAssertEqual(latestItem.sourceApp, "Kipple", "Source app should be 'Kipple' for editor copies")
                XCTAssertEqual(latestItem.windowTitle, "Quick Editor", "Window title should be 'Quick Editor' for editor copies")
                XCTAssertNotNil(latestItem.bundleIdentifier)
                XCTAssertEqual(latestItem.bundleIdentifier, Bundle.main.bundleIdentifier)
                XCTAssertTrue(latestItem.isFromEditor ?? false, "isFromEditor should be true")
                XCTAssertEqual(latestItem.category, .kipple, "Category should be kipple for editor copies")
            } else {
                // デバッグ情報を出力
                print("Initial history count: \(initialHistoryCount)")
                print("Current history count: \(self.clipboardService.history.count)")
                print("History items:")
                for (index, item) in self.clipboardService.history.prefix(5).enumerated() {
                    print("  [\(index)] \(item.content) (from: \(item.sourceApp ?? "unknown"))")
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
        
        // モニタリングを開始
        clipboardService.startMonitoring()
        Thread.sleep(forTimeInterval: 0.5)
        
        let initialCount = clipboardService.history.count
        
        // When - エディタからコピー
        clipboardService.copyToClipboard(editorContent, fromEditor: true)
        
        // 待機して結果を確認
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Then
            let currentCount = self.clipboardService.history.count
            XCTAssertGreaterThan(currentCount, initialCount, "Editor copy should be added to history")
            
            // 最新のアイテムを確認
            if let editorItem = self.clipboardService.history.first(where: { $0.content == editorContent }) {
                XCTAssertEqual(editorItem.sourceApp, "Kipple", "Editor copy should have 'Kipple' as source app")
                XCTAssertTrue(editorItem.isFromEditor ?? false, "Should be marked as from editor")
                XCTAssertEqual(editorItem.category, .kipple, "Should have kipple category")
                
                // 通常のコピー（fromEditor: false）は内部コピーとして扱われ、履歴に追加されないことを確認
                let beforeInternalCount = self.clipboardService.history.count
                let internalContent = "KIPPLE_TEST_INTERNAL_\(UUID().uuidString)"
                self.clipboardService.copyToClipboard(internalContent, fromEditor: false)
                
                // 少し待って確認
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // 内部コピーは履歴に追加されない
                    XCTAssertEqual(self.clipboardService.history.count, beforeInternalCount, 
                                   "Internal copy should not increase history count")
                    XCTAssertFalse(self.clipboardService.history.contains { $0.content == internalContent }, 
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
        
        // モニタリングを開始
        clipboardService.startMonitoring()
        Thread.sleep(forTimeInterval: 0.5)
        
        // When
        clipboardService.copyToClipboard(testContent, fromEditor: true)
        
        // 待機
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Then
            if let latestItem = self.clipboardService.history.first(where: { $0.content == testContent }) {
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
        
        // モニタリングを開始
        clipboardService.startMonitoring()
        Thread.sleep(forTimeInterval: 0.5)
        
        // When - 各コピーの間隔を長くして、確実に検出されるようにする
        for (index, content) in contents.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 1.5) {
                self.clipboardService.copyToClipboard(content, fromEditor: true)
            }
        }
        
        // 待機して確認
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            // Then
            // テスト用のエディタアイテムを確認
            let testContents = Set(contents)
            let foundItems = self.clipboardService.history.filter { 
                testContents.contains($0.content)
            }
            
            // 少なくとも1つは記録されているはず
            XCTAssertFalse(foundItems.isEmpty, "At least one editor copy should be recorded")
            
            // 記録されたアイテムが正しいプロパティを持っているか確認
            for item in foundItems {
                XCTAssertEqual(item.sourceApp, "Kipple", "All editor items should have 'Kipple' as source app")
                XCTAssertEqual(item.windowTitle, "Quick Editor", "All editor items should have 'Quick Editor' as window title")
                XCTAssertEqual(item.category, .kipple, "All editor items should have kipple category")
                XCTAssertTrue(item.isFromEditor ?? false, "Should be marked as from editor")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 6.0)
    }
}
