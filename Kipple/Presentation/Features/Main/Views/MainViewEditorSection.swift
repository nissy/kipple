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
    @State private var scrollOffset: CGFloat = 0
    @ObservedObject private var fontManager = FontManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // エディタコンテンツ
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.textBackgroundColor))
                    .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
                
                SimpleLineNumberView(
                    text: $editorText,
                    font: fontManager.editorFont
                ) { offset in
                        scrollOffset = offset
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorFontSettingsChanged)) { _ in
            // フォント設定が変更されたときにビューを更新
        }
    }
}
