//
//  PermissionsSettingsView.swift
//  Kipple
//
//  Created by Kipple on 2025/10/13.
//

import SwiftUI
import AppKit
import CoreGraphics
import ApplicationServices

struct PermissionsSettingsView: View {
    @State private var hasScreenCapturePermission = CGPreflightScreenCaptureAccess()
    @State private var hasAccessibilityPermission = AXIsProcessTrusted()
    @State private var permissionPollingTimer: Timer?
    @ObservedObject private var clipboardReader = ClipboardReader.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
                screenRecordingSection
                accessibilitySection
                clipboardSection
            }
            .padding(.horizontal, SettingsLayoutMetrics.scrollHorizontalPadding)
            .padding(.vertical, SettingsLayoutMetrics.scrollVerticalPadding)
        }
        .onAppear {
            startPermissionPolling()
        }
        .onDisappear {
            stopPermissionPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    /// この権限がどの機能のために必要かを一目で示す行
    private func featureRow(
        _ featureName: LocalizedStringKey,
        description: LocalizedStringKey = "This feature is unavailable without this permission."
    ) -> some View {
        SettingsRow(
            label: "Used By",
            description: description
        ) {
            Text(featureName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var screenRecordingSection: some View {
        SettingsGroup(
            "Screen & System Audio Recording",
            includeTopDivider: false
        ) {
            featureRow(
                "Screen text capture and source window names",
                description:
                    "Without permission, screen text capture is unavailable and source window names may be missing."
            )

            SettingsRow(label: "Permission") {
                HStack(spacing: 10) {
                    Button(hasScreenCapturePermission ? "Open System Settings" : "Request Permission") {
                        requestPermissionAgain()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color.accentColor)
                    PermissionStatusBadge(isGranted: hasScreenCapturePermission)
                }
            }

            SettingsRow(label: "Overview") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "Kipple captures still images for OCR and reads source window names. It does not record audio."
                    )
                    Text("1. Use the button above and follow the macOS prompt to System Settings.")
                    Text(
                        "2. In System Settings → Privacy & Security → Screen & System Audio Recording, enable “Kipple”."
                    )
                    Text("3. Return to Kipple to check the permission status.")
                    permissionRecoveryInstructions
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accessibilitySection: some View {
        SettingsGroup(
            "Device Control and Data Access",
            includeTopDivider: true
        ) {
            featureRow("Paste on selection, plain text paste, and queue paste")

            SettingsRow(label: "Permission") {
                HStack(spacing: 10) {
                    Button(hasAccessibilityPermission ? "Open System Settings" : "Request Permission") {
                        requestAccessibilityPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color.accentColor)
                    PermissionStatusBadge(isGranted: hasAccessibilityPermission)
                }
            }

            SettingsRow(label: "Overview") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Why: Lets Kipple send paste commands to the frontmost app. Input stays on device.")
                    Text("1. Use the button above and follow the macOS prompt to System Settings.")
                    Text(
                        "2. In System Settings → Privacy & Security → Device Control and Data Access, enable “Kipple”."
                    )
                    Text("3. Return to Kipple to check the permission status.")
                    permissionRecoveryInstructions
                    Text("Input Monitoring permission is not required for queue paste or global shortcuts.")
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissionRecoveryInstructions: some View {
        Group {
            Text("If macOS requests a restart or the status remains Not Granted, quit and reopen Kipple.")
            Text(
                LocalizedStringKey(
                    "If it is still Not Granted, remove the old Kipple entry from this permission list, "
                        + "add the Kipple.app you are using, and enable it again."
                )
            )
        }
    }

    private var clipboardSection: some View {
        SettingsGroup("Clipboard Access") {
            featureRow(
                "Clipboard history and plain text paste",
                description: "macOS controls whether Kipple can read other apps’ clipboard contents."
            )
            SettingsRow(label: "Status") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(clipboardStatus)
                        .foregroundStyle(clipboardReader.accessBehavior == .alwaysDeny ? .orange : .secondary)
                    HStack {
                        Button("Check Clipboard Access") { _ = clipboardReader.read(retry: true) }
                            .disabled(clipboardReader.accessBehavior == .alwaysDeny)
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    .controlSize(.small)
                }
            }
            Text(LocalizedStringKey(
                "If macOS asks, allow clipboard access. If access is blocked, review Kipple in System Settings "
                    + "→ Privacy & Security. Kipple may appear there only after macOS first asks for access."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var clipboardStatus: LocalizedStringKey {
        if clipboardReader.readFailed { return "Clipboard could not be read. Check access and try again." }
        switch clipboardReader.accessBehavior {
        case .alwaysAllow: return "Clipboard reading is allowed"
        case .alwaysDeny: return "Clipboard reading is blocked"
        case .ask: return "macOS asks before reading"
        default: return "Controlled by macOS"
        }
    }

    @MainActor
    private func refreshScreenCapturePermission() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted != hasScreenCapturePermission {
            hasScreenCapturePermission = granted
        }
    }

    @MainActor
    private func refreshAccessibilityPermission() {
        let granted = AXIsProcessTrusted()
        if granted != hasAccessibilityPermission {
            hasAccessibilityPermission = granted
        }
    }

    @MainActor
    private func refreshPermissions() {
        refreshScreenCapturePermission()
        refreshAccessibilityPermission()
        clipboardReader.refreshAccess()
        SystemDiagnostics.permissions(
            screenCapture: hasScreenCapturePermission,
            accessibility: hasAccessibilityPermission,
            clipboard: clipboardReader.accessBehavior
        )
    }

    private func openSystemSettings() {
        startPermissionPolling()
        ScreenRecordingPermissionOpener.openSystemSettings()
    }

    private func requestPermissionAgain() {
        if hasScreenCapturePermission {
            openSystemSettings()
            return
        }

        startPermissionPolling()
        let didPrompt = CGRequestScreenCaptureAccess()
        if !didPrompt {
            openSystemSettings()
        }
    }

    @MainActor
    private func openAccessibilityPreferences() {
        startPermissionPolling()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private func requestAccessibilityPermission() {
        if hasAccessibilityPermission {
            openAccessibilityPreferences()
            return
        }

        startPermissionPolling()
        let options: [CFString: Bool] = ["AXTrustedCheckOptionPrompt" as CFString: true]
        let didPrompt = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !didPrompt {
            openAccessibilityPreferences()
        }
    }

    private func startPermissionPolling() {
        permissionPollingTimer?.invalidate()
        permissionPollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                refreshPermissions()
            }
        }
        if let timer = permissionPollingTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        refreshPermissions()
    }

    private func stopPermissionPolling() {
        permissionPollingTimer?.invalidate()
        permissionPollingTimer = nil
    }
}

extension Notification.Name {
    static let screenRecordingPermissionRequested = Notification.Name("ScreenRecordingPermissionRequested")
    static let queuePastePermissionRequested = Notification.Name("QueuePastePermissionRequested")
}

// MARK: - PermissionStatusBadge

struct PermissionStatusBadge: View {
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isGranted ? Color.green : Color.orange)
                .frame(width: 10, height: 10)

            Text(isGranted ? "Granted" : "Not Granted")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
    }
}
