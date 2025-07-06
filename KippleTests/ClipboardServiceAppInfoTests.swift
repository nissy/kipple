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
        clipboardService.clearAllHistory()
    }
    
    override func tearDown() {
        clipboardService.stopMonitoring()
        clipboardService.clearAllHistory()
        clipboardService = nil
        super.tearDown()
    }
    
    func testAppInfoCapture() {
        // テスト用のクリップボードサービスを作成
        clipboardService.startMonitoring()
        
        // テスト内容をクリップボードにコピー
        let testContent = "Test from XCTest at \(Date())"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(testContent, forType: .string)
        
        // クリップボードサービスが検出するまで待機
        let expectation = XCTestExpectation(description: "Clipboard detection")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // 履歴を確認
            if let latestItem = self.clipboardService.history.first {
                print("\n=== Captured Clipboard Item ===")
                print("Content: \(latestItem.content)")
                print("Source App: \(latestItem.sourceApp ?? "nil")")
                print("Bundle ID: \(latestItem.bundleIdentifier ?? "nil")")
                print("Window Title: \(latestItem.windowTitle ?? "nil")")
                print("Process ID: \(latestItem.processID ?? -1)")
                print("================================\n")
                
                // XCTestからのコピーの場合、Xcodeが記録されているはず
                XCTAssertNotNil(latestItem.sourceApp, "Source app should not be nil")
                
                // Bundle IDが記録されているか確認
                XCTAssertNotNil(latestItem.bundleIdentifier, "Bundle ID should not be nil")
            } else {
                XCTFail("No clipboard item was captured")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
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
        
        let testContent = "Editor copy test at \(Date())"
        
        // エディタからのコピー（fromEditor: true）
        clipboardService.copyToClipboard(testContent, fromEditor: true)
        
        // 少し待機
        let expectation = XCTestExpectation(description: "Editor copy check")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // 履歴に追加されているか確認
            if let latestItem = self.clipboardService.history.first(where: { $0.content == testContent }) {
                print("\n=== Editor Copy Item ===")
                print("Content: \(latestItem.content)")
                print("Source App: \(latestItem.sourceApp ?? "nil")")
                print("========================\n")
                
                // エディタからのコピーでもアプリ情報が記録されるはず
                XCTAssertNotNil(latestItem.sourceApp)
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
        let testContent = "Timing test at \(Date())"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(testContent, forType: .string)
        
        // 即座に確認
        DispatchQueue.main.async {
            let currentFrontApp = NSWorkspace.shared.frontmostApplication?.localizedName
            print("Front app after copy: \(currentFrontApp ?? "unknown")")
        }
        
        // 履歴を確認
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let item = self.clipboardService.history.first {
                print("Recorded app: \(item.sourceApp ?? "unknown")")
            }
            print("==================\n")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
}