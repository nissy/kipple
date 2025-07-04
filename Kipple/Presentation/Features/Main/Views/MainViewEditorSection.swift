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
            // ヘッダー
            HStack(spacing: 10) {
                // Icon with gradient background
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.green, Color.green.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 28, height: 28)
                        .shadow(color: Color.green.opacity(0.3), radius: 3, y: 2)
                    
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text("Quick Editor")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Character count
                if !editorText.isEmpty {
                    Text("\(editorText.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.8))
                        )
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Pin button for always on top
                Button(action: onToggleAlwaysOnTop) {
                    ZStack {
                        Circle()
                            .fill(isAlwaysOnTop ? 
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [
                                        Color(NSColor.controlBackgroundColor), 
                                        Color(NSColor.controlBackgroundColor)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                            .frame(width: 28, height: 28)
                            .shadow(
                                color: isAlwaysOnTop ? Color.accentColor.opacity(0.3) : Color.black.opacity(0.1),
                                radius: isAlwaysOnTop ? 4 : 2,
                                y: 2
                            )
                        
                        Image(systemName: isAlwaysOnTop ? "pin.fill" : "pin")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isAlwaysOnTop ? .white : .secondary)
                            .rotationEffect(.degrees(isAlwaysOnTop ? 0 : -45))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(isAlwaysOnTop ? 1.0 : 0.9)
                .animation(.spring(response: 0.3), value: isAlwaysOnTop)
                .help(isAlwaysOnTop ? "Disable always on top" : "Enable always on top")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Color(NSColor.windowBackgroundColor).opacity(0.9)
            )
            
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
