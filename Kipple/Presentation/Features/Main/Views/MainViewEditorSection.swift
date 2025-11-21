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
    let onToggleAlwaysOnTop: () -> Void
    let onClear: () -> Void
    @State private var scrollOffset: CGFloat = 0
    @ObservedObject private var fontManager = FontManager.shared
    @State private var hoveredClearButton = false
    private let clearButtonInset: CGFloat = 32
    
    var body: some View {
        VStack(spacing: 0) {
            // エディタコンテンツ
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.textBackgroundColor))
                    .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
                
                SimpleLineNumberView(
                    text: $editorText,
                    font: fontManager.editorFont
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
        .padding(.trailing, 14)
        .padding(.bottom, 12)
        .help(Text("Clear editor"))
        .onHover { hovering in
            hoveredClearButton = hovering
        }
    }
}
