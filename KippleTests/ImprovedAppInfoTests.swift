//
//  ImprovedAppInfoTests.swift
//  KippleTests
//
//  Created by Test on 2025/07/06.
//

import XCTest
import Cocoa
import Carbon
@testable import Kipple

final class ImprovedAppInfoTests: XCTestCase {
    
    func testAlternativeAppInfoMethods() {
        print("\n=== Testing Alternative Methods ===")
        
        // 方法1: NSRunningApplicationからの情報取得
        let runningApps = NSWorkspace.shared.runningApplications
        print("\nRunning Applications (first 5):")
        for app in runningApps.prefix(5) {
            if app.activationPolicy == .regular {
                print("- \(app.localizedName ?? "Unknown"): \(app.bundleIdentifier ?? "no bundle ID")")
            }
        }
        
        // 方法2: CGWindowListを使用したウィンドウ情報の取得
        testCGWindowList()
        
        // 方法3: NSDistributedNotificationCenterを使用したアプリ切り替えの監視
        testAppActivationNotifications()
    }
    
    func testCGWindowList() {
        print("\n=== CGWindowList Info ===")
        
        // すべてのウィンドウ情報を取得
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? as? [[String: Any]]
        
        if let windows = windowList {
            print("Found \(windows.count) windows")
            
            // 最前面のウィンドウを探す
            for window in windows.prefix(5) {
                if let ownerName = window[kCGWindowOwnerName as String] as? String,
                   let windowTitle = window[kCGWindowName as String] as? String {
                    print("\nWindow:")
                    print("  Owner: \(ownerName)")
                    print("  Title: \(windowTitle)")
                    print("  Layer: \(window[kCGWindowLayer as String] ?? "unknown")")
                    print("  PID: \(window[kCGWindowOwnerPID as String] ?? "unknown")")
                }
            }
        }
    }
    
    func testAppActivationNotifications() {
        print("\n=== App Activation Notifications Test ===")
        
        let expectation = XCTestExpectation(description: "App activation test")
        var lastActiveApp: String?
        
        // アプリ切り替えの通知を監視
        let notificationCenter = NSWorkspace.shared.notificationCenter
        let observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                lastActiveApp = app.localizedName
                print("App activated: \(app.localizedName ?? "Unknown")")
            }
        }
        
        print("Switch between apps for 5 seconds...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            print("Last active app: \(lastActiveApp ?? "none detected")")
            notificationCenter.removeObserver(observer)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 6.0)
    }
    
    func testPasteboardChangeCountTiming() {
        print("\n=== Pasteboard Change Count Timing ===")
        
        let expectation = XCTestExpectation(description: "Pasteboard timing test")
        let pasteboard = NSPasteboard.general
        var changeRecords: [(time: Date, changeCount: Int, frontApp: String?)] = []
        
        // 初期状態を記録
        let initialCount = pasteboard.changeCount
        print("Initial change count: \(initialCount)")
        
        // タイマーで監視
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let currentCount = pasteboard.changeCount
            if currentCount != changeRecords.last?.changeCount ?? initialCount {
                let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
                changeRecords.append((Date(), currentCount, frontApp))
                print("Change detected! Count: \(currentCount), App: \(frontApp ?? "unknown")")
            }
        }
        
        print("Copy something from another app within 5 seconds...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            timer.invalidate()
            
            print("\n=== Change History ===")
            for record in changeRecords {
                print("Time: \(record.time), Count: \(record.changeCount), App: \(record.frontApp ?? "unknown")")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 6.0)
    }
    
    func testEventTapForClipboardMonitoring() {
        print("\n=== Event Tap Test (Requires Accessibility Permission) ===")
        
        // アクセシビリティ権限の確認
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        guard AXIsProcessTrustedWithOptions(options) else {
            print("❌ Accessibility permission not granted. Skipping event tap test.")
            return
        }
        
        let expectation = XCTestExpectation(description: "Event tap test")
        var capturedEvents: [(app: String?, action: String)] = []
        
        // イベントタップの作成
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .keyDown {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                
                // Cmd+C (keyCode 8 = C)
                if keyCode == 8 && flags.contains(.maskCommand) {
                    let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
                    print("Cmd+C detected! App: \(frontApp ?? "unknown")")
                }
            }
            return Unmanaged.passRetained(event)
        }
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: nil
        ) else {
            print("Failed to create event tap")
            return
        }
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        print("Event tap active. Press Cmd+C in different apps for 5 seconds...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            
            print("\nCaptured events:")
            for event in capturedEvents {
                print("App: \(event.app ?? "unknown"), Action: \(event.action)")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 6.0)
    }
}
