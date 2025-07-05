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
    
    @State private var isHovered = false
    @State private var isShowingPopover = false
    @ObservedObject private var fontManager = FontManager.shared
    
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
                        .fill(item.isPinned ? 
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color.clear, Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        .frame(width: 28, height: 28)
                        .shadow(
                            color: item.isPinned ? Color.accentColor.opacity(0.3) : .clear,
                            radius: item.isPinned ? 4 : 0,
                            y: 2
                        )
                    
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .foregroundColor(item.isPinned ? .white : .secondary)
                        .font(.system(size: 12, weight: .medium))
                        .rotationEffect(.degrees(item.isPinned ? 0 : -45))
                        .animation(.spring(response: 0.3), value: item.isPinned)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(isHovered ? 1.1 : 1.0)
            .animation(.spring(response: 0.3), value: isHovered)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayContent)
                    .font(historyFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(isSelected ? .white : .primary)
                
                if isHovered {
                    Text("\(item.category.rawValue) • \(item.characterCount) characters • \(item.timeAgo)")
                        .font(historyMetadataFont)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            
            if let onDelete = onDelete, isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .background(Circle().fill(Color(NSColor.windowBackgroundColor)))
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            
            if hovering {
                // 0.5秒後にポップオーバーを表示
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if isHovered {
                        isShowingPopover = true
                    }
                }
            } else {
                isShowingPopover = false
            }
        }
        .popover(
            isPresented: $isShowingPopover,
            attachmentAnchor: popoverAttachmentAnchor,
            arrowEdge: popoverArrowEdge
        ) {
            ClipboardItemPopover(item: item)
                .interactiveDismissDisabled() // ポップオーバー内のクリックで閉じないようにする
        }
    }
    
    private var isWindowOnLeftSide: Bool {
        if let mainWindow = NSApplication.shared.windows.first(where: { 
            $0.title == "Kipple" || $0.contentViewController != nil
        }) {
            // ウィンドウが表示されている画面を取得
            let windowScreen = NSScreen.screens.first { screen in
                screen.frame.intersects(mainWindow.frame)
            } ?? NSScreen.main
            
            guard let currentScreen = windowScreen else { return true }
            
            let screenFrame = currentScreen.frame
            let windowFrame = mainWindow.frame
            let screenCenter = screenFrame.midX
            
            // ウィンドウの中心がスクリーンの中心より左にあるかどうか
            return windowFrame.midX < screenCenter
        }
        return true // デフォルトは左側として扱う
    }
    
    private var popoverAttachmentAnchor: PopoverAttachmentAnchor {
        // プレビューをできるだけウィンドウの外側に表示するための設定
        if isWindowOnLeftSide {
            return .rect(.bounds)  // アイテムの境界に基づいて配置
        } else {
            return .rect(.bounds)  // アイテムの境界に基づいて配置
        }
    }
    
    private var popoverArrowEdge: Edge {
        // プレビューの矢印の向きを調整（ウィンドウの位置に基づいて左右に表示）
        if isWindowOnLeftSide {
            return .trailing  // ウィンドウが左側にある場合、ポップオーバーは右側に表示
        } else {
            return .leading   // ウィンドウが右側にある場合、ポップオーバーは左側に表示
        }
    }
    
    private var backgroundView: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)
            } else if isHovered {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.1), radius: 5, y: 2)
                
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
            }
        }
    }
}

// MARK: - Popover Content
struct ClipboardItemPopover: View {
    let item: ClipItem
    
    @ObservedObject private var fontManager = FontManager.shared
    @ObservedObject private var appSettings = AppSettings.shared
    
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
            
            ScrollView {
                Text(item.fullContent)
                    .font(popoverFont)
                    .lineSpacing(4)
                    .lineLimit(15) // 15行で制限
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .padding(16)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        .frame(width: 380)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.2), radius: 20, y: 10)
        .allowsHitTesting(false)
    }
    
    // MARK: - Helper Properties
    
    private var popoverFont: Font {
        Font(fontManager.historyFont)
    }
    
    private var categoryColor: Color {
        switch item.category {
        case .url: return .blue
        case .email: return .green
        case .code: return .purple
        case .filePath: return .orange
        case .shortText: return .orange
        case .longText: return .indigo
        case .general: return .gray
        }
    }
}

// MARK: - HistoryItemView Helper Properties
extension HistoryItemView {
    private var historyFont: Font {
        Font(fontManager.historyFont)
    }
    
    private var historyMetadataFont: Font {
        let metadataSize = max(10, fontManager.historySettings.primaryFontSize - 3)
        if let font = NSFont(name: fontManager.historySettings.primaryFontName, size: metadataSize) {
            return Font(font)
        } else {
            return .system(size: metadataSize)
        }
    }
    
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
