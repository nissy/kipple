//
//  GeneralSettingsView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import SwiftUI
import AppKit

struct GeneralSettingsView: View {
    @AppStorage("autoLaunchAtLogin") private var autoLaunchAtLogin = false
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode: Int = 0
    @AppStorage("hotkeyModifierFlags") private var hotkeyModifierFlags: Int = 0
    @AppStorage("textCaptureHotkeyKeyCode") private var textCaptureHotkeyKeyCode: Int = 0
    @AppStorage("textCaptureHotkeyModifierFlags") private var textCaptureHotkeyModifierFlags: Int = 0
    @AppStorage("windowAnimation") private var windowAnimation: String = "none"
    
    @State private var tempKeyCode: UInt16 = 0
    @State private var tempModifierFlags: NSEvent.ModifierFlags = []
    @State private var tempCaptureKeyCode: UInt16 = 17
    @State private var tempCaptureModifierFlags: NSEvent.ModifierFlags = [.command, .shift]
    @State private var hasScreenCapturePermission = CGPreflightScreenCaptureAccess()
    @State private var captureHotkeyError: String?
    @State private var permissionPollingTimer: Timer?
    
    private let defaultCaptureKeyCode: UInt16 = 17
    private let defaultCaptureModifierFlags: NSEvent.ModifierFlags = [.command, .shift]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
                // Startup
                SettingsGroup("Startup", includeTopDivider: false) {
                    SettingsRow(
                        label: "Launch at login",
                        isOn: $autoLaunchAtLogin
                    )
                    .onChange(of: autoLaunchAtLogin) { newValue in
                        LaunchAtLogin.shared.isEnabled = newValue
                    }
                }
                
                // Global Hotkey
                SettingsGroup("Open Kipple") {
                    SettingsRow(
                        label: "Global Hotkey"
                    ) {
                        HotkeyRecorderField(
                            keyCode: $tempKeyCode,
                            modifierFlags: $tempModifierFlags
                        )
                        .onChange(of: tempKeyCode) { _ in updateHotkey() }
                        .onChange(of: tempModifierFlags) { _ in updateHotkey() }
                    }
                }
                
                SettingsGroup(
                    "Screen Text Capture",
                    headerAccessory: AnyView(
                        PermissionStatusBadge(isGranted: hasScreenCapturePermission)
                    )
                ) {
                    SettingsRow(
                        label: "Screen Recording Access",
                        layout: .inlineControl
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            Button("Open System Settings") {
                                openScreenRecordingSettings()
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 12))

                            if hasScreenCapturePermission {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Access granted.")
                                    Text("Open System Settings › Privacy & Security.")
                                    Text("Select Screen & System Audio Recording to review apps.")
                                }
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Screen access is required for capture overlay.")
                                    Text("Enable Kipple in System Settings › Privacy & Security.")
                                    Text("Then open Screen & System Audio Recording.")
                                }
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    
                    SettingsRow(
                        label: "Global Hotkey"
                    ) {
                        HotkeyRecorderField(
                            keyCode: $tempCaptureKeyCode,
                            modifierFlags: $tempCaptureModifierFlags
                        )
                        .disabled(!hasScreenCapturePermission)
                        .onChange(of: tempCaptureKeyCode) { _ in updateCaptureHotkey() }
                        .onChange(of: tempCaptureModifierFlags) { _ in updateCaptureHotkey() }
                    }

