//
//  HistoryItemView.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import SwiftUI

struct HistoryItemView: View {
    let item: ClipItem
    let isSelected: Bool
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
        HStack(spacing: 12) {
            // カテゴリアイコン（アクション可能な場合はボタンとして機能）
            if item.isActionable {
                Button(action: {
                    item.performAction()
                }) {
                    Image(systemName: item.category.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? .white : .accentColor)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(isSelected ? 
                                    Color.white.opacity(0.2) : 
                                    Color.accentColor.opacity(0.15)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .help(item.actionTitle ?? "")
            } else if let onCategoryTap = onCategoryTap {
                Button(action: onCategoryTap) {
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
                .buttonStyle(PlainButtonStyle())
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
            
            Button(action: onTogglePin) {
                ZStack {
                    Circle()
                        .fill(item.isPinned ? Color.accentColor : Color.clear)
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .foregroundColor(item.isPinned ? .white : .secondary)
                        .font(.system(size: 12, weight: .medium))
                        .rotationEffect(.degrees(item.isPinned ? 0 : -45))
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayContent)
                    .font(historyFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            
            if let onDelete = onDelete, isHovered && !isScrolling {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            // スクロール中はポップオーバーを表示しない
            guard !isScrolling else {
                isHovered = hovering
                return
            }
            
            isHovered = hovering
            
            // タイマーをキャンセル
            popoverTimer?.invalidate()
            popoverTimer = nil
            
            if hovering {
                // ポップオーバーの遅延表示
                popoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                    if isHovered && !isScrolling {
                        // 初回のみウィンドウ位置を確認
                        if windowPosition == nil {
                            windowPosition = checkWindowPosition()
                        }
                        isShowingPopover = true
                    }
                }
            } else {
                isShowingPopover = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSScrollView.willStartLiveScrollNotification)) { _ in
            isScrolling = true
            if isShowingPopover {
                isShowingPopover = false
            }
            popoverTimer?.invalidate()
            popoverTimer = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSScrollView.didEndLiveScrollNotification)) { _ in
            isScrolling = false
            // スクロール終了後、ホバー中ならポップオーバーを再開
            if isHovered {
                popoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                    if isHovered && !isScrolling {
                        // 初回のみウィンドウ位置を確認
                        if windowPosition == nil {
                            windowPosition = checkWindowPosition()
                        }
                        isShowingPopover = true
                    }
                }
            }
        }
        .popover(
            isPresented: $isShowingPopover,
            attachmentAnchor: popoverAttachmentAnchor,
            arrowEdge: popoverArrowEdge
        ) {
            if isShowingPopover {
                ClipboardItemPopover(item: item)
                    .interactiveDismissDisabled() // ポップオーバー内のクリックで閉じないようにする
            }
        }
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
    
    private var popoverAttachmentAnchor: PopoverAttachmentAnchor {
        // プレビューをできるだけウィンドウの外側に表示するための設定
        return .rect(.bounds)  // アイテムの境界に基づいて配置
    }
    
    private var popoverArrowEdge: Edge {
        // プレビューの矢印の向きを調整（ウィンドウの位置に基づいて左右に表示）
        // 初期値がnilの場合はデフォルトで右側に表示
        return (windowPosition ?? true) ? .trailing : .leading
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
                AnyShapeStyle(Color(isHovered ? 
                    NSColor.controlBackgroundColor : 
                    NSColor.controlBackgroundColor.withAlphaComponent(0.3)
                ))
            )
            .overlay(
                isHovered && !isSelected ?
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1) : nil
            )
            .shadow(
                color: isSelected ? Color.accentColor.opacity(0.3) : Color.clear,
                radius: isSelected ? 8 : 0,
                y: isSelected ? 4 : 0
            )
    }
}

// MARK: - Popover Content
struct ClipboardItemPopover: View {
    let item: ClipItem
    @StateObject private var fontManager = FontManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // カテゴリバッジとアプリ情報
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: item.category.icon)
                        .font(.system(size: 12))
                    Text(item.category.rawValue)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(categoryColor)
                )
                
                Spacer()
                
                // アプリケーション情報
                if item.sourceApp != nil || item.windowTitle != nil {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let appName = item.sourceApp {
                            HStack(spacing: 4) {
                                Image(systemName: "app.badge.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.accentColor)
                                Text(appName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        if let windowTitle = item.windowTitle {
                            HStack(spacing: 4) {
                                Image(systemName: "macwindow")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text(windowTitle)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            
            // コンテンツを直接表示（シンプル化してパフォーマンス向上）
            Text(String(item.content.prefix(500))) // 最大50０文字に制限
                .font(Font(fontManager.historyFont))
                .lineSpacing(4)
                .lineLimit(10) // 10行に制限
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .padding(16)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(NSColor.textBackgroundColor))
            
            // 詳細情報セクション
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                
                // 詳細メタデータ
                HStack(spacing: 16) {
                    // 文字数
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Characters")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(item.characterCount)")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    
                    // 時刻
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Copied")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(item.formattedTimestamp)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 320) // サイズを小さく
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 6, y: 3)
    }
    
    // MARK: - Helper Properties
    
    private var categoryColor: Color {
        switch item.category {
        case .url: return .blue
        case .email: return .green
        case .code: return .purple
        case .filePath: return .orange
        case .shortText: return .orange
        case .longText: return .indigo
        case .general: return .gray
        case .kipple: return .accentColor
        }
    }
}

// MARK: - HistoryItemView Helper Properties
extension HistoryItemView {
    
    private var actionIcon: String {
        switch item.category {
        case .url:
            return "safari"
        case .email:
            return "envelope"
        default:
            return "arrow.right.circle"
        }
    }
}

// ClipboardItemPopover Extension
extension ClipboardItemPopover {
    private var actionIcon: String {
        switch item.category {
        case .url:
            return "safari"
        case .email:
            return "envelope"
        default:
            return "arrow.right.circle"
        }
    }
}
