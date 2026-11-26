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

    static func singleVisibleWindowTitle(for pid: Int32) -> String? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let matching = windows.filter {
            $0[kCGWindowOwnerPID as String] as? Int32 == pid && $0[kCGWindowLayer as String] as? Int == 0
        }
        guard matching.count == 1,
              let title = matching[0][kCGWindowName as String] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return title
    }

    private var lastActiveNonKippleApp: AppInfo?
    private var clipboardActivation: (processID: pid_t, changeCount: Int)?
    private nonisolated(unsafe) var observer: Any?

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
        clipboardActivation = NSWorkspace.shared.frontmostApplication.map {
            ($0.processIdentifier, NSPasteboard.general.changeCount)
        }

        // Observe app activation
        let workspace = NSWorkspace.shared
        let notificationCenter = workspace.notificationCenter

        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }

            MainActor.assumeIsolated {
                guard let self else { return }
                self.clipboardActivation = (app.processIdentifier, NSPasteboard.general.changeCount)
                // If it's not Kipple, store it as last active app
                if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                    self.lastActiveNonKippleApp = AppInfo(
                        name: app.localizedName,
                        bundleId: app.bundleIdentifier,
                        pid: app.processIdentifier
                    )

                    // noisy: アプリ切替のたびに発火するため削除
                }
            }
        }
    }

    func stopTracking() {
        clipboardActivation = nil
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    func foregroundApp(forClipboardChange changeCount: Int) -> NSRunningApplication? {
        // A clipboard revision already present at activation may belong to the previous app.
        guard let activation = clipboardActivation,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier == activation.processID,
              changeCount > activation.changeCount else { return nil }
        return app
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
                // noisy: 毎回出るため削除
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

    /// 直前にアクティブだった非Kippleアプリを再アクティブ化
    func activateLastTrackedAppIfAvailable() {
        guard let candidate = lastActiveNonKippleApp else { return }

        if let runningApp = NSRunningApplication(processIdentifier: candidate.pid) {
            activate(runningApp)
            return
        }

        if let bundleId = candidate.bundleId {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            if let app = apps.first {
                activate(app)
            }
        }
    }

    func updateLastActiveApp(_ info: AppInfo) {
        lastActiveNonKippleApp = info
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

    private func activate(_ app: NSRunningApplication) {
        // default ([]) なら main/key window のみ復帰され、ユーザー直前のウインドウが key に戻りやすい
        app.activate(options: [])
    }
}
@MainActor
protocol LastActiveAppTracking: AnyObject {
    func getSourceAppInfo() -> LastActiveAppTracker.AppInfo
    func activateLastTrackedAppIfAvailable()
    func updateLastActiveApp(_ info: LastActiveAppTracker.AppInfo)
}

extension LastActiveAppTracker: LastActiveAppTracking {}
