//
//  MainViewControlSection.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI

struct MainViewControlSection: View {
    @Binding var editorMode: MainViewModel.ClipboardEditorMode
    let isEditorLocked: Bool
    let canSave: Bool
    let onSave: () -> Void
    let onTrim: () -> Void
    let onFormat: (ClipboardTextFormat) -> Void
    @ObservedObject private var appSettings = AppSettings.shared

    private let buttonHeight: CGFloat = 30
    private let horizontalPadding: CGFloat = 10
    private let trimButtonWidth: CGFloat = 40
    private let formatMenuButtonWidth: CGFloat = 32

    var body: some View {
        HStack(spacing: 6) {
            editModeButton
            saveButton
            formatMenu
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .kippleLiquidControlGroup(in: Capsule(), isEnabled: !isEditorLocked)
    }

    private var editModeButton: some View {
        Button(action: toggleEditorMode) {
            HStack(spacing: 4) {
                Image(systemName: editModeButtonIcon)
                    .font(.system(size: 11, weight: .semibold))

                Text(editModeButtonTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if !editModeShortcut.isEmpty {
                    shortcutBadge(editModeShortcut)
                }
            }
                .padding(.horizontal, horizontalPadding)
                .frame(minWidth: 64, minHeight: buttonHeight)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(editModeButtonTitle))
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(editModeButtonForegroundColor)
        .kippleControlSurface(in: Capsule(), isActive: isEditing, isEnabled: !isEditorLocked)
        .disabled(isEditorLocked)
        .help(Text(editModeButtonHelpText))
        .focusable(false)
        .focusEffectDisabled()
    }

    private var formatMenu: some View {
        HStack(spacing: 0) {
            Button(action: trim) {
                HStack(spacing: 4) {
                    Image(systemName: "scissors")
                        .font(.system(size: 11, weight: .regular))
                }
                .padding(.horizontal, horizontalPadding)
                .frame(width: trimButtonWidth, height: buttonHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(Text("editor.trim"))
            .focusable(false)
            .focusEffectDisabled()

            Rectangle()
                .fill(formatButtonSeparatorColor)
                .frame(width: 1, height: buttonHeight - 12)
                .padding(.vertical, 6)
                .allowsHitTesting(false)

            Menu {
                Button(action: { format(.json) }, label: {
                    Label {
                        Text("editor.format.json")
                    } icon: {
                        Image(systemName: "curlybraces")
                    }
                })

                Button(action: { format(.yaml) }, label: {
                    Label {
                        Text("editor.format.yaml")
                    } icon: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                })
            } label: {
                Image(systemName: "chevron.down")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(formatButtonForegroundColor)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: formatMenuButtonWidth, height: buttonHeight)
                    .contentShape(Rectangle())
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .menuIndicator(.hidden)
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(Text("editor.format"))
            .focusable(false)
            .focusEffectDisabled()
        }
        .foregroundColor(formatButtonForegroundColor)
        .kippleControlSurface(in: Capsule(), isEnabled: !isFormatDisabled)
        .disabled(isFormatDisabled)
        .contentShape(Rectangle())
        .help(Text(formatButtonHelpText))
        .focusable(false)
        .focusEffectDisabled()
    }

    private var saveButton: some View {
        Button(action: onSave) {
            saveButtonLabel
            .padding(.horizontal, horizontalPadding)
            .frame(height: buttonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(saveButtonForegroundColor)
        .kippleControlSurface(in: Capsule(), isActive: !isSaveDisabled, isEnabled: !isSaveDisabled)
        .disabled(isSaveDisabled)
        .help(Text(saveButtonHelpText))
        .focusable(false)
        .focusEffectDisabled()
    }

    private var saveButtonLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 11, weight: .semibold))

            Text("editor.saveToHistory")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            let shortcut = getShortcutKeyDisplay()
            if !shortcut.isEmpty {
                shortcutBadge(shortcut)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("editor.saveToHistory"))
    }

    private func buttonLabel(
        systemImage: String,
        title: LocalizedStringKey? = nil,
        shortcut: String,
        accessibilityLabel: LocalizedStringKey
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .regular))

            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if !shortcut.isEmpty {
                shortcutBadge(shortcut)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
    }

    private var isEditing: Bool {
        editorMode == .editing
    }

    private var isFormatDisabled: Bool {
        isEditorLocked || !isEditing
    }

    private var isSaveDisabled: Bool {
        isEditorLocked || !canSave
    }

    private var editModeButtonTitle: LocalizedStringKey {
        if isEditorLocked {
            return "editor.mode.locked"
        }

        return isEditing ? "editor.mode.finishEditing" : "editor.mode.startEditing"
    }

    private var editModeButtonIcon: String {
        if isEditorLocked {
            return "lock.fill"
        }

        return isEditing ? "checkmark" : "pencil"
    }

    private var editModeButtonHelpText: LocalizedStringKey {
        isEditorLocked ? "editor.locked.help" : editModeButtonTitle
    }

    private var editModeShortcut: String {
        isEditing ? "ESC" : ""
    }

    private var editModeButtonForegroundColor: Color {
        isEditorLocked ? Color.secondary.opacity(0.62) : .primary
    }

    private var saveButtonForegroundColor: Color {
        isSaveDisabled ? Color.secondary.opacity(0.62) : .primary
    }

    private var saveButtonHelpText: LocalizedStringKey {
        if isEditorLocked {
            return "editor.locked.help"
        }

        if !canSave {
            return "editor.saveToHistory.noChanges"
        }

        return "editor.saveToHistory"
    }
    
    private var formatButtonForegroundColor: Color {
        isFormatDisabled ? Color.secondary.opacity(0.62) : .primary
    }

    private var formatButtonSeparatorColor: Color {
        isFormatDisabled ? Color.secondary.opacity(0.06) : Color.secondary.opacity(0.08)
    }

    private func toggleEditorMode() {
        guard !isEditorLocked else { return }
        editorMode = isEditing ? .display : .editing
    }

    private var formatButtonHelpText: LocalizedStringKey {
        if isEditorLocked {
            return "editor.locked.help"
        }

        if !isEditing {
            return "editor.editTools.requiresEditing"
        }

        return "editor.editTools.help"
    }

    private func trim() {
        guard !isFormatDisabled else { return }
        onTrim()
    }

    private func format(_ textFormat: ClipboardTextFormat) {
        guard !isFormatDisabled else { return }
        onFormat(textFormat)
    }

    private func getShortcutKeyDisplay() -> String {
        if appSettings.editorCopyHotkeyKeyCode == 0 || appSettings.editorCopyHotkeyModifierFlags == 0 {
            return ""
        }

        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(appSettings.editorCopyHotkeyModifierFlags))
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        if let keyChar = keyCodeToString(UInt16(appSettings.editorCopyHotkeyKeyCode)) {
            parts.append(keyChar)
        }

        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String? {
        let keyMap: [UInt16: String] = [
            1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 50: "`"
        ]
        if keyCode == 0 { return nil }
        return keyMap[keyCode]
    }
}
