//
//  AppInfoRetrievalTests.swift
//  KippleTests
//
//  Created by Test on 2025/07/06.
//

import XCTest
import Cocoa
@testable import Kipple

final class AppInfoRetrievalTests: XCTestCase {
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
    
    func testCurrentAppInfoRetrieval() {
        // 現在のアプリ情報を取得してログに出力
        let frontApp = NSWorkspace.shared.frontmostApplication
        
        XCTAssertNotNil(frontApp)
    }
    
    func testManualClipboardCopy() {
        // 手動でクリップボードにコピーして、どのアプリが記録されるかテスト
        
        let expectation = XCTestExpectation(description: "Waiting for clipboard copy")
        
        clipboardService.startMonitoring()
        
        // 5秒待機して、その間にユーザーが他のアプリからコピーすることを期待
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if let latestItem = self.clipboardService.history.first {
            } else {
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 6.0)
    }
    
    func testAccessibilityPermission() {
        // アクセシビリティ権限の状態を確認
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessibilityEnabled {
        }
    }
    
    func testDelayedAppInfoCapture() {
        // クリップボード変更検出時のタイミング問題をテスト
        let expectation = XCTestExpectation(description: "Testing delayed app info capture")
        
        clipboardService.startMonitoring()
        
        // 別のアプリをアクティブにする時間を与える
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            // プログラムからクリップボードにコピー
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("Test from XCTest", forType: .string)
            
            // 少し待ってから結果を確認
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let item = self.clipboardService.history.first(where: { $0.content == "Test from XCTest" }) {
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testMultipleAppsSequence() {
        // 複数のアプリからのコピーをシミュレート
        
        let expectation = XCTestExpectation(description: "Multiple apps test")
        
        clipboardService.startMonitoring()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
            for (index, item) in self.clipboardService.history.enumerated() {
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 16.0)
    }
}
