//
//  LastActiveAppTracker.swift
//  Kipple
//
//  Tracks the last active non-Kipple application to correctly record copy source
//

import Foundation
import AppKit

@MainActor
final class LastActiveAppTracker {
    // MARK: - Singleton

    static let shared = LastActiveAppTracker()

    // MARK: - Properties

    struct AppInfo {
        let name: String?
        let bundleId: String?
        let pid: Int32
    }
    private var lastActiveNonKippleApp: AppInfo?
    private var observer: Any?

    // MARK: - Initialization

    private init() {
        // Initialize with current frontmost app if it's not Kipple
        updateFromCurrentApp()
    }

    deinit {
        // Clean up observer if it exists
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Public Methods

    func startTracking() {
        // Stop any existing tracking
        stopTracking()

        // Initialize with current state
        updateFromCurrentApp()

        // Observe app activation
        let workspace = NSWorkspace.shared
        let notificationCenter = workspace.notificationCenter

        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self = self else { return }
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }

                // If it's not Kipple, store it as last active app
                if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                    self.lastActiveNonKippleApp = AppInfo(
                        name: app.localizedName,
                        bundleId: app.bundleIdentifier,
                        pid: app.processIdentifier
                    )

                    Logger.shared.log(
                        "Updated last active app: \(app.localizedName ?? "Unknown")"
                    )
                }
            }
        }
    }

    func stopTracking() {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    func getSourceAppInfo() -> AppInfo {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            // No frontmost app, use last known
            if let lastApp = lastActiveNonKippleApp {
                return lastApp
            }
            return AppInfo(name: nil, bundleId: nil, pid: 0)
        }

        let bundleId = frontApp.bundleIdentifier
        let kippleBundleId = Bundle.main.bundleIdentifier

        // If Kipple is frontmost, use the last active non-Kipple app
        if bundleId == kippleBundleId {
            if let lastApp = lastActiveNonKippleApp {
                Logger.shared.log(
                    "Kipple is frontmost, using last active app: \(lastApp.name ?? "Unknown")"
                )
                return lastApp
            }
            // Fallback to Kipple if no other app was tracked
            return AppInfo(
                name: frontApp.localizedName,
                bundleId: bundleId,
                pid: frontApp.processIdentifier
            )
        }

        // Not Kipple, return current app and update tracker
        let appInfo = AppInfo(
            name: frontApp.localizedName,
            bundleId: bundleId,
            pid: frontApp.processIdentifier
        )

        // Update last active non-Kipple app
        lastActiveNonKippleApp = appInfo

        return appInfo
    }

    // MARK: - Private Methods

    private func updateFromCurrentApp() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }

        // If current app is not Kipple, store it
        if frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastActiveNonKippleApp = AppInfo(
                name: frontApp.localizedName,
                bundleId: frontApp.bundleIdentifier,
                pid: frontApp.processIdentifier
            )
        }
    }
}
