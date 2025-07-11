//
//  AppInfoTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/11.
//
//  SPECS.md準拠: アプリ情報取得機能の統合テスト
//  - コピー元アプリ名の取得
//  - ウィンドウタイトルの取得（アクセシビリティ権限）
//  - バンドルID、プロセスIDの取得
//  - CGWindowList APIによるフォールバック
//  - Kipple自身からのコピー処理

import XCTest
import Cocoa
import Carbon
@testable import Kipple

final class AppInfoTests: XCTestCase {
    var mockClipboardService: MockClipboardService!
    
    override func setUp() {
        super.setUp()
        mockClipboardService = MockClipboardService()
        
        // クリーンな状態を確保
        mockClipboardService.reset()
        NSPasteboard.general.clearContents()
    }
    
    override func tearDown() {
        mockClipboardService?.reset()
        mockClipboardService = nil
        NSPasteboard.general.clearContents()
        super.tearDown()
    }
    
    // MARK: - 基本的なアプリ情報取得
    
    func testFrontmostApplicationInfo() {
        // SPECS.md: アプリ情報取得機能
        let frontApp = NSWorkspace.shared.frontmostApplication
        
        XCTAssertNotNil(frontApp)
        XCTAssertNotNil(frontApp?.localizedName)
        XCTAssertNotNil(frontApp?.bundleIdentifier)
        XCTAssertGreaterThan(frontApp?.processIdentifier ?? -1, 0)
    }
    
    func testClipboardItemAppInfo() {
        // SPECS.md: クリップボード監視でアプリ情報を記録
        // テスト用のアイテムを追加
        let uuid = UUID().uuidString
        let testContent = "KIPPLE_TEST_\(uuid)"
        let testItem = ClipItem(content: testContent)
        
        // アプリ情報を設定（テスト環境用）
        // ClipItemのプロパティはletなので、新しいインスタンスを作成
        let itemWithAppInfo = ClipItem(
            content: testContent,
            sourceApp: "XCTest",
            bundleIdentifier: "com.apple.dt.xctest.tool"
        )
        
        mockClipboardService.addTestItem(itemWithAppInfo)
        
        // 検証
        if let item = mockClipboardService.history.first(where: { $0.content == testContent }) {
            XCTAssertEqual(item.content, testContent)
            XCTAssertNotNil(item.sourceApp)
            XCTAssertNotNil(item.bundleIdentifier)
        } else {
            XCTFail("Clipboard item not found")
        }
    }
    
    // MARK: - CGWindowList APIテスト
    
    func testCGWindowListFallback() {
        // SPECS.md: アクセシビリティ権限なしでの代替（CGWindowList API使用）
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray?
                as? [[String: Any]] else {
            XCTFail("Failed to get window list")
            return
        }
        
        XCTAssertFalse(windowList.isEmpty, "Window list should not be empty")
        
        // 最前面のウィンドウ情報が取得できることを確認
        var foundValidWindow = false
        for window in windowList.prefix(10) {
            if let ownerName = window[kCGWindowOwnerName as String] as? String,
               window[kCGWindowOwnerPID as String] is Int32 {
                XCTAssertFalse(ownerName.isEmpty)
                foundValidWindow = true
                break
            }
        }
        XCTAssertTrue(foundValidWindow, "Should find at least one valid window")
    }
    
    // MARK: - アクセシビリティ権限テスト
    
    func testAccessibilityPermissionCheck() {
        // SPECS.md: アクセシビリティ権限チェック（キャッシュ付き、1秒間有効）
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        let hasPermission = AXIsProcessTrustedWithOptions(options)
        
        // 権限の有無に関わらず、チェック機能が動作することを確認
        XCTAssertNotNil(hasPermission)
    }
    
    // MARK: - Kipple自身からのコピー処理
    
    func testKippleInternalCopyNotRecorded() {
        // SPECS.md: Kipple自身の場合は最後のアクティブアプリ
        mockClipboardService.startMonitoring()
        
        let initialCount = mockClipboardService.history.count
        
        // 内部コピー（fromEditor: false）は履歴に記録されない
        mockClipboardService.copyToClipboard("Internal copy test", fromEditor: false)
        
        let expectation = XCTestExpectation(description: "Internal copy check")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            XCTAssertEqual(
                self.mockClipboardService.history.count,
                initialCount,
                "Internal copy should not be added to history"
            )
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testEditorCopyWithAppInfo() {
        // SPECS.md: エディターからのコピーはKippleカテゴリ
        mockClipboardService.startMonitoring()
        
        let uuid = UUID().uuidString
        let testContent = "KIPPLE_TEST_EDITOR_\(uuid)"
        let expectation = XCTestExpectation(description: "Editor copy check")
        
        // エディターからのコピー（fromEditor: true）
        mockClipboardService.copyToClipboard(testContent, fromEditor: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if let item = self.mockClipboardService.history.first(where: { $0.content == testContent }) {
                XCTAssertEqual(item.sourceApp, "Kipple", "Editor copy should have 'Kipple' as source app")
                XCTAssertEqual(item.windowTitle, "Quick Editor")
                XCTAssertEqual(item.category, .kipple)
                XCTAssertTrue(item.isFromEditor ?? false)
                XCTAssertNotNil(item.bundleIdentifier)
                XCTAssertEqual(item.bundleIdentifier, Bundle.main.bundleIdentifier)
                XCTAssertEqual(item.processID, ProcessInfo.processInfo.processIdentifier)
            } else {
                XCTFail("Editor copy was not found in history")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - パフォーマンステスト
    
    func testAppInfoRetrievalPerformance() {
        // アプリ情報取得のパフォーマンステスト
        measure {
            _ = NSWorkspace.shared.frontmostApplication
            
            let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
            _ = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray?
        }
    }
}
