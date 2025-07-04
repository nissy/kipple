//
//  ResizableSplitView.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI

struct ResizableSplitView<Top: View, Bottom: View>: View {
    let topContent: Top
    let bottomContent: Bottom
    @Binding var topHeight: Double
    let minTopHeight: Double
    let minBottomHeight: Double
    
    @State private var isDragging = false
    
    init(
        topHeight: Binding<Double>,
        minTopHeight: Double = 100,
        minBottomHeight: Double = 100,
        @ViewBuilder topContent: () -> Top,
        @ViewBuilder bottomContent: () -> Bottom
    ) {
        self._topHeight = topHeight
        self.minTopHeight = minTopHeight
        self.minBottomHeight = minBottomHeight
        self.topContent = topContent()
        self.bottomContent = bottomContent()
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // トップコンテンツ
                topContent
                    .frame(height: CGFloat(topHeight))
                    .clipped()
                
                // ドラッグハンドル
                ZStack {
                    // Background area
                    Rectangle()
                        .fill(Color(NSColor.windowBackgroundColor))
                        .frame(height: 12)
                    
                    // Visual handle
                    HStack(spacing: 4) {
                        ForEach(0..<3) { _ in
                            Circle()
                                .fill(isDragging ? Color.accentColor : Color.gray.opacity(0.3))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .scaleEffect(isDragging ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3), value: isDragging)
                }
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let newHeight = topHeight + Double(value.translation.height)
                                let availableHeight = Double(geometry.size.height) - 12 // ハンドルの高さを引く
                                
                                // 制約をチェック
                                if newHeight >= minTopHeight && 
                                   (availableHeight - newHeight) >= minBottomHeight {
                                    topHeight = newHeight
                                }
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
                
                // ボトムコンテンツ
                bottomContent
                    .frame(maxHeight: .infinity)
                    .clipped()
            }
        }
    }
}
