#!/usr/bin/env swift

import Cocoa
import ApplicationServices

// 現在のフロントアプリ情報を取得
func getCurrentAppInfo() {
    guard let frontApp = NSWorkspace.shared.frontmostApplication else {
        print("Failed to get frontmost application")
        return
    }
    
    print("=== Current Frontmost App ===")
    print("Name: \(frontApp.localizedName ?? "unknown")")
    print("Bundle ID: \(frontApp.bundleIdentifier ?? "unknown")")
    print("Process ID: \(frontApp.processIdentifier)")
    print("Is Active: \(frontApp.isActive)")
}

// CGWindowListを使用してウィンドウ情報を取得
func getWindowsInfo() {
    print("\n=== Window List (Top 5) ===")
    
    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
    guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? as? [[String: Any]] else {
        print("Failed to get window list")
        return
    }
    
    for (index, window) in windowList.prefix(5).enumerated() {
        if let ownerName = window[kCGWindowOwnerName as String] as? String,
           let windowTitle = window[kCGWindowName as String] as? String,
           let pid = window[kCGWindowOwnerPID as String] as? Int32 {
            print("\(index + 1). App: \(ownerName)")
            print("   Window: \(windowTitle)")
            print("   PID: \(pid)")
            print("   Layer: \(window[kCGWindowLayer as String] ?? "unknown")")
        }
    }
}

// アプリ切り替えの監視
func monitorAppActivation() {
    print("\n=== Monitoring App Activation ===")
    print("Switch between apps for 10 seconds…")
    
    var recordedApps: [(Date, String)] = []
    
    let observer = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification,
        object: nil,
        queue: .main
    ) { notification in
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           let name = app.localizedName {
            recordedApps.append((Date(), name))
            print("App activated: \(name) at \(Date())")
        }
    }
    
    // 10秒間監視
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 10))
    
    NSWorkspace.shared.notificationCenter.removeObserver(observer)
    
    print("\n=== Recorded App Activations ===")
    for (date, app) in recordedApps {
        print("\(date): \(app)")
    }
}

// メイン処理
print("=== Kipple App Info Test ===")
getCurrentAppInfo()
getWindowsInfo()
monitorAppActivation()

print("\n=== Test Complete ===")
