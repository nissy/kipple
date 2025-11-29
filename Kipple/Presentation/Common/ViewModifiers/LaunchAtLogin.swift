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
        get { SMAppService.mainApp.status == .enabled }
        set { setEnabled(newValue) }
    }
    
    func setEnabled(_ enabled: Bool) {
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
    }
    
    func checkStatus() {
        _ = SMAppService.mainApp.status
    }
}
