//
//  GeneralSettingsView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import SwiftUI
import AppKit

struct GeneralSettingsView: View {
    var onOpenPermissions: () -> Void
    @ObservedObject private var launchAtLogin = LaunchAtLogin.shared
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode: Int = 0
    @AppStorage("hotkeyModifierFlags") private var hotkeyModifierFlags: Int = 0
    @AppStorage("windowAnimation") private var windowAnimation: String = "none"
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var plainTextHotkey = PlainTextPasteHotkey.shared

    @State private var tempKeyCode: UInt16 = 0
    @State private var tempModifierFlags: NSEvent.ModifierFlags = []
    @State private var selectedLanguage: AppSettings.LanguageOption = .system
    @State private var plainTextKeyCode: UInt16 = 9
    @State private var plainTextModifiers: NSEvent.ModifierFlags = [.control, .shift]
    @State private var plainTextHotkeyError: PlainTextPasteHotkey.ConfigurationError?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
                languageSection
                startupSection
                openKippleSection
                pasteSection
                windowAnimationSection
            }
            .padding(.horizontal, SettingsLayoutMetrics.scrollHorizontalPadding)
            .padding(.vertical, SettingsLayoutMetrics.scrollVerticalPadding)
        }
        .onAppear {
            launchAtLogin.checkStatus()
            tempKeyCode = UInt16(hotkeyKeyCode)
            tempModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifierFlags))
            selectedLanguage = appSettings.appLanguage
            plainTextHotkey.refreshPermission()
            loadPlainTextHotkey()
        }
        .onChange(of: selectedLanguage) { _, newValue in
            appSettings.appLanguage = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.checkStatus()
        }
        .onChange(of: plainTextHotkey.hasAccessibilityPermission) { _, _ in
            plainTextHotkeyError = nil
            loadPlainTextHotkey()
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                plainTextHotkey.refreshPermission()
            }
        }
    }

    private var languageSection: some View {
        SettingsGroup("Language", includeTopDivider: false) {
            SettingsRow(label: "App Language") {
                Picker("", selection: $selectedLanguage) {
                    ForEach(AppSettings.LanguageOption.allCases) { option in
                        Text(option.displayName)
                            .tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                .pickerStyle(MenuPickerStyle())
            }
        }
    }

    private var startupSection: some View {
        SettingsGroup("Startup") {
            SettingsRow(
                label: "Launch at login",
                isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) })
            )
            if launchAtLogin.status == .requiresApproval {
                SettingsRow(
                    label: "Approval required",
                    description: "Allow Kipple in Login Items to launch at login."
                ) {
                    Button("Open System Settings") { launchAtLogin.openSystemSettings() }
                }
            } else if launchAtLogin.status == .notFound {
                Text("The login item could not be found. Move Kipple to Applications and try again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var openKippleSection: some View {
        SettingsGroup("Open Kipple") {
            SettingsRow(label: "Global Hotkey") {
                HotkeyRecorderField(
                    keyCode: $tempKeyCode,
                    modifierFlags: $tempModifierFlags
                )
                .onChange(of: tempKeyCode) { _, _ in updateHotkey() }
                .onChange(of: tempModifierFlags) { _, _ in updateHotkey() }
            }
        }
    }

    private var windowAnimationSection: some View {
        SettingsGroup("Window Animation") {
            SettingsRow(label: "Animation style") {
                Picker("", selection: $windowAnimation) {
                    Text("None").tag("none")
                    Text("Fade").tag("fade")
                    Text("Slide").tag("slide")
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 200)
                .labelsHidden()
            }
        }
    }

    private var pasteSection: some View {
        SettingsGroup("Pasting") {
            SettingsRow(label: "Paste clipboard contents") { Text("⌘V") }
            SettingsRow(label: "Paste as Plain Text") {
                HotkeyRecorderField(
                    keyCode: $plainTextKeyCode,
                    modifierFlags: $plainTextModifiers,
                    onCommit: updatePlainTextHotkey
                )
                .disabled(!plainTextHotkey.hasAccessibilityPermission)
                .help("Click the shortcut field to change it. Clear disables the shortcut.")
            }
            if !plainTextHotkey.hasAccessibilityPermission {
                Text("Allow Device Control and Data Access to configure and use plain text paste.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Permission Settings", action: onOpenPermissions)
                    .controlSize(.small)
            } else if let plainTextHotkeyError {
                Text(plainTextHotkeyErrorMessage(plainTextHotkeyError))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if plainTextHotkey.registrationFailed {
                Text("The plain text shortcut is unavailable. Check for a conflicting shortcut in another app.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(
                "Plain text paste clears clipboard formatting. Select the history item again to restore formatting."
            )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func loadPlainTextHotkey() {
        plainTextKeyCode = plainTextHotkey.shortcut.keyCode
        plainTextModifiers = plainTextHotkey.shortcut.modifiers
    }

    private func updatePlainTextHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        plainTextHotkeyError = plainTextHotkey.apply(keyCode: keyCode, modifiers: modifiers)
        loadPlainTextHotkey()
    }

    private func plainTextHotkeyErrorMessage(_ error: PlainTextPasteHotkey.ConfigurationError) -> LocalizedStringKey {
        switch error {
        case .permissionRequired:
            "Allow Device Control and Data Access to configure and use plain text paste."
        case .modifierRequired:
            "Include Command, Control, or Option in the shortcut."
        case .shortcutUnavailable:
            "This shortcut is already in use. Your previous shortcut has been kept."
        }
    }

    private func updateHotkey() {
        hotkeyKeyCode = Int(tempKeyCode)
        hotkeyModifierFlags = Int(tempModifierFlags.rawValue)
        let shouldEnable = (hotkeyKeyCode != 0) && (hotkeyModifierFlags != 0)
        UserDefaults.standard.set(shouldEnable, forKey: "enableHotkey")

        NotificationCenter.default.post(
            name: NSNotification.Name("HotkeySettingsChanged"),
            object: nil,
            userInfo: [
                "keyCode": hotkeyKeyCode,
                "modifierFlags": hotkeyModifierFlags,
                "enabled": shouldEnable
            ]
        )
    }
}
