//
//  ClipboardServiceAppMonitoring.swift
//  Kipple
//
//  Created by Kipple on 2025/07/18.
//

import Cocoa
import ApplicationServices

// MARK: - App Monitoring
// This extension handles app switching detection and window information retrieval
extension ClipboardService {
    
    // MARK: - App Info Structure
    
    struct AppInfo {
        let appName: String?
        let windowTitle: String?
        let bundleId: String?
        let pid: Int32?
    }
    
    // MARK: - App Activation Monitoring
    
    func setupAppActivationMonitoring() {
        // 既存のオブザーバがあれば解除（多重登録によるリーク防止）
        stopAppActivationMonitoring()
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier,
                  bundleId != Bundle.main.bundleIdentifier else { return }
            
            self?.lastActiveNonKippleApp = LastActiveApp(
                name: app.localizedName,
                bundleId: bundleId,
                pid: app.processIdentifier
            )
            
            Logger.shared.debug("Recorded non-Kipple app: \(app.localizedName ?? "unknown")")
        }
    }
    
    func stopAppActivationMonitoring() {
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appActivationObserver = nil
        }
    }
    
    // MARK: - App Info Retrieval
    
    func getActiveAppInfo() -> AppInfo {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return AppInfo(appName: nil, windowTitle: nil, bundleId: nil, pid: nil)
        }
        
        // Kipple自身の場合は、最後にアクティブだった他のアプリを取得
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            return getLastActiveNonKippleApp()
        }
        
        let appName = frontApp.localizedName
        let bundleId = frontApp.bundleIdentifier
        let pid = frontApp.processIdentifier
        
        // ウィンドウタイトルを取得
        var windowTitle: String?
        
        if hasAccessibilityPermission() {
            windowTitle = getWindowTitle(for: bundleId ?? "", processId: pid)
        }
        
        if windowTitle == nil {
            windowTitle = getWindowTitleViaCGWindowList(processId: pid)
        }
        
        Logger.shared.debug("Captured app info: \(appName ?? "unknown") (\(bundleId ?? "unknown"))")
        
        return AppInfo(appName: appName, windowTitle: windowTitle, bundleId: bundleId, pid: pid)
    }
    
    private func getLastActiveNonKippleApp() -> AppInfo {
        if let lastApp = lastActiveNonKippleApp {
            Logger.shared.debug("Using last active non-Kipple app: \(lastApp.name ?? "unknown")")
            
            var windowTitle: String?
            if let lastPid = lastApp.pid {
                if hasAccessibilityPermission() {
                    windowTitle = getWindowTitle(for: lastApp.bundleId ?? "", processId: lastPid)
                }
                if windowTitle == nil {
                    windowTitle = getWindowTitleViaCGWindowList(processId: lastPid)
                }
            }
            
            return AppInfo(
                appName: lastApp.name,
                windowTitle: windowTitle,
                bundleId: lastApp.bundleId,
                pid: lastApp.pid
            )
        }
        
        return AppInfo(appName: nil, windowTitle: nil, bundleId: nil, pid: nil)
    }
    
    // MARK: - Window Title Retrieval
    
    private func getWindowTitle(for bundleId: String, processId: Int32) -> String? {
        let app = AXUIElementCreateApplication(processId)
        
        var value: AnyObject?
        var result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
        
        if result != .success {
            result = AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &value)
        }
        
        if result != .success {
            result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
            if result == .success, let windows = value as? [AXUIElement], !windows.isEmpty {
                value = windows[0] as AnyObject
            }
        }
        
        if result == .success, let windowValue = value {
            guard CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
                return nil
            }
            let window = unsafeBitCast(windowValue, to: AXUIElement.self)
            
            var titleValue: AnyObject?
            let titleResult = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            
            if titleResult == .success, let title = titleValue as? String, !title.isEmpty {
                return title
            }
        }
        
        return nil
    }
    
    private func getWindowTitleViaCGWindowList(processId: Int32) -> String? {
        let windowOptions: CGWindowListOption = [.excludeDesktopElements, .optionOnScreenOnly]
        let windowList = CGWindowListCopyWindowInfo(windowOptions, kCGNullWindowID) as? [[String: Any]] ?? []
        
        for window in windowList {
            guard let windowPid = window[kCGWindowOwnerPID as String] as? Int32,
                  windowPid == processId,
                  let windowName = window[kCGWindowName as String] as? String,
                  !windowName.isEmpty else { continue }
            
            return windowName
        }
        
        return nil
    }
    
    private func hasAccessibilityPermission() -> Bool {
        return AccessibilityManager.shared.hasPermission
    }
}
