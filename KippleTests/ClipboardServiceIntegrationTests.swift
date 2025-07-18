//
//  ClipboardServiceIntegrationTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/18.
//

import XCTest
@testable import Kipple

final class ClipboardServiceIntegrationTests: XCTestCase {
    var clipboardService: ClipboardService!
    
    override func setUp() {
        super.setUp()
        clipboardService = ClipboardService.shared
        
        // テスト環境でも必要な初期化を行う
        // saveSubscriptionが設定されていない場合は手動で設定
        if clipboardService.saveSubscription == nil {
            clipboardService.saveSubscription = clipboardService.saveSubject
                .debounce(for: .seconds(1), scheduler: RunLoop.main)
                .sink { [weak clipboardService] items in
                    clipboardService?.saveHistoryToRepository(items)
                }
        }
        
        clipboardService.clearAllHistory()
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    override func tearDown() {
        clipboardService.stopMonitoring()
        clipboardService.clearAllHistory()
        Thread.sleep(forTimeInterval: 0.5)
        clipboardService = nil
        super.tearDown()
    }
    
    func testCopyFromHistoryItem() {
        // Given: 履歴にアイテムがある
        let content1 = "Test content 1"
        let content2 = "Test content 2"
        let content3 = "Test content 3"
        
        // 手動で履歴を追加
        clipboardService.history = [
            ClipItem(content: content3),
            ClipItem(content: content2),
            ClipItem(content: content1)
        ]
        
        // When: 履歴のアイテムをコピー
        clipboardService.copyToClipboard(content2, fromEditor: false)
        
        // Then: クリップボードに設定される
        let pasteboardContent = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(pasteboardContent, content2)
        
        // And: currentClipboardContentが更新される
        XCTAssertEqual(clipboardService.currentClipboardContent, content2)
        
        // And: 履歴の順序が更新される（コピーしたアイテムが先頭に）
        let expectation = XCTestExpectation(description: "History updated")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            XCTAssertEqual(self.clipboardService.history.first?.content, content2)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testExternalCopyDetection() {
        // テスト環境ではモニタリングが正しく動作しないため、
        // 外部コピーの動作を直接シミュレートする
        let testContent = "External copy test \(UUID().uuidString)"
        let expectation = XCTestExpectation(description: "External copy simulated")
        
        // Given: 初期状態を設定
        clipboardService.clearAllHistory()
        let initialCount = clipboardService.history.count
        
        // When: 外部コピーをシミュレート（アプリ情報付きで直接追加）
        let appInfo = ClipboardService.AppInfo(
            appName: "TestApp",
            windowTitle: "Test Window",
            bundleId: "com.test.app",
            pid: 12345
        )
        
        // 直接addToHistoryWithAppInfoを呼び出す
        clipboardService.addToHistoryWithAppInfo(testContent, appInfo: appInfo, isFromEditor: false)
        
        // Then: 履歴に追加されることを確認
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            XCTAssertGreaterThan(
                self.clipboardService.history.count,
                initialCount,
                "External copy should be added to history"
            )
            
            if let latestItem = self.clipboardService.history.first {
                XCTAssertEqual(latestItem.content, testContent)
                XCTAssertEqual(latestItem.sourceApp, "TestApp")
                XCTAssertEqual(latestItem.windowTitle, "Test Window")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testInternalCopyDoesNotDuplicate() {
        // Given: 初期履歴を設定
        let content = "Test content for internal copy"
        clipboardService.history = [ClipItem(content: content)]
        let initialCount = 1
        let expectation = XCTestExpectation(description: "Internal copy processed")
        
        // When: 内部コピー（fromEditor: false）
        clipboardService.copyToClipboard(content, fromEditor: false)
        
        // Then: 履歴の数は増えない
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            XCTAssertEqual(
                self.clipboardService.history.count,
                initialCount,
                "Internal copy should not duplicate history items"
            )
            
            // But: クリップボードには設定される
            let pasteboardContent = NSPasteboard.general.string(forType: .string)
            XCTAssertEqual(pasteboardContent, content)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testCopyWithHistoryUpdate() {
        // Given: 複数のアイテムがある履歴
        let content1 = "First item"
        let content2 = "Second item"
        let content3 = "Third item"
        
        clipboardService.history = [
            ClipItem(content: content1),
            ClipItem(content: content2),
            ClipItem(content: content3)
        ]
        
        // When: 3番目のアイテムをコピー
        clipboardService.copyToClipboard(content3, fromEditor: false)
        
        // Then: 順序が更新される
        let expectation = XCTestExpectation(description: "History order updated")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            XCTAssertEqual(self.clipboardService.history[0].content, content3, "Copied item should move to top")
            XCTAssertEqual(self.clipboardService.history[1].content, content1)
            XCTAssertEqual(self.clipboardService.history[2].content, content2)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
}
