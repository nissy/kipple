//
//  DataSettingsView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import SwiftUI
import AppKit
import CoreGraphics
import ApplicationServices

struct DataSettingsView: View {
    @AppStorage("maxHistoryItems") private var maxHistoryItems = 300
    @AppStorage("filterCategoryURL") private var filterCategoryURL = true
    @AppStorage("actionClickModifiers") private var actionClickModifiers = Int(NSEvent.ModifierFlags.command.rawValue)
    @AppStorage("historySelectPaste") private var historySelectPaste = false
    @State private var showClearHistoryAlert = false
    @State private var showClearSuccessAlert = false
    @State private var showClearErrorAlert = false
    @State private var isClearingHistory = false
    @State private var clearedItemCount = 0
    @ObservedObject private var appSettings = AppSettings.shared
    
    private let clipboardService: any ClipboardServiceProtocol

    @MainActor
    init(clipboardService: (any ClipboardServiceProtocol)? = nil) {
        if let service = clipboardService {
            self.clipboardService = service
        } else {
            self.clipboardService = ClipboardServiceProvider.resolve()
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
                ClipboardFontSettingsView()

                // Action Click
                SettingsGroup("Open URI") {
                    SettingsRow(
                        label: "Modified click",
                        description: "Use modifier + click"
                    ) {
                        ModifierKeyPicker(selection: $actionClickModifiers)
                            .frame(width: 120)
                    }
                }

                // Categories management entry (moved from Settings to Manager)
                SettingsGroup("Categories") {
                    SettingsRow(label: "Manage Categories") {
                        ManageCategoriesButton()
                    }
                }

                // Storage Limits Section
                SettingsGroup("Storage Limits") {
                    SettingsRow(label: "Maximum history items") {
                        HStack {
                            TextField(
                                "",
                                value: Binding(
                                    get: { Double(maxHistoryItems) },
                                    set: { maxHistoryItems = Int(max(10, min(1000, $0))) }
                                ),
                                formatter: makeNumberFormatter(minimum: 10, maximum: 1000)
                            )
                            .kippleRoundedTextFieldStyle()
                            .frame(width: 80)
                            .onChange(of: maxHistoryItems) { _, newValue in
                                updateHistoryLimit(newValue)
                            }

                            Stepper(
                                "",
                                value: Binding(
                                    get: { Double(maxHistoryItems) },
                                    set: { maxHistoryItems = Int($0) }
                                ),
                                in: 10...1000,
                                step: 10
                            )
                            .labelsHidden()
                        }
                    }
                }
                
                // Data Management Section
                SettingsGroup("Data Management") {
                    SettingsRow(
                        label: "Clear history",
                        description: "Items in custom categories or posted as desktop notes stay."
                    ) {
                        Button(action: {
                            showClearHistoryAlert = true
                        }, label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 12))
                                Text("Clear History")
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                LinearGradient(
                                    colors: [Color.red, Color.red.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .cornerRadius(6)
                            .shadow(color: Color.red.opacity(0.25), radius: 1, y: 1)
                        })
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isClearingHistory)
                    }
                }

                ScreenTextCaptureSettingsView()
                PasteOnSelectionSettingsView(isOn: $historySelectPaste)
            }
            .padding(.horizontal, SettingsLayoutMetrics.scrollHorizontalPadding)
            .padding(.vertical, SettingsLayoutMetrics.scrollVerticalPadding)
        }
        .alert("Clear Clipboard History?", isPresented: $showClearHistoryAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear History", role: .destructive) {
                clearHistory()
            }
        } message: {
            Text("history.clear.confirmation")
        }
        .alert("History Cleared", isPresented: $showClearSuccessAlert) {
            Button("OK") { }
        } message: {
            Text(clearHistorySuccessMessage(count: clearedItemCount))
        }
        .alert("Could not clear history", isPresented: $showClearErrorAlert) {
            Button("OK") { }
        } message: {
            Text("Please try clearing the history again.")
        }
    }
    
    private func clearHistory() {
        guard !isClearingHistory else { return }
        isClearingHistory = true

        Task {
            defer { isClearingHistory = false }
            switch await clipboardService.clearHistory(keepingCategories: true) {
            case let .success(count):
                clearedItemCount = count
                showClearSuccessAlert = true
            case .failure:
                showClearErrorAlert = true
            }
        }
    }

    private func updateHistoryLimit(_ newLimit: Int) {
        // Update ModernClipboardService with new limit
        if let modernService = clipboardService as? ModernClipboardServiceAdapter {
            Task {
                await modernService.setMaxHistoryItems(newLimit)
            }
        }
    }

    private func makeNumberFormatter(minimum: Double, maximum: Double) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = NSNumber(value: minimum)
        formatter.maximum = NSNumber(value: maximum)
        formatter.generatesDecimalNumbers = false
        formatter.allowsFloats = false
        return formatter
    }

    private func clearHistorySuccessMessage(count: Int) -> String {
        appSettings.localizedFormat(
            "history.clear.success",
            comment: "Summary after clearing history",
            count
        )
    }
}

// MARK: - Screen Text Capture Settings

private struct ScreenTextCaptureSettingsView: View {
    @AppStorage("textCaptureHotkeyKeyCode") private var textCaptureHotkeyKeyCode: Int = 0
    @AppStorage("textCaptureHotkeyModifierFlags") private var textCaptureHotkeyModifierFlags: Int = 0

