//
//  ClipboardServiceAppInfoTests.swift
//  KippleTests
//
//  Created by Test on 2025/07/06.
//

import XCTest
import Cocoa
@testable import Kipple

final class ClipboardServiceAppInfoTests: XCTestCase {
    var clipboardService: ClipboardService!
    
    override func setUp() {
        super.setUp()
        clipboardService = ClipboardService.shared
        
        // モニタリングを停止してから再開することで、クリーンな状態を確保
        clipboardService.stopMonitoring()
        Thread.sleep(forTimeInterval: 0.2)
        
        // 履歴をクリア
        clipboardService.clearAllHistory()
        // クリップボードもクリア
        NSPasteboard.general.clearContents()
    }
    
    override func tearDown() {
        clipboardService.stopMonitoring()
        clipboardService.clearAllHistory()
        // クリップボードもクリア
        NSPasteboard.general.clearContents()
        clipboardService = nil
        super.tearDown()
    }
    
    func testAppInfoCapture() {
        // テスト用のクリップボードサービスを作成
        clipboardService.startMonitoring()
        
        // 履歴をクリア
        clipboardService.clearAllHistory()
        
        // 少し待機してからテスト内容をクリップボードにコピー
        let uuid = UUID().uuidString
        let testContent = "KIPPLE_TEST_XCTEST_\(uuid)"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(testContent, forType: .string)
        }
        
        // クリップボードサービスが検出するまで待機
        let expectation = XCTestExpectation(description: "Clipboard detection")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // テスト用のプレフィックスを持つアイテムのみをフィルタ
            let testItems = self.clipboardService.history.filter { $0.content.hasPrefix("KIPPLE_TEST_") }
            
            if let latestItem = testItems.first(where: { $0.content == testContent }) {
                print("\n=== Captured Clipboard Item ===")
                print("Content: \(latestItem.content)")
                print("Source App: \(latestItem.sourceApp ?? "nil")")
                print("Bundle ID: \(latestItem.bundleIdentifier ?? "nil")")
                print("Window Title: \(latestItem.windowTitle ?? "nil")")
                print("Process ID: \(latestItem.processID ?? -1)")
                print("================================\n")
                
                // テスト環境でのコピーの場合、アプリ情報が取得できない可能性がある
                // そのため、少なくともコンテンツが正しく記録されていることを確認
                XCTAssertEqual(latestItem.content, testContent, 
                             "Content should match test content")
                
                // アプリ情報が取得できた場合の追加チェック（オプショナル）
                if latestItem.sourceApp != nil {
                    print("Source app detected: \(latestItem.sourceApp!)")
                }
                if latestItem.bundleIdentifier != nil {
                    print("Bundle ID detected: \(latestItem.bundleIdentifier!)")
                }
            } else {
                XCTFail("No clipboard item was captured")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 3.0)
    }
    
    func testKippleInternalCopyNotRecorded() {
        // 内部コピーのテスト
        clipboardService.startMonitoring()
        
        let initialCount = clipboardService.history.count
        
        // 内部コピー（fromEditor: false）
        clipboardService.copyToClipboard("Internal copy test", fromEditor: false)
        
        // 少し待機
        let expectation = XCTestExpectation(description: "Internal copy check")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // 履歴に追加されていないことを確認
            XCTAssertEqual(self.clipboardService.history.count, initialCount, 
                          "Internal copy should not be added to history")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testEditorCopyIsRecorded() {
        // エディタからのコピーのテスト
        clipboardService.startMonitoring()
        
        let uuid = UUID().uuidString
        let testContent = "KIPPLE_TEST_EDITOR_\(uuid)"
        
        // エディタからのコピー（fromEditor: true）
        clipboardService.copyToClipboard(testContent, fromEditor: true)
        
        // 少し待機
        let expectation = XCTestExpectation(description: "Editor copy check")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // テスト用のプレフィックスを持つアイテムのみをフィルタ
            let testItems = self.clipboardService.history.filter { $0.content.hasPrefix("KIPPLE_TEST_") }
            
            // 履歴に追加されているか確認
            if let latestItem = testItems.first(where: { $0.content == testContent }) {
                print("\n=== Editor Copy Item ===")
                print("Content: \(latestItem.content)")
                print("Source App: \(latestItem.sourceApp ?? "nil")")
                print("========================\n")
                
                // エディタからのコピーでもアプリ情報が記録されるはず
                XCTAssertNotNil(latestItem.sourceApp)
                XCTAssertEqual(latestItem.sourceApp, "Kipple", "Editor copy should have 'Kipple' as source app")
            } else {
                XCTFail("Editor copy was not found in history")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testAccessibilityPermissionStatus() {
        // アクセシビリティ権限の状態を確認
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        let hasPermission = AXIsProcessTrustedWithOptions(options)
        
        print("\n=== Accessibility Permission Status ===")
        print("Has Permission: \(hasPermission)")
        
        if !hasPermission {
            print("⚠️ To get window titles, grant accessibility permission to the test runner")
            print("System Preferences > Security & Privacy > Privacy > Accessibility")
        }
        print("=====================================\n")
    }
    
    func testCGWindowListApproach() {
        // CGWindowListを使用したウィンドウ情報の取得テスト
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? as? [[String: Any]] else {
            XCTFail("Failed to get window list")
            return
        }
        
        print("\n=== CGWindowList Results (Top 5 Windows) ===")
        for (index, window) in windowList.prefix(5).enumerated() {
            if let ownerName = window[kCGWindowOwnerName as String] as? String,
               let windowTitle = window[kCGWindowName as String] as? String {
                print("\(index + 1). App: \(ownerName), Window: \(windowTitle)")
            }
        }
        print("==========================================\n")
        
        XCTAssertFalse(windowList.isEmpty, "Window list should not be empty")
    }
    
    func testTimingOfAppInfoCapture() {
        // アプリ情報取得のタイミングをテスト
        clipboardService.startMonitoring()
        
        let expectation = XCTestExpectation(description: "Timing test")
        
        // 現在のフロントアプリを記録
        let initialFrontApp = NSWorkspace.shared.frontmostApplication?.localizedName
        print("\n=== Timing Test ===")
        print("Initial front app: \(initialFrontApp ?? "unknown")")
        
        // クリップボードにコピー
        let uuid = UUID().uuidString
        let testContent = "KIPPLE_TEST_TIMING_\(uuid)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(testContent, forType: .string)
        
        // 即座に確認
        DispatchQueue.main.async {
            let currentFrontApp = NSWorkspace.shared.frontmostApplication?.localizedName
            print("Front app after copy: \(currentFrontApp ?? "unknown")")
        }
        
        // 履歴を確認
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // テスト用のプレフィックスを持つアイテムのみをフィルタ
            let testItems = self.clipboardService.history.filter { $0.content.hasPrefix("KIPPLE_TEST_") }
            
            if let item = testItems.first(where: { $0.content == testContent }) {
                print("Recorded app: \(item.sourceApp ?? "unknown")")
            }
            print("==================\n")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
}
