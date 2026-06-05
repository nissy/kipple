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
            trimButton
            formatPickerButton
        }
    }

    private var editModeButton: some View {
        Button(action: toggleEditorMode) {
            Image(systemName: editModeButtonIcon)
                .font(iconFont)
                .frame(
                    width: KippleButtonMetrics.toolbarSize,
                    height: KippleButtonMetrics.toolbarSize
                )
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(editModeButtonTitle))
        .foregroundColor(editModeButtonForegroundColor)
        .kippleSystemCircleButton(isActive: isEditing, isEnabled: !isEditorLocked)
        .disabled(isEditorLocked)
        .help(Text(editModeButtonHelpText))
        .focusable(false)
        .focusEffectDisabled()
    }

    private var trimButton: some View {
        Button(action: trim) {
            Image(systemName: "scissors")
                .font(iconFont)
                .foregroundColor(formatButtonForegroundColor)
                .frame(
                    width: KippleButtonMetrics.toolbarSize,
                    height: KippleButtonMetrics.toolbarSize
                )
                .contentShape(Rectangle())
        }
        .foregroundColor(formatButtonForegroundColor)
        .kippleSystemCircleButton(isEnabled: !isFormatDisabled)
        .disabled(isFormatDisabled)
        .accessibilityLabel(Text("editor.trim"))
        .help(Text("editor.trim"))
        .focusable(false)
        .focusEffectDisabled()
    }

    private var formatPickerButton: some View {
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
            Image(systemName: "curlybraces")
                .symbolRenderingMode(.palette)
                .foregroundStyle(formatButtonForegroundColor)
                .font(iconFont)
                .frame(
                    width: KippleButtonMetrics.toolbarSize,
                    height: KippleButtonMetrics.toolbarSize
                )
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(PlainButtonStyle())
        .kippleSystemCircleButton(isEnabled: !isFormatDisabled)
        .disabled(isFormatDisabled)
        .accessibilityLabel(Text("editor.format"))
        .help(Text(formatButtonHelpText))
        .focusable(false)
        .focusEffectDisabled()
    }

    private var saveButton: some View {
        Button(action: save) {
            Image(systemName: "tray.and.arrow.down")
                .font(iconFont)
                .frame(
                    width: KippleButtonMetrics.toolbarSize,
                    height: KippleButtonMetrics.toolbarSize
                )
                .contentShape(Rectangle())
        }
        .foregroundColor(saveButtonForegroundColor)
        .kippleSystemCircleButton(isEnabled: !isSaveDisabled)
        .disabled(isSaveDisabled)
        .help(Text(saveButtonHelpText))
        .focusable(false)
        .focusEffectDisabled()
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

    private var editModeButtonForegroundColor: Color {
        KippleButtonAppearance.foreground(isActive: isEditing, isEnabled: !isEditorLocked)
    }

    private var saveButtonForegroundColor: Color {
        KippleButtonAppearance.foreground(isActive: false, isEnabled: !isSaveDisabled)
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
        KippleButtonAppearance.foreground(isActive: false, isEnabled: !isFormatDisabled)
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
}
