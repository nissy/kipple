//
//  MainViewEditorSection.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI

struct MainViewEditorSection: View {
    @Binding var editorText: String
    @Binding var isAlwaysOnTop: Bool
    let isEditing: Bool
    let isLocked: Bool
    let onToggleAlwaysOnTop: () -> Void
    let onBeginEditing: () -> Void
    let onCommitEditing: () -> Void
    let onClear: () -> Void
    @State private var scrollOffset: CGFloat = 0
    @ObservedObject private var fontManager = FontManager.shared
    @State private var hoveredClearButton = false
    private let clearButtonInset: CGFloat = 20
    private var isTextEditable: Bool {
        isEditing && !isLocked
    }
    
    var body: some View {
        VStack(spacing: 0) {
            editorStatusLabel

            // エディタコンテンツ
            ZStack(alignment: .bottomTrailing) {
                SimpleLineNumberView(
                    text: $editorText,
                    font: fontManager.editorFont,
                    isEditable: isTextEditable,
                    onDoubleClick: isLocked ? {} : onBeginEditing,
                    onEscape: onCommitEditing
                ) { offset in
                    scrollOffset = offset
                }
                .padding(.trailing, clearButtonInset)

                clearEditorButton
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(editorFieldFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(editorFieldStrokeColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorFontSettingsChanged)) { _ in
            // フォント設定が変更されたときにビューを更新
        }
    }

    private var editorStatusLabel: some View {
        HStack {
            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundColor(statusColor)

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var statusText: LocalizedStringKey {
        if isLocked {
            return "editor.status.locked"
        }

        return isEditing ? "editor.status.editing" : "editor.status.livePreview"
    }

    private var statusColor: Color {
        if isTextEditable {
            return .accentColor
        }

        return .secondary
    }

    private var editorFieldFillColor: Color {
        if isTextEditable {
            return Color.primary.opacity(0.05)
        }

        return Color.primary.opacity(0.025)
    }

    private var editorFieldStrokeColor: Color {
        if isTextEditable {
            return Color.accentColor.opacity(0.22)
        }

        return Color.primary.opacity(0.05)
    }

    private var clearEditorButton: some View {
        Button(action: onClear) {
            Image(systemName: "xmark.circle.fill")
                .font(MainViewMetrics.BottomBar.clearIconFont)
                .foregroundColor(.secondary.opacity(isLocked ? 0.25 : 0.6))
                .scaleEffect(hoveredClearButton && !isLocked ? 1.1 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isLocked)
        .padding(.trailing, 8)
        .padding(.bottom, 6)
        .help(Text(clearHelpText))
        .onHover { hovering in
            hoveredClearButton = hovering
        }
    }

    private var clearHelpText: LocalizedStringKey {
        isLocked ? "editor.locked.help" : "Clear live editor"
    }
}
