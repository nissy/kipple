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
    @AppStorage("textCaptureHotkeyKeyCode") private var textCaptureHotkeyKeyCode: Int = 0
    @AppStorage("textCaptureHotkeyModifierFlags") private var textCaptureHotkeyModifierFlags: Int = 0

    @State private var tempCaptureKeyCode: UInt16 = 17
    @State private var tempCaptureModifierFlags: NSEvent.ModifierFlags = [.command, .shift]
    @State private var hasScreenCapturePermission = CGPreflightScreenCaptureAccess()
    @State private var hasAccessibilityPermission = AXIsProcessTrusted()
    @State private var captureHotkeyError: String?
    @State private var permissionPollingTimer: Timer?

    private let defaultCaptureKeyCode: UInt16 = 17
    private let defaultCaptureModifierFlags: NSEvent.ModifierFlags = [.command, .shift]

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
            loadCaptureHotkeyState()
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
            includeTopDivider: false,
            headerAccessory: AnyView(
                PermissionStatusBadge(isGranted: hasScreenCapturePermission)
            )
        ) {
            SettingsRow(label: "Request Access") {
                HStack {
                    Button("Request Permission Again") {
                        requestPermissionAgain()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color.accentColor)
                    .disabled(hasScreenCapturePermission)
                }
            }

            SettingsRow(label: "Overview") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Open System Settings → Privacy & Security → Screen & System Audio Recording.")
                    Text("2. Turn on the toggle next to “Kipple”.")
                    Text("3. Return to Kipple; this screen updates automatically.")
                    Text("MDM Tip: Configure AllowStandardUserToSetSystemService for ScreenCapture.")
                    Text("This enables standard users to approve the permission.")
                    Text("Once granted, configure the screen text capture shortcut in the section below.")
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }

            SettingsRow(label: "Text Capture Shortcut") {
                VStack(alignment: .leading, spacing: 8) {
                    HotkeyRecorderField(
                        keyCode: $tempCaptureKeyCode,
                        modifierFlags: $tempCaptureModifierFlags
                    )
                    .disabled(!hasScreenCapturePermission)
                    .onChange(of: tempCaptureKeyCode) { _ in updateCaptureHotkey() }
                    .onChange(of: tempCaptureModifierFlags) { _ in updateCaptureHotkey() }

                    if let captureHotkeyError {
                        Text(captureHotkeyError)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    } else if hasScreenCapturePermission {
                        Text("Shortcut is ready to use. Hold the selected modifiers and key to capture text.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Enable Screen Recording permission to configure the text capture shortcut.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var accessibilitySection: some View {
        SettingsGroup(
            "Accessibility Permission",
            headerAccessory: AnyView(
                PermissionStatusBadge(isGranted: hasAccessibilityPermission)
            )
        ) {
            SettingsRow(label: "Request Access") {
                HStack {
                    Button("Request Permission Again") {
                        requestAccessibilityPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color.accentColor)
                    .disabled(hasAccessibilityPermission)
                }
            }

            SettingsRow(label: "Overview") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Open System Settings → Privacy & Security → Accessibility.")
                    Text("2. Turn on the toggle next to “Kipple”.")
                    Text("3. Return to Kipple; this screen updates automatically.")
                    Text("Tip: This allows Kipple to observe Command+V while running in the background.")
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
        }
    }

    private func loadCaptureHotkeyState() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: TextCaptureHotkeyManager.keyCodeDefaultsKey) == nil {
            defaults.set(Int(defaultCaptureKeyCode), forKey: TextCaptureHotkeyManager.keyCodeDefaultsKey)
        }
        if defaults.object(forKey: TextCaptureHotkeyManager.modifierDefaultsKey) == nil {
            defaults.set(Int(defaultCaptureModifierFlags.rawValue), forKey: TextCaptureHotkeyManager.modifierDefaultsKey)
        }

        textCaptureHotkeyKeyCode = defaults.integer(forKey: TextCaptureHotkeyManager.keyCodeDefaultsKey)
        textCaptureHotkeyModifierFlags = defaults.integer(forKey: TextCaptureHotkeyManager.modifierDefaultsKey)

        tempCaptureKeyCode = UInt16(textCaptureHotkeyKeyCode)
        tempCaptureModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(textCaptureHotkeyModifierFlags))

        if hasScreenCapturePermission {
            captureHotkeyError = nil
            updateCaptureHotkey()
        } else {
            disableCaptureHotkey()
        }
    }

    @MainActor
    private func updateCaptureHotkey() {
        let manager = TextCaptureHotkeyManager.shared

        guard hasScreenCapturePermission else {
            disableCaptureHotkey()
            return
        }

        let keyCode = tempCaptureKeyCode
        let modifiers = tempCaptureModifierFlags

        guard keyCode != 0, !modifiers.isEmpty else {
            captureHotkeyError = "Select a key and modifier to enable the shortcut."
            disableCaptureHotkey()
            return
        }

        let success = manager.applyHotKey(
            keyCode: keyCode,
            modifiers: modifiers
        )

        if success {
            textCaptureHotkeyKeyCode = Int(keyCode)
            textCaptureHotkeyModifierFlags = Int(modifiers.rawValue)
            captureHotkeyError = nil
            postCaptureHotkeyUpdate(
                keyCode: Int(keyCode),
                modifierFlags: Int(modifiers.rawValue),
                enabled: true
            )
        } else {
            captureHotkeyError = "The selected shortcut is already taken. Try another combination."
        }
    }

    private func disableCaptureHotkey() {
        let manager = TextCaptureHotkeyManager.shared
        _ = manager.applyHotKey(keyCode: 0, modifiers: [])
        postCaptureHotkeyUpdate(
            keyCode: 0,
            modifierFlags: 0,
            enabled: false
        )
    }

    @MainActor
    private func refreshScreenCapturePermission() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted != hasScreenCapturePermission {
            hasScreenCapturePermission = granted
            if granted {
                stopPermissionPolling()
                loadCaptureHotkeyState()
            } else {
                captureHotkeyError = nil
                disableCaptureHotkey()
            }
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

    private func openPermissionTab() {
        NotificationCenter.default.post(
            name: .screenRecordingPermissionRequested,
            object: nil,
            userInfo: nil
        )
        startPermissionPolling()
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

    private func postCaptureHotkeyUpdate(keyCode: Int, modifierFlags: Int, enabled: Bool) {
        NotificationCenter.default.post(
            name: NSNotification.Name("TextCaptureHotkeySettingsChanged"),
            object: nil,
            userInfo: [
                "keyCode": keyCode,
                "modifierFlags": modifierFlags,
                "enabled": enabled
            ]
        )
    }
}

extension Notification.Name {
    static let screenRecordingPermissionRequested = Notification.Name("ScreenRecordingPermissionRequested")
}

// MARK: - PermissionStatusBadge

private struct PermissionStatusBadge: View {
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
