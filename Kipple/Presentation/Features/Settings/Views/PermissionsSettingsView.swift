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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
                screenRecordingSection
                accessibilitySection
            }
            .padding(.horizontal, SettingsLayoutMetrics.scrollHorizontalPadding)
            .padding(.vertical, SettingsLayoutMetrics.scrollVerticalPadding)
        }
        .onAppear {
            refreshPermissions()
        }
        .onDisappear {
            stopPermissionPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private var screenRecordingSection: some View {
        SettingsGroup(
            "Screen Recording Permission",
            includeTopDivider: false
        ) {
            SettingsRow(label: "Request Access") {
                HStack(spacing: 10) {
                    Button("Request Permission Again") {
                        requestPermissionAgain()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color.accentColor)
                    .disabled(hasScreenCapturePermission)
                    PermissionStatusBadge(isGranted: hasScreenCapturePermission)
                }
            }

            SettingsRow(label: "Overview") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Why: Needed so Screen Text Capture can read on-screen text. No screen data leaves your Mac.")
                    Text("1. Click “Request Permission Again” and follow the macOS prompt to System Settings.")
                    Text("2. In System Settings → Privacy & Security → Screen Recording, enable “Kipple”.")
                    Text("Note: On macOS 15+, the section label is Screen & System Audio Recording.")
                    Text("3. Return to Kipple; the status badge switches to Granted automatically.")
                    Text("MDM Tip: Configure AllowStandardUserToSetSystemService for ScreenCapture.")
                    Text("This enables standard users to approve the permission.")
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
        }
    }

    private var accessibilitySection: some View {
        SettingsGroup(
            "Accessibility Permission",
            includeTopDivider: true
        ) {
            SettingsRow(label: "Request Access") {
                HStack(spacing: 10) {
                    Button("Request Permission Again") {
                        requestAccessibilityPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color.accentColor)
                    .disabled(hasAccessibilityPermission)
                    PermissionStatusBadge(isGranted: hasAccessibilityPermission)
                }
            }

            SettingsRow(label: "Overview") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Why: Lets Quick Paste watch Command+V for clipboard automation. Input stays on device.")
                    Text("1. Click “Request Permission Again” to trigger the macOS prompt or jump to System Settings.")
                    Text("2. In System Settings → Privacy & Security → Accessibility, enable “Kipple”.")
                    Text("3. Return to Kipple; the status badge switches to Granted automatically.")
                    Text("Tip: Granting Accessibility lets Kipple observe Command+V while running in the background.")
                    Text(LocalizedStringKey("Automation Prompt Tip"))
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
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
            refreshPermissions()
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
    static let accessibilityPermissionRequested = Notification.Name("AccessibilityPermissionRequested")
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
