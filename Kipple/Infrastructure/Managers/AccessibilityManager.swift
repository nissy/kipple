//
//  AccessibilityManager.swift
//  Kipple
//
//  Created by Kipple on 2025/07/06.
//

import Foundation
import ApplicationServices
import AppKit

@MainActor
final class AccessibilityManager {
    static let shared = AccessibilityManager()
    
    private var permissionTimer: Timer?
    private var lastCheckTime = Date(timeIntervalSince1970: 0)
    private var cachedPermissionStatus: Bool?
    private let cacheValidityDuration: TimeInterval = 1.0
    
    // Thread-safe access to cached data
    private let cacheQueue = DispatchQueue(label: "com.nissy.kipple.accessibility.cache", attributes: .concurrent)
    
    private init() {
        // Start monitoring permission changes
        startPermissionMonitoring()
    }
    
    private func startPermissionMonitoring() {
        // 既存タイマーを解除（多重登録防止）
        permissionTimer?.invalidate()
        permissionTimer = nil

        // Check permission status periodically
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let currentStatus = AXIsProcessTrusted()
            var previousStatus: Bool?
            
            self.cacheQueue.sync {
                previousStatus = self.cachedPermissionStatus
            }
            
            // If status changed, refresh cache and notify
            if let previous = previousStatus, previous != currentStatus {
                self.cacheQueue.async(flags: .barrier) {
                    self.cachedPermissionStatus = currentStatus
                    self.lastCheckTime = Date()
                }
                
                Logger.shared.info("Accessibility permission changed from \(previous) to \(currentStatus)")
                
                // Post notification for UI updates
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name("AccessibilityPermissionChanged"),
                        object: nil,
                        userInfo: ["hasPermission": currentStatus]
                    )
                }
            }
        }
    }

    // Check accessibility permission with caching (thread-safe)
    var hasPermission: Bool {
        // First, try to read cached value without blocking
        var cachedValue: (status: Bool, time: Date)?
        cacheQueue.sync {
            if let status = cachedPermissionStatus {
                cachedValue = (status, lastCheckTime)
            }
        }
        
        // Check if cached value is still valid
        if let cached = cachedValue {
            let now = Date()
            if now.timeIntervalSince(cached.time) < cacheValidityDuration {
                return cached.status
            }
        }
        
        // Need to refresh - use barrier to ensure exclusive access
        return cacheQueue.sync(flags: .barrier) {
            // Double-check in case another thread just updated
            let now = Date()
            if let cached = cachedPermissionStatus,
               now.timeIntervalSince(lastCheckTime) < cacheValidityDuration {
                return cached
            }
            
            // Check permission and update cache synchronously
            let status = AXIsProcessTrusted()
            cachedPermissionStatus = status
            lastCheckTime = now
            
            Logger.shared.info("Accessibility permission checked: \(status)")
            return status
        }
    }
    
    // Force refresh the cache (thread-safe)
    func refreshPermissionStatus() {
        cacheQueue.async(flags: .barrier) {
            self.cachedPermissionStatus = nil
            self.lastCheckTime = Date(timeIntervalSince1970: 0)
        }
    }
    
    // Request permission with options
    func requestPermission() -> Bool {
        if hasPermission {
            return true
        }
        
        let options = NSDictionary(dictionary: ["AXTrustedCheckOptionPrompt": true])
        return AXIsProcessTrustedWithOptions(options)
    }
    
    // Open system preferences
    static func openSystemPreferences() {
        let urls = [
            // Try the new format first (macOS 13+)
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            // Fallback to old format
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            // Alternative URL
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        
        for urlString in urls {
            if let url = URL(string: urlString) {
                if NSWorkspace.shared.open(url) {
                    Logger.shared.info("Opened system preferences with URL: \(urlString)")
                    return
                }
            }
        }
        
        // If all URLs fail, try to open System Settings app directly
        Logger.shared.warning("Failed to open specific accessibility settings, opening System Settings app")
        if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // Show accessibility alert with explanation
    func showAccessibilityAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = """
                Kipple needs Accessibility permission to capture app names and window titles from copied content.
                
                🔒 Privacy Guarantee:
                • Only captures app and window information when copying
                • NO keystrokes or personal data captured
                • NO data is sent to external servers
                • All processing happens locally on your Mac
                • Permission can be revoked anytime
                
                Please enable Kipple in:
                System Settings → Privacy & Security → Accessibility
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                AccessibilityManager.openSystemPreferences()
            }
        }
    }
}
