//
//  LaunchAtLogin.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published private(set) var status: SMAppService.Status
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void

    init(
        readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
        register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }
    ) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        status = readStatus()
    }
    
    var isEnabled: Bool {
        get { status == .enabled || status == .requiresApproval }
        set { setEnabled(newValue) }
    }
    
    func setEnabled(_ enabled: Bool) {
        checkStatus()
        do {
            if enabled {
                if !isEnabled { try register() }
            } else if status != .notRegistered {
                try unregister()
            }
        } catch {
            SystemDiagnostics.failure("launchAtLogin", error: error)
            NotificationCenter.default.post(
                name: NSNotification.Name("LaunchAtLoginError"),
                object: nil,
                userInfo: ["error": error.localizedDescription]
            )
        }
        checkStatus()
    }
    
    func checkStatus() {
        status = readStatus()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
