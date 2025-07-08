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
    @State private var currentNotificationType: CopiedNotificationView.NotificationType = .copied
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
            
            // コピー通知を表示
            showCopiedNotification(.copied)
            
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
                    HStack(spacing: 0) {
                        // 有効なフィルターを取得
                        let enabledCategories = [ClipItemCategory.url, .email, .code, .filePath, .shortText, .longText, .general, .kipple]
                            .filter { isCategoryFilterEnabled($0) }
                        
                        // 有効なフィルターがある場合のみカテゴリフィルターパネルを表示
                        if !enabledCategories.isEmpty {
                            VStack(spacing: 8) {
                                Text("Filter")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 12)
                                
                                ForEach(enabledCategories, id: \.self) { category in
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3)) {
                                            viewModel.toggleCategoryFilter(category)
                                        }
                                    }) {
                                        VStack(spacing: 4) {
                                            ZStack {
                                                Circle()
                                                    .fill(viewModel.selectedCategory == category ? 
                                                        Color.accentColor : 
                                                        Color.secondary.opacity(0.1))
                                                    .frame(width: 36, height: 36)
                                                    .shadow(
                                                        color: viewModel.selectedCategory == category ? 
                                                            Color.accentColor.opacity(0.3) : .clear,
                                                        radius: 4,
                                                        y: 2
                                                    )
                                                
                                                Image(systemName: category.icon)
                                                    .font(.system(size: 16, weight: .medium))
                                                    .foregroundColor(viewModel.selectedCategory == category ? 
                                                        .white : .secondary)
                                            }
                                            
                                            Text(category.rawValue)
                                                .font(.system(size: 10))
                                                .foregroundColor(viewModel.selectedCategory == category ? 
                                                    .primary : .secondary)
                                                .lineLimit(1)
                                        }
                                        .frame(width: 60)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .scaleEffect(viewModel.selectedCategory == category ? 1.05 : 1.0)
                                    .animation(.spring(response: 0.3), value: viewModel.selectedCategory)
                                }
                                
                                Spacer()
                            }
                            .frame(width: 80)
                            .padding(.vertical, 8)
                            .background(
                                Color(NSColor.controlBackgroundColor).opacity(0.5)
                            )
                        }
                        
                        // メインコンテンツ（履歴とピン留めセクション）
                        VStack(spacing: 0) {
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
                                                if !viewModel.togglePin(for: item) {
                                                    // ピン留め失敗（最大数に達している）
                                                    showCopiedNotification(.pinLimitReached)
                                                }
                                            },
                                            onDelete: { item in
                                                viewModel.deleteItem(item)
                                            },
                                            onCategoryFilter: { category in
                                                viewModel.toggleCategoryFilter(category)
                                            },
                                            selectedCategory: $viewModel.selectedCategory
                                        )
                                        .id(historyRefreshID)
                                    },
                                    bottomContent: {
                                        MainViewPinnedSection(
                                            pinnedItems: viewModel.pinnedItems,
                                            onSelectItem: handleItemSelection,
                                            onTogglePin: { item in
                                                if !viewModel.togglePin(for: item) {
                                                    // ピン留め失敗（最大数に達している）
                                                    showCopiedNotification(.pinLimitReached)
                                                }
                                            },
                                            onDelete: { item in
                                                viewModel.deleteItem(item)
                                            },
                                            onReorderPins: { newOrder in
                                                viewModel.reorderPinnedItems(newOrder)
                                            },
                                            onCategoryFilter: { category in
                                                viewModel.toggleCategoryFilter(category)
                                            },
                                            selectedItem: $selectedHistoryItem
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
                                        if !viewModel.togglePin(for: item) {
                                            // ピン留め失敗（最大数に達している）
                                            showCopiedNotification(.pinLimitReached)
                                        }
                                    },
                                    onDelete: { item in
                                        viewModel.deleteItem(item)
                                    },
                                    onCategoryFilter: { category in
                                        viewModel.toggleCategoryFilter(category)
                                    },
                                    selectedCategory: $viewModel.selectedCategory
                                )
                                .id(historyRefreshID)
                            }
                        }
                    }
                }
            )
        }
        .frame(minWidth: 300, maxWidth: .infinity)
        .background(
            Color(NSColor.windowBackgroundColor)
        )
        .overlay(CopiedNotificationView(showNotification: $isShowingCopiedNotification, notificationType: currentNotificationType), alignment: .top)
        .safeAreaInset(edge: .bottom) {
            // 設定アイコンを下部に配置（ピンアイテムと重ならないように）
            VStack(spacing: 0) {
                
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
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)) { _ in
            // エディタセクションのみを更新（デバウンスを長くしてパフォーマンス向上）
            editorRefreshID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyFontSettingsChanged)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)) { _ in
            // 履歴セクションのみを更新（デバウンスを長くしてパフォーマンス向上）
            historyRefreshID = UUID()
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Enter キーでアクションを実行
                if event.keyCode == 36 { // Enter key
                    if let selectedItem = selectedHistoryItem,
                       selectedItem.isActionable {
                        selectedItem.performAction()
                        return nil // イベントを消費
                    }
                }
                // Cmd+O でアクションを実行
                else if event.keyCode == 31 && event.modifierFlags.contains(.command) { // O key with Cmd
                    if let selectedItem = selectedHistoryItem,
                       selectedItem.isActionable {
                        selectedItem.performAction()
                        return nil // イベントを消費
                    }
                }
                return event
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCopiedNotification)) { _ in
            showCopiedNotification(.copied)
        }
    }
    
    // MARK: - Actions
    private func confirmAction() {
        viewModel.copyEditor()
        
        // コピー通知を表示
        showCopiedNotification(.copied)
        
        // Copyボタンではウィンドウを閉じない（ピンの状態に関わらず）
    }
    
    private func clearAction() {
        viewModel.clearEditor()
    }
    
    private func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        
        // 状態の変更を通知（WindowManagerがウィンドウレベルを更新する）
        onAlwaysOnTopChanged?(isAlwaysOnTop)
    }
    
    private func showCopiedNotification(_ type: CopiedNotificationView.NotificationType) {
        // 通知タイプを設定
        currentNotificationType = type
        
        // 既に表示中の場合は一旦非表示にしてから再表示（アニメーションのリセット）
        if isShowingCopiedNotification {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isShowingCopiedNotification = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.isShowingCopiedNotification = true
                }
                self.hideCopiedNotificationAfterDelay()
            }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isShowingCopiedNotification = true
            }
            hideCopiedNotificationAfterDelay()
        }
    }
    
    private func hideCopiedNotificationAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.isShowingCopiedNotification = false
            }
        }
    }
    
    private func isCategoryFilterEnabled(_ category: ClipItemCategory) -> Bool {
        switch category {
        case .url:
            return appSettings.filterCategoryURL
        case .email:
            return appSettings.filterCategoryEmail
        case .code:
            return appSettings.filterCategoryCode
        case .filePath:
            return appSettings.filterCategoryFilePath
        case .shortText:
            return appSettings.filterCategoryShortText
        case .longText:
            return appSettings.filterCategoryLongText
        case .general:
            return appSettings.filterCategoryGeneral
        case .kipple:
            return appSettings.filterCategoryKipple
        }
    }
}
