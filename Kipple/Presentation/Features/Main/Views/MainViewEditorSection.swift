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
    let onToggleAlwaysOnTop: () -> Void
    let onBeginEditing: () -> Void
    let onCommitEditing: () -> Void
    let onClear: () -> Void
    @State private var scrollOffset: CGFloat = 0
    @ObservedObject private var fontManager = FontManager.shared
    @State private var hoveredClearButton = false
    private let clearButtonInset: CGFloat = 20
    private var displayModeBackgroundColor: NSColor {
        NSColor(calibratedWhite: 250.0 / 255.0, alpha: 1.0)
    }
    private var editorShadowColor: Color {
        isEditing ? Color.black.opacity(0.08) : Color.clear
    }
    private var editorBackgroundColor: Color {
        isEditing
            ? Color(NSColor.textBackgroundColor)
            : Color(displayModeBackgroundColor)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // エディタコンテンツ
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(editorBackgroundColor)
                    .shadow(color: editorShadowColor, radius: isEditing ? 8 : 0, y: isEditing ? 4 : 0)
                
                SimpleLineNumberView(
                    text: $editorText,
                    font: fontManager.editorFont,
                    isEditable: isEditing,
                    onDoubleClick: onBeginEditing,
                    onEscape: onCommitEditing
                ) { offset in
                    scrollOffset = offset
                }
                .padding(.trailing, clearButtonInset)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                clearEditorButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorFontSettingsChanged)) { _ in
            // フォント設定が変更されたときにビューを更新
        }
    }

    private var clearEditorButton: some View {
        Button(action: onClear) {
            Image(systemName: "xmark.circle.fill")
                .font(MainViewMetrics.BottomBar.clearIconFont)
                .foregroundColor(.secondary.opacity(0.6))
                .scaleEffect(hoveredClearButton ? 1.1 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.trailing, 8)
        .padding(.bottom, 6)
        .help(Text("Clear live editor"))
        .onHover { hovering in
            hoveredClearButton = hovering
        }
    }
}
