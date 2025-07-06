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
        
        print("=== Current Frontmost App Info ===")
        print("App Name: \(frontApp?.localizedName ?? "nil")")
        print("Bundle ID: \(frontApp?.bundleIdentifier ?? "nil")")
        print("Process ID: \(frontApp?.processIdentifier ?? -1)")
        print("================================")
        
        XCTAssertNotNil(frontApp)
    }
    
    func testManualClipboardCopy() {
        // 手動でクリップボードにコピーして、どのアプリが記録されるかテスト
        print("\n=== Manual Clipboard Test ===")
        print("Please copy some text from another app (e.g., Safari, Terminal) within 5 seconds...")
        
        let expectation = XCTestExpectation(description: "Waiting for clipboard copy")
        
        clipboardService.startMonitoring()
        
        // 5秒待機して、その間にユーザーが他のアプリからコピーすることを期待
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if let latestItem = self.clipboardService.history.first {
                print("\nCaptured clipboard item:")
                print("Content: \(latestItem.content.prefix(50))...")
                print("Source App: \(latestItem.sourceApp ?? "nil")")
                print("Window Title: \(latestItem.windowTitle ?? "nil")")
                print("Bundle ID: \(latestItem.bundleIdentifier ?? "nil")")
                print("Process ID: \(latestItem.processID ?? -1)")
            } else {
                print("No clipboard item captured")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 6.0)
    }
    
    func testAccessibilityPermission() {
        // アクセシビリティ権限の状態を確認
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        
        print("\n=== Accessibility Permission ===")
        print("Accessibility Enabled: \(accessibilityEnabled)")
        print("================================")
        
        if !accessibilityEnabled {
            print("⚠️ Accessibility permission is not granted. Window titles cannot be retrieved.")
        }
    }
    
    func testDelayedAppInfoCapture() {
        // クリップボード変更検出時のタイミング問題をテスト
        let expectation = XCTestExpectation(description: "Testing delayed app info capture")
        
        clipboardService.startMonitoring()
        
        // 別のアプリをアクティブにする時間を与える
        print("\n=== Delayed App Info Test ===")
        print("Switch to another app and copy text within 3 seconds...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            // プログラムからクリップボードにコピー
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("Test from XCTest", forType: .string)
            
            // 少し待ってから結果を確認
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let item = self.clipboardService.history.first(where: { $0.content == "Test from XCTest" }) {
                    print("\nProgrammatically copied item:")
                    print("Source App: \(item.sourceApp ?? "nil")")
                    print("Expected: Xcode or xctest")
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testMultipleAppsSequence() {
        // 複数のアプリからのコピーをシミュレート
        print("\n=== Multiple Apps Test ===")
        print("This test requires manual interaction:")
        print("1. Copy text from Safari")
        print("2. Copy text from Terminal")
        print("3. Copy text from Notes")
        print("You have 15 seconds...")
        
        let expectation = XCTestExpectation(description: "Multiple apps test")
        
        clipboardService.startMonitoring()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
            print("\n=== Captured History ===")
            for (index, item) in self.clipboardService.history.enumerated() {
                print("\nItem \(index + 1):")
                print("  Content: \(item.content.prefix(30))...")
                print("  App: \(item.sourceApp ?? "unknown")")
                print("  Window: \(item.windowTitle ?? "no title")")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 16.0)
    }
}
