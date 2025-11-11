//
//  LaunchAtLogin.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLogin {
    static let shared = LaunchAtLogin()
    
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
                        return
                    }
                    
                    try SMAppService.mainApp.register()
                } else {
                    if SMAppService.mainApp.status != .enabled {
                        return
                    }
                    
                    try SMAppService.mainApp.unregister()
                }
                
                // 設定を同期
                UserDefaults.standard.set(enabled, forKey: "autoLaunchAtLogin")
            } catch {
                let action = enabled ? "enable" : "disable"
                Logger.shared.error("Failed to \(action) launch at login: \(error.localizedDescription)")
                
                // エラーの詳細をユーザーに通知
                NotificationCenter.default.post(
                    name: NSNotification.Name("LaunchAtLoginError"),
                    object: nil,
                    userInfo: ["error": error.localizedDescription]
                )
            }
        } else {
            // Fallback for older versions
            Logger.shared.warning("Launch at login requires macOS 13.0 or later")
            UserDefaults.standard.set(enabled, forKey: "autoLaunchAtLogin")
        }
    }
    
    func checkStatus() {
        if #available(macOS 13.0, *) {
            _ = SMAppService.mainApp.status
        }
    }
}
