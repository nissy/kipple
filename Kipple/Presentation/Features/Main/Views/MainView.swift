//
//  MainView.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import SwiftUI

struct MainView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var selectedHistoryItem: ClipItem?
    @State private var hoveredHistoryItem: ClipItem?
    @State private var isShowingCopiedNotification = false
    @State private var isAlwaysOnTop = false
    @AppStorage("editorSectionHeight") private var editorSectionHeight: Double = 250
    @AppStorage("historySectionHeight") private var historySectionHeight: Double = 300
    @ObservedObject private var appSettings = AppSettings.shared
    
    // パフォーマンス最適化: 部分更新用のID
    @State private var editorRefreshID = UUID()
    @State private var historyRefreshID = UUID()
    
    let onClose: (() -> Void)?
    let onAlwaysOnTopChanged: ((Bool) -> Void)?
    let onOpenSettings: (() -> Void)?
    
    // 設定値を読み込み
    
    init(
        onClose: (() -> Void)? = nil,
        onAlwaysOnTopChanged: ((Bool) -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onAlwaysOnTopChanged = onAlwaysOnTopChanged
        self.onOpenSettings = onOpenSettings
    }
    
    private func handleItemSelection(_ item: ClipItem) {
        if viewModel.isEditorInsertEnabled() && viewModel.shouldInsertToEditor() {
            viewModel.insertToEditor(content: item.content)
            // エディタ挿入の場合はウィンドウを閉じない
        } else {
            viewModel.selectHistoryItem(item)
            // ピン（常に最前面）が有効でない場合のみウィンドウを閉じる
            if !isAlwaysOnTop {
                onClose?()
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // メインコンテンツ（分割ビュー）
            ResizableSplitView(
                topHeight: $editorSectionHeight,
                minTopHeight: 150,
                minBottomHeight: 150,
                topContent: {
                    VStack(spacing: 0) {
                        MainViewEditorSection(
                            editorText: $viewModel.editorText,
                            isAlwaysOnTop: $isAlwaysOnTop,
                            onToggleAlwaysOnTop: toggleAlwaysOnTop
                        )
                        MainViewControlSection(
                            onCopy: confirmAction,
                            onClear: clearAction
                        )
                    }
                    .id(editorRefreshID) // エディタセクションの部分更新用
                },
                bottomContent: {
                    if !viewModel.pinnedItems.isEmpty {
                        ResizableSplitView(
                            topHeight: $historySectionHeight,
                            minTopHeight: 100,
                            minBottomHeight: 80,
                            topContent: {
                                MainViewHistorySection(
                                    history: viewModel.history,
                                    selectedHistoryItem: $selectedHistoryItem,
                                    hoveredHistoryItem: $hoveredHistoryItem,
                                    onSelectItem: handleItemSelection,
                                    onTogglePin: { item in
                                        viewModel.togglePin(for: item)
                                    },
                                    onDelete: { item in
                                        viewModel.deleteItem(item)
                                    }
                                )
                                .id(historyRefreshID) // 履歴セクションの部分更新用
                            },
                            bottomContent: {
                                MainViewPinnedSection(
                                    pinnedItems: viewModel.pinnedItems,
                                    onSelectItem: handleItemSelection,
                                    onTogglePin: { item in
                                        viewModel.togglePin(for: item)
                                    },
                                    onDelete: { item in
                                        viewModel.deleteItem(item)
                                    },
                                    onReorderPins: { newOrder in
                                        viewModel.reorderPinnedItems(newOrder)
                                    }
                                )
                            }
                        )
                    } else {
                        MainViewHistorySection(
                            history: viewModel.history,
                            selectedHistoryItem: $selectedHistoryItem,
                            hoveredHistoryItem: $hoveredHistoryItem,
                            onSelectItem: handleItemSelection,
                            onTogglePin: { item in
                                viewModel.togglePin(for: item)
                            },
                            onDelete: { item in
                                viewModel.deleteItem(item)
                            }
                        )
                        .id(historyRefreshID) // 履歴セクションの部分更新用
                    }
                }
            )
        }
        .frame(minWidth: 300, maxWidth: .infinity)
        .background(
            Color(NSColor.windowBackgroundColor)
        )
        .overlay(CopiedNotificationView(showNotification: $isShowingCopiedNotification), alignment: .top)
        .safeAreaInset(edge: .bottom) {
            // 設定アイコンを下部に配置（ピンアイテムと重ならないように）
            VStack(spacing: 0) {
                // Gradient divider
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color.clear, Color.gray.opacity(0.2), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(height: 1)
                
                HStack {
                    Spacer()
                    
                    Button(action: {
                        onOpenSettings?()
                    }, label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [
                                        Color(NSColor.controlBackgroundColor),
                                        Color(NSColor.controlBackgroundColor).opacity(0.8)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 28, height: 28)
                                .shadow(color: Color.black.opacity(0.1), radius: 3, y: 2)
                            
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    })
                    .buttonStyle(PlainButtonStyle())
                    .scaleEffect(1.0)
                    .onHover { _ in
                        withAnimation(.spring(response: 0.3)) {
                            // Scale effect handled by button style
                        }
                    }
                    .help("Settings")
                }
                .padding(12)
                .background(
                    Color(NSColor.windowBackgroundColor).opacity(0.95)
                    .background(.ultraThinMaterial)
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorFontSettingsChanged)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)) { _ in
            // エディタセクションのみを更新（デバウンス適用）
            editorRefreshID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyFontSettingsChanged)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)) { _ in
            // 履歴セクションのみを更新（デバウンス適用）
            historyRefreshID = UUID()
        }
    }
    
    // MARK: - Actions
    private func confirmAction() {
        viewModel.copyEditor()
        
        // コピー通知を表示
        isShowingCopiedNotification = true
        
        // 2秒後に通知を非表示
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isShowingCopiedNotification = false
        }
        
        // ピン（常に最前面）が有効でない場合のみウィンドウを閉じる
        if !isAlwaysOnTop {
            onClose?()
        }
    }
    
    private func clearAction() {
        viewModel.clearEditor()
    }
    
    private func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        
        // 状態の変更を通知（WindowManagerがウィンドウレベルを更新する）
        onAlwaysOnTopChanged?(isAlwaysOnTop)
    }
}
