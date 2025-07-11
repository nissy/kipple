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
        
        // 方法1: NSRunningApplicationからの情報取得
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps.prefix(5) where app.activationPolicy == .regular {
        }
        
        // 方法2: CGWindowListを使用したウィンドウ情報の取得
        testCGWindowList()
        
        // 方法3: NSDistributedNotificationCenterを使用したアプリ切り替えの監視
        testAppActivationNotifications()
    }
    
    func testCGWindowList() {
        
        // すべてのウィンドウ情報を取得
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? as? [[String: Any]]
        
        if let windows = windowList {
            
            // 最前面のウィンドウを探す
            for window in windows.prefix(5) {
                if let ownerName = window[kCGWindowOwnerName as String] as? String,
                   let windowTitle = window[kCGWindowName as String] as? String {
                }
            }
        }
    }
    
    func testAppActivationNotifications() {
        
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
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            notificationCenter.removeObserver(observer)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 6.0)
    }
    
    func testPasteboardChangeCountTiming() {
        
        let expectation = XCTestExpectation(description: "Pasteboard timing test")
        let pasteboard = NSPasteboard.general
        struct ChangeRecord {
            let time: Date
            let changeCount: Int
            let frontApp: String?
        }
        var changeRecords: [ChangeRecord] = []
        
        // 初期状態を記録
        let initialCount = pasteboard.changeCount
        
        // タイマーで監視
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let currentCount = pasteboard.changeCount
            if currentCount != changeRecords.last?.changeCount ?? initialCount {
                let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
                changeRecords.append(ChangeRecord(time: Date(), changeCount: currentCount, frontApp: frontApp))
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            timer.invalidate()
            
            for _ in changeRecords {
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 6.0)
    }
    
    func testEventTapForClipboardMonitoring() {
        
        // アクセシビリティ権限の確認
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        guard AXIsProcessTrustedWithOptions(options) else {
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
            return
        }
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            
            for event in capturedEvents {
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 6.0)
    }
}
