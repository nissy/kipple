//
//  HistoryItemView.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import SwiftUI
import AppKit

struct HistoryItemView: View {
    let item: ClipItem
    let isSelected: Bool
    let isCurrentClipboardItem: Bool
    let onTap: () -> Void
    let onTogglePin: () -> Void
    let onDelete: (() -> Void)?
    let onCategoryTap: (() -> Void)?
    let historyFont: Font // フォントをパラメータとして受け取る
    
    @State private var isHovered = false
    @State private var isShowingPopover = false
    @State private var popoverTimer: Timer?
    @State private var windowPosition: Bool? // 初期値をnilに設定
    @State private var isScrolling = false
    
    var body: some View {
        ZStack {
            // 背景全体をクリック可能にするための透明レイヤー（パディングを含む全体）
            backgroundView
                .contentShape(Rectangle())
                .onTapGesture {
                    closePopover()
                    onTap()
                }

            HStack(spacing: 8) {
            // ピンボタン
            ZStack {
                Circle()
                    .fill(pinButtonBackground)
                    .frame(width: 24, height: 24)
                
                Image(systemName: pinButtonIcon)
                    .foregroundColor(pinButtonForeground)
                    .font(.system(size: 11, weight: .medium))
                    .rotationEffect(.degrees(pinButtonRotation))
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
            .onTapGesture {
                closePopover()
                onTogglePin()
            }
            
            // カテゴリアイコン（アクション可能な場合はボタンとして機能）
            if item.isActionable {
                ZStack {
                    Circle()
                        .fill(isSelected ? 
                            Color.white.opacity(0.2) : 
                            Color.accentColor
                        )
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: item.category.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? .white : .white)
                }
                .frame(width: 24, height: 24)
                .contentShape(Circle())
                .onTapGesture {
                    closePopover()
                    item.performAction()
                }
                .help(item.actionTitle ?? "")
            } else if let onCategoryTap = onCategoryTap {
                ZStack {
                    Circle()
                        .fill(isSelected ? 
                            Color.white.opacity(0.2) : 
                            Color.secondary.opacity(0.1)
                        )
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: item.category.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? .white : .secondary)
                }
                .frame(width: 24, height: 24)
                .contentShape(Circle())
                .onTapGesture {
                    closePopover()
                    onCategoryTap()
                }
                .help("「\(item.category.rawValue)」でフィルタ")
            } else {
                Image(systemName: item.category.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(isSelected ? 
                                Color.white.opacity(0.2) : 
                                Color.secondary.opacity(0.1)
                            )
                    )
            }
            
            Text(getDisplayContent())
                .font(historyFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    closePopover()
                    onTap()
                }

            if let onDelete = onDelete, isHovered && !isScrolling && !item.isPinned {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .contentShape(Circle())
                    .onTapGesture {
                        closePopover()
                        onDelete()
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            // スクロール中はポップオーバーを表示しない
            guard !isScrolling else {
                isHovered = hovering
                return
            }
            
            isHovered = hovering
            
            cancelPopoverTimer()
            
            if hovering {
                schedulePopoverPresentation()
            } else {
                closePopover()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSScrollView.willStartLiveScrollNotification)) { _ in
            isScrolling = true
            closePopover()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSScrollView.didEndLiveScrollNotification)) { _ in
            isScrolling = false
            // スクロール終了後、ホバー中ならポップオーバーを再開
            if isHovered {
                schedulePopoverPresentation()
            }
        }
        .background(
            HoverPopoverPresenter(
                isPresented: $isShowingPopover,
                arrowEdge: popoverArrowEdge
            ) {
                ClipboardItemPopover(item: item)
            }
        )
        .onDisappear {
            closePopover()
        }
    }
    
    private func getDisplayContent() -> String {
        if let newlineIndex = item.content.firstIndex(of: "\n") {
            return String(item.content[..<newlineIndex]) + "…"
        }
        return item.content
    }
    
    private func checkWindowPosition() -> Bool {
        // メインウィンドウを取得（より確実な方法）
        guard let mainWindow = NSApp.windows.first(where: { window in
            window.isVisible && 
            window.level == .normal &&
            window.contentViewController != nil
        }) else {
            // ウィンドウが見つからない場合はデフォルトで左側
            return true
        }
        
        // ウィンドウが表示されている画面を取得
        guard let currentScreen = mainWindow.screen ?? NSScreen.main else {
            return true
        }
        
        let screenFrame = currentScreen.frame
        let windowFrame = mainWindow.frame
        let screenCenter = screenFrame.midX
        
        // ウィンドウの中心がスクリーンの中心より左にあるかどうか
        return windowFrame.midX < screenCenter
    }
    
    private var popoverArrowEdge: Edge {
        // プレビューの矢印の向きを調整（ウィンドウの位置に基づいて左右に表示）
        // 初期値がnilの場合はデフォルトで右側に表示
        return (windowPosition ?? true) ? .trailing : .leading
    }

    private func schedulePopoverPresentation() {
        cancelPopoverTimer()
        
        popoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            if isHovered && !isScrolling {
                if windowPosition == nil {
                    windowPosition = checkWindowPosition()
                }
                isShowingPopover = true
            }
        }
    }

    private func cancelPopoverTimer() {
        popoverTimer?.invalidate()
        popoverTimer = nil
    }

    private func closePopover() {
        cancelPopoverTimer()
        if isShowingPopover {
            isShowingPopover = false
        }
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                isSelected ? 
                AnyShapeStyle(LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )) :
                AnyShapeStyle(Color(NSColor.quaternaryLabelColor).opacity(isHovered ? 0.5 : 0.2))
            )
            .overlay(
                isHovered && !isSelected ?
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1) : nil
            )
            .shadow(
                color: isSelected ? Color.accentColor.opacity(0.3) : Color.clear,
                radius: isSelected ? 8 : 0,
                y: isSelected ? 4 : 0
            )
    }
}
