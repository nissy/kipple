//
//  MainViewControlSection.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI
import AppKit

struct MainViewControlSection: View {
    @Binding var editorMode: MainViewModel.ClipboardEditorMode
    let isEditorLocked: Bool
    let canSave: Bool
    let onSave: () -> Void
    let onTrim: () -> Void
    let onFormat: (ClipboardTextFormat) -> Void
    @ObservedObject private var appSettings = AppSettings.shared

    private let iconFont = Font.system(size: 11, weight: .semibold)

    var body: some View {
        HStack(spacing: 6) {
            controlButtons
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var controlButtons: some View {
        HStack(spacing: 6) {
            editModeButton
            saveButton
            formatMenu
        }
    }

    private var editModeButton: some View {
        Button(action: toggleEditorMode) {
            HStack(spacing: 4) {
                Text(editModeButtonTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if !editModeShortcut.isEmpty {
                    shortcutBadge(editModeShortcut)
                }
            }
                .padding(.horizontal, KippleButtonMetrics.editorControlHorizontalPadding)
                .frame(
                    minWidth: KippleButtonMetrics.editorModeMinWidth,
                    minHeight: KippleButtonMetrics.editorControlHeight
                )
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(editModeButtonTitle))
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(.white)
        .background(editModeButtonBackground)
        .clipShape(editorControlShape)
        .overlay(editorControlShape.stroke(editModeButtonBorder, lineWidth: 1))
        .shadow(color: editModeButtonShadow, radius: 4, y: 2)
        .disabled(isEditorLocked)
        .help(Text(editModeButtonHelpText))
        .focusable(false)
        .focusEffectDisabled()
    }

    private var formatMenu: some View {
        HStack(spacing: 0) {
            Button(action: trim) {
                Image(systemName: "scissors")
                    .font(iconFont)
                    .frame(
                        width: KippleButtonMetrics.editorTrimButtonWidth,
                        height: KippleButtonMetrics.editorControlHeight
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(Text("editor.trim"))

            Rectangle()
                .fill(formatButtonSeparatorColor)
                .frame(width: 1, height: KippleButtonMetrics.editorControlHeight - 12)
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
                    .font(iconFont)
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(
                width: KippleButtonMetrics.editorFormatMenuButtonWidth,
                height: KippleButtonMetrics.editorControlHeight
            )
            .contentShape(Rectangle())
            .accessibilityLabel(Text("editor.format"))
        }
        .foregroundColor(formatButtonForegroundColor)
        .background(formatButtonBackground)
        .clipShape(editorControlShape)
        .overlay(editorControlShape.stroke(formatButtonBorderColor, lineWidth: 1))
        .shadow(color: formatButtonShadowColor, radius: 4, y: 2)
        .disabled(isFormatDisabled)
        .contentShape(Rectangle())
        .help(Text(formatButtonHelpText))
        .focusable(false)
        .focusEffectDisabled()
    }

    private var saveButton: some View {
        Button(action: save) {
            saveButtonLabel
                .padding(.horizontal, KippleButtonMetrics.editorControlHorizontalPadding)
                .frame(height: KippleButtonMetrics.editorControlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(saveButtonForegroundColor)
        .background(saveButtonBackground)
        .clipShape(editorControlShape)
        .overlay(editorControlShape.stroke(saveButtonBorderColor, lineWidth: 1))
        .shadow(color: saveButtonShadowColor, radius: 4, y: 2)
        .disabled(isSaveDisabled)
        .help(Text(saveButtonHelpText))
        .focusable(false)
        .focusEffectDisabled()
    }

    private var saveButtonLabel: some View {
        HStack(spacing: 4) {
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

    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var editorControlShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: KippleButtonMetrics.editorControlCornerRadius,
            style: .continuous
        )
    }

    private var primaryButtonBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor,
                Color.accentColor.opacity(0.85)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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

    private var editModeButtonHelpText: LocalizedStringKey {
        isEditorLocked ? "editor.locked.help" : editModeButtonTitle
    }

    private var editModeShortcut: String {
        isEditing ? "ESC" : ""
    }

    private var editModeButtonBackground: LinearGradient {
        if isEditorLocked {
            return lockedButtonBackground
        }

        if isEditing {
            return dangerButtonBackground
        }

        return primaryButtonBackground
    }

    private var editModeButtonBorder: Color {
        Color.white.opacity(0.15)
    }

    private var editModeButtonShadow: Color {
        Color.black.opacity(0.12)
    }

    private var dangerButtonBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.red,
                Color.red.opacity(0.85)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var lockedButtonBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.secondary.opacity(0.45),
                Color.secondary.opacity(0.32)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var disabledButtonBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(NSColor.controlBackgroundColor).opacity(0.88),
                Color(NSColor.controlBackgroundColor).opacity(0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var saveButtonBackground: LinearGradient {
        isSaveDisabled ? disabledButtonBackground : primaryButtonBackground
    }

    private var saveButtonForegroundColor: Color {
        isSaveDisabled ? KippleButtonAppearance.disabledForeground : Color.white
    }

    private var saveButtonBorderColor: Color {
        isSaveDisabled ? Color.secondary.opacity(0.18) : Color.white.opacity(0.15)
    }

    private var saveButtonShadowColor: Color {
        isSaveDisabled ? Color.clear : Color.black.opacity(0.12)
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

    private var formatButtonBackground: LinearGradient {
        if isFormatDisabled {
            return disabledButtonBackground
        }

        return LinearGradient(
            colors: [
                Color.green,
                Color.green.opacity(0.85)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var formatButtonForegroundColor: Color {
        isFormatDisabled ? KippleButtonAppearance.disabledForeground : Color.white
    }

    private var formatButtonBorderColor: Color {
        isFormatDisabled ? Color.secondary.opacity(0.18) : Color.white.opacity(0.15)
    }

    private var formatButtonSeparatorColor: Color {
        isFormatDisabled ? Color.secondary.opacity(0.16) : Color.white.opacity(0.25)
    }

    private var formatButtonShadowColor: Color {
        isFormatDisabled ? Color.clear : Color.black.opacity(0.12)
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

    private func save() {
        guard !isSaveDisabled else { return }
        onSave()
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