    @State private var tempCaptureKeyCode: UInt16 = 17
    @State private var tempCaptureModifierFlags: NSEvent.ModifierFlags = [.command, .shift]
    @State private var hasScreenCapturePermission = CGPreflightScreenCaptureAccess()
    @State private var captureHotkeyErrorKey: LocalizedStringKey?

    private let defaultCaptureKeyCode: UInt16 = 17
    private let defaultCaptureModifierFlags: NSEvent.ModifierFlags = [.command, .shift]

    var body: some View {
        SettingsGroup(
            "Screen Text Capture",
            includeTopDivider: true,
            headerAccessory: AnyView(
                PermissionStatusBadge(isGranted: hasScreenCapturePermission)
            ),
            headerAccessoryAlignment: .leading
        ) {
            SettingsRow(label: "Text Capture Hotkey") {
                VStack(alignment: .leading, spacing: 8) {
                    HotkeyRecorderField(
                        keyCode: $tempCaptureKeyCode,
                        modifierFlags: $tempCaptureModifierFlags
                    )
                    .disabled(!hasScreenCapturePermission)
                    .onChange(of: tempCaptureKeyCode) { _, _ in updateCaptureHotkey() }
                    .onChange(of: tempCaptureModifierFlags) { _, _ in updateCaptureHotkey() }

                    if let captureHotkeyErrorKey {
                        Text(captureHotkeyErrorKey)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    } else if hasScreenCapturePermission {
                        Text("Shortcut is ready to use. Hold the selected modifiers and key to capture text.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text(
                            LocalizedStringKey(
                                "Allow Screen & System Audio Recording to configure the text capture shortcut."
                            )
                        )
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            loadCaptureHotkeyState()
            refreshScreenCapturePermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshScreenCapturePermission()
        }
    }

    private func loadCaptureHotkeyState() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: TextCaptureHotkeyManager.keyCodeDefaultsKey) == nil {
            defaults.set(Int(defaultCaptureKeyCode), forKey: TextCaptureHotkeyManager.keyCodeDefaultsKey)
        }
        if defaults.object(forKey: TextCaptureHotkeyManager.modifierDefaultsKey) == nil {
            defaults.set(
                Int(defaultCaptureModifierFlags.rawValue),
                forKey: TextCaptureHotkeyManager.modifierDefaultsKey
            )
        }

        textCaptureHotkeyKeyCode = defaults.integer(forKey: TextCaptureHotkeyManager.keyCodeDefaultsKey)
        textCaptureHotkeyModifierFlags = defaults.integer(forKey: TextCaptureHotkeyManager.modifierDefaultsKey)

        tempCaptureKeyCode = UInt16(textCaptureHotkeyKeyCode)
        tempCaptureModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(textCaptureHotkeyModifierFlags))

        if hasScreenCapturePermission {
            captureHotkeyErrorKey = nil
            updateCaptureHotkey()
        }
    }

    @MainActor
    private func updateCaptureHotkey() {
        let manager = TextCaptureHotkeyManager.shared

        // Permission changes must not erase the saved shortcut. Capture checks permission when invoked.
        guard hasScreenCapturePermission else { return }

        let keyCode = tempCaptureKeyCode
        let modifiers = tempCaptureModifierFlags

        guard keyCode != 0, !modifiers.isEmpty else {
            captureHotkeyErrorKey = LocalizedStringKey("Select a key and modifier to enable the shortcut.")
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
            captureHotkeyErrorKey = nil
            postCaptureHotkeyUpdate(
                keyCode: Int(keyCode),
                modifierFlags: Int(modifiers.rawValue),
                enabled: true
            )
        } else {
            captureHotkeyErrorKey = LocalizedStringKey(
                "The selected shortcut is already taken. Try another combination."
            )
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
                loadCaptureHotkeyState()
            } else {
                captureHotkeyErrorKey = nil
            }
        }
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

// MARK: - Paste on Selection Settings

private struct PasteOnSelectionSettingsView: View {
    @Binding var isOn: Bool
    @State private var hasAccessibilityPermission = AXIsProcessTrusted()

    var body: some View {
        SettingsGroup(
            "Paste on selection",
            includeTopDivider: true,
            headerAccessory: AnyView(
                PermissionStatusBadge(isGranted: hasAccessibilityPermission)
            ),
            headerAccessoryAlignment: .leading
        ) {
            SettingsRow(
                label: LocalizedStringKey("Paste on selection"),
                description: "Paste on selection description",
                layout: .inlineControl
            ) {
                Toggle(LocalizedStringKey("Paste on selection"), isOn: $isOn)
                    .toggleStyle(.checkbox)
                    .disabled(!hasAccessibilityPermission)
                    .help(Text("Paste on selection description"))

                if !hasAccessibilityPermission {
                    let permissionTitle = Text(AccessibilityPermissionLabel.title)
                    Text("Use the Permission tab to grant \(permissionTitle) permission in System Settings.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            refreshAccessibilityPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityPermission()
        }
    }

    @MainActor
    private func refreshAccessibilityPermission() {
        let granted = AXIsProcessTrusted()
        if granted != hasAccessibilityPermission {
            hasAccessibilityPermission = granted
        }
        if !granted {
            isOn = false
        }
    }
}