                    if let captureHotkeyError {
                        Text(captureHotkeyError)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .padding(.leading, 4)
                    }
                }
                
                // Window Animation
                SettingsGroup("Window Animation") {
                    SettingsRow(
                        label: "Animation style"
                    ) {
                        Picker("", selection: $windowAnimation) {
                            Text("None").tag("none")
                            Text("Fade").tag("fade")
                            Text("Slide").tag("slide")
                            Text("Scale").tag("scale")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 200)
                        .labelsHidden()
                    }
                }
            }
            .padding(.horizontal, SettingsLayoutMetrics.scrollHorizontalPadding)
            .padding(.vertical, SettingsLayoutMetrics.scrollVerticalPadding)
        }
        .onAppear {
            tempKeyCode = UInt16(hotkeyKeyCode)
            tempModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifierFlags))
            loadCaptureHotkeyState()
            refreshScreenCapturePermission()
        }
        .onDisappear {
            stopPermissionPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshScreenCapturePermission()
        }
    }
    
    private func updateHotkey() {
        hotkeyKeyCode = Int(tempKeyCode)
        hotkeyModifierFlags = Int(tempModifierFlags.rawValue)
        // Clear(= no key) の場合は無効と見なす
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
    
    @MainActor
    private func updateCaptureHotkey() {
        guard hasScreenCapturePermission else { return }
        
        // 重複チェック（メインパネル用ホットキーと同一の場合は不可）
        if tempCaptureKeyCode != 0,
           !tempCaptureModifierFlags.isEmpty,
           Int(tempCaptureKeyCode) == hotkeyKeyCode,
           Int(tempCaptureModifierFlags.rawValue) == hotkeyModifierFlags {
            captureHotkeyError = "Shortcut conflicts with the toggle hotkey. Choose another combination."
            tempCaptureKeyCode = 0
            tempCaptureModifierFlags = []
            textCaptureHotkeyKeyCode = 0
            textCaptureHotkeyModifierFlags = 0
            _ = TextCaptureHotkeyManager.shared.applyHotKey(keyCode: 0, modifiers: [])
            return
        }

        let manager = TextCaptureHotkeyManager.shared
        let success = manager.applyHotKey(keyCode: tempCaptureKeyCode, modifiers: tempCaptureModifierFlags)
        guard success else {
            captureHotkeyError = "Failed to register shortcut. Try a different combination."
            tempCaptureKeyCode = UInt16(textCaptureHotkeyKeyCode)
            tempCaptureModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(textCaptureHotkeyModifierFlags))
            return
        }

        captureHotkeyError = nil
        
        textCaptureHotkeyKeyCode = Int(tempCaptureKeyCode)
        textCaptureHotkeyModifierFlags = Int(tempCaptureModifierFlags.rawValue)
        
        let enabled = (tempCaptureKeyCode != 0) && !tempCaptureModifierFlags.isEmpty
        
        NotificationCenter.default.post(
            name: NSNotification.Name("TextCaptureHotkeySettingsChanged"),
            object: nil,
            userInfo: [
                "keyCode": textCaptureHotkeyKeyCode,
                "modifierFlags": textCaptureHotkeyModifierFlags,
                "enabled": enabled
            ]
        )
    }
    
    private func loadCaptureHotkeyState() {
        // 初期値未設定の場合はデフォルトを適用
        if UserDefaults.standard.object(forKey: "textCaptureHotkeyKeyCode") == nil {
            textCaptureHotkeyKeyCode = Int(defaultCaptureKeyCode)
        }
        if UserDefaults.standard.object(forKey: "textCaptureHotkeyModifierFlags") == nil {
            textCaptureHotkeyModifierFlags = Int(defaultCaptureModifierFlags.rawValue)
        }
        
        tempCaptureKeyCode = UInt16(textCaptureHotkeyKeyCode)
        tempCaptureModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(textCaptureHotkeyModifierFlags))

        if hasScreenCapturePermission {
            captureHotkeyError = nil
            updateCaptureHotkey()
        }
    }
    
    private func refreshScreenCapturePermission() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted != hasScreenCapturePermission {
            hasScreenCapturePermission = granted
            if granted {
                stopPermissionPolling()
                loadCaptureHotkeyState()
            } else {
                captureHotkeyError = nil
            }
        }
    }
    
    private func openScreenRecordingSettings() {
        startPermissionPolling()

        ScreenRecordingPermissionOpener.openSystemSettings()
    }

    private func startPermissionPolling() {
        permissionPollingTimer?.invalidate()
        permissionPollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            refreshScreenCapturePermission()
        }
        if let timer = permissionPollingTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        refreshScreenCapturePermission()
    }

    private func stopPermissionPolling() {
        permissionPollingTimer?.invalidate()
        permissionPollingTimer = nil
    }
}

// MARK: - ModifierKeyPicker
struct ModifierKeyPicker: View {
    @Binding var selection: Int
    
    private var modifierFlags: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: UInt(selection)) }
        set { selection = Int(newValue.rawValue) }
    }
    
    var body: some View {
        Menu {
            Button("None") {
                selection = 0
            }
            Button("⌘ Command") {
                selection = Int(NSEvent.ModifierFlags.command.rawValue)
            }
            Button("⌥ Option") {
                selection = Int(NSEvent.ModifierFlags.option.rawValue)
            }
            Button("⌃ Control") {
                selection = Int(NSEvent.ModifierFlags.control.rawValue)
            }
            Button("⇧ Shift") {
                selection = Int(NSEvent.ModifierFlags.shift.rawValue)
            }
        } label: {
            HStack {
                Text(modifierKeyDisplayName)
                    .font(.system(size: 12))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
        }
    }
    
    private var modifierKeyDisplayName: String {
        if modifierFlags.isEmpty { return "None" }
        switch modifierFlags {
        case .command: return "⌘ Command"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .shift: return "⇧ Shift"
        default: return "⌘ Command"
        }
    }
}

// MARK: - PermissionStatusBadge
private struct PermissionStatusBadge: View {
    let isGranted: Bool

    var body: some View {
        Label {
            Text(isGranted ? "Granted" : "Not Granted")
                .font(.system(size: 11, weight: .semibold))
        } icon: {
            Image(systemName: isGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundColor(Color.white)
        .background(isGranted ? Color.green : Color.orange)
        .clipShape(Capsule())
    }
}
