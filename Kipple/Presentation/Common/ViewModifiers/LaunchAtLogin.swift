//
//  LaunchAtLogin.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import Foundation
import ServiceManagement

@MainActor
class LaunchAtLogin {
    static let shared = LaunchAtLogin()
    
    private let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.Kipple"
    
    private init() {}
    
    var isEnabled: Bool {
        get {
            // macOS 13.0以降のAPI
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                // Fallback for older versions
                return UserDefaults.standard.bool(forKey: "autoLaunchAtLogin")
            }
        }
        set {
            setEnabled(newValue)
        }
    }
    
    func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status == .enabled {
                        Logger.shared.info("Launch at login is already enabled")
                        return
                    }
                    
                    try SMAppService.mainApp.register()
                    Logger.shared.info("Successfully enabled launch at login")
                } else {
                    if SMAppService.mainApp.status != .enabled {
                        Logger.shared.info("Launch at login is already disabled")
                        return
                    }
                    
                    try SMAppService.mainApp.unregister()
                    Logger.shared.info("Successfully disabled launch at login")
                }
                
                // 設定を同期
                UserDefaults.standard.set(enabled, forKey: "autoLaunchAtLogin")
            } catch {
                let action = enabled ? "enable" : "disable"
                Logger.shared.error("Failed to \(action) launch at login: \(error.localizedDescription)")
                
                // エラーの詳細をユーザーに通知
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("LaunchAtLoginError"),
                        object: nil,
                        userInfo: ["error": error.localizedDescription]
                    )
                }
            }
        } else {
            // Fallback for older versions
            Logger.shared.warning("Launch at login requires macOS 13.0 or later")
            UserDefaults.standard.set(enabled, forKey: "autoLaunchAtLogin")
        }
    }
    
    func checkStatus() {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            switch status {
            case .enabled:
                Logger.shared.debug("Launch at login status: enabled")
            case .notRegistered:
                Logger.shared.debug("Launch at login status: not registered")
            case .notFound:
                Logger.shared.debug("Launch at login status: not found")
            case .requiresApproval:
                Logger.shared.debug("Launch at login status: requires approval")
            @unknown default:
                Logger.shared.debug("Launch at login status: unknown")
            }
        }
    }
}
