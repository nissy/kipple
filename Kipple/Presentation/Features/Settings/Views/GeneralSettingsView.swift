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
    @AppStorage("windowAnimation") private var windowAnimation: String = "none"

    @State private var tempKeyCode: UInt16 = 0
    @State private var tempModifierFlags: NSEvent.ModifierFlags = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
                startupSection
                openKippleSection
                windowAnimationSection
            }
            .padding(.horizontal, SettingsLayoutMetrics.scrollHorizontalPadding)
            .padding(.vertical, SettingsLayoutMetrics.scrollVerticalPadding)
        }
        .onAppear {
            tempKeyCode = UInt16(hotkeyKeyCode)
            tempModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifierFlags))
        }
    }

    private var startupSection: some View {
        SettingsGroup("Startup", includeTopDivider: false) {
            SettingsRow(
                label: "Launch at login",
                isOn: $autoLaunchAtLogin
            )
            .onChange(of: autoLaunchAtLogin) { newValue in
                LaunchAtLogin.shared.isEnabled = newValue
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
                .onChange(of: tempKeyCode) { _ in updateHotkey() }
                .onChange(of: tempModifierFlags) { _ in updateHotkey() }
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
                    Text("Scale").tag("scale")
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 200)
                .labelsHidden()
            }
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
