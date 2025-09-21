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
    @ObservedObject private var fontManager = FontManager.shared
    
    // パフォーマンス最適化: 部分更新用のID
    @State private var editorRefreshID = UUID()
    @State private var historyRefreshID = UUID()
    @State private var hoveredClearButton = false
    // キーボードイベントモニタ（リーク防止のため保持して明示的に解除）
    @State private var keyDownMonitor: Any?
    // Copied通知の遅延非表示を管理（多重スケジュール防止）
    @State private var copiedHideWorkItem: DispatchWorkItem?
    
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
            
            // コピー時の処理
            if isAlwaysOnTop {
                // Always on Topが有効な場合のみ通知を表示
                showCopiedNotification(.copied)
            } else {
                // Always on Topが無効の場合は即座にウィンドウを閉じる
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
                    if appSettings.editorPosition == "top" {
                        editorSection
                    } else {
                        historyAndPinnedContent
                    }
                },
                bottomContent: {
                    if appSettings.editorPosition == "bottom" {
                        editorSection
                    } else {
                        historyAndPinnedContent
                    }
                }
            )
        }
        .frame(minWidth: 300, maxWidth: .infinity)
        .background(
            Color(NSColor.windowBackgroundColor)
        )
        .overlay(
            CopiedNotificationView(
                showNotification: $isShowingCopiedNotification,
                notificationType: currentNotificationType
            ),
            alignment: .top
        )
        .safeAreaInset(edge: .bottom) {
            bottomBar
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
            // 既存のモニタがあれば解除
            if let monitor = keyDownMonitor {
                NSEvent.removeMonitor(monitor)
                keyDownMonitor = nil
            }
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
        .onDisappear {
            if let monitor = keyDownMonitor {
                NSEvent.removeMonitor(monitor)
                keyDownMonitor = nil
            }
            // Cancel any scheduled hide for copied notification to avoid retaining self after window closes
            copiedHideWorkItem?.cancel()
            copiedHideWorkItem = nil
            isShowingCopiedNotification = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCopiedNotification)) { _ in
            showCopiedNotification(.copied)
        }
    }
    
    // エディタセクション
    @ViewBuilder
    private var editorSection: some View {
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
        .id(editorRefreshID)
    }
    
    // 履歴とピン留めセクションのコンテンツ
    @ViewBuilder
    private var historyAndPinnedContent: some View {
        HStack(spacing: 0) {
            // 有効なフィルターを取得
            let enabledCategories = [
                ClipItemCategory.url, .email, .code, .filePath,
                .shortText, .longText, .general, .kipple
            ]
                .filter { isCategoryFilterEnabled($0) }
            
            // フィルターパネルを常に表示（ピンフィルターがあるため）
                VStack(spacing: 8) {
                    // ピン留めフィルター（一番上に配置）
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.togglePinnedFilter()
                        }
                    }, label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(viewModel.isPinnedFilterActive ? 
                                        Color.accentColor : 
                                        Color.secondary.opacity(0.1))
                                    .frame(width: 36, height: 36)
                                    .shadow(
                                        color: viewModel.isPinnedFilterActive ? 
                                            Color.accentColor.opacity(0.3) : .clear,
                                        radius: 4,
                                        y: 2
                                    )
                                
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(viewModel.isPinnedFilterActive ? 
                                        .white : .secondary)
                            }
                            
                            Text("Pinned")
                                .font(.system(size: 10))
                                .foregroundColor(viewModel.isPinnedFilterActive ? 
                                    .primary : .secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 60)
                    })
                    .buttonStyle(PlainButtonStyle())
                    .scaleEffect(viewModel.isPinnedFilterActive ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3), value: viewModel.isPinnedFilterActive)
                    
                    ForEach(enabledCategories, id: \.self) { category in
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                viewModel.toggleCategoryFilter(category)
                            }
                        }, label: {
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
                        })
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(viewModel.selectedCategory == category ? 1.05 : 1.0)
                        .animation(.spring(response: 0.3), value: viewModel.selectedCategory)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(
                    Color(NSColor.controlBackgroundColor).opacity(0.5)
                )
            
            // メインコンテンツ（履歴セクションのみ）
            MainViewHistorySection(
                history: viewModel.history,
                currentClipboardContent: viewModel.currentClipboardContent,
                selectedHistoryItem: $selectedHistoryItem,
                hoveredHistoryItem: $hoveredHistoryItem,
                onSelectItem: handleItemSelection,
                onTogglePin: { item in
                    if !viewModel.togglePinSync(for: item) {
                        // ピン留め失敗（最大数に達している）
                        showCopiedNotification(.pinLimitReached)
                    }
                },
                onDelete: { item in
                    viewModel.deleteItemSync(item)
                },
                onCategoryFilter: { category in
                    viewModel.toggleCategoryFilter(category)
                },
                selectedCategory: $viewModel.selectedCategory
            )
            .id(historyRefreshID)
        }
    }
    
    // 下部バー
    @ViewBuilder
    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 12) {
                // 現在のペースト内容を表示
                if let currentContent = viewModel.currentClipboardContent {
                    HStack(alignment: .center, spacing: 8) {
                        // 自動消去タイマーの残り時間表示
                        if AppSettings.shared.enableAutoClear,
                           let remainingTime = viewModel.autoClearRemainingTime {
                            HStack(spacing: 6) {
                                Image(systemName: "timer")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                
                                Text(formatRemainingTime(remainingTime))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            
                            Divider()
                                .frame(height: 16)
                                .padding(.horizontal, 4)
                        }
                        
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        Text(currentContent)
                            .font(.custom(fontManager.historyFont.fontName, size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        // Clear button
                        Button(action: {
                            clearSystemClipboard()
                        }, label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.6))
                                .scaleEffect(hoveredClearButton ? 1.1 : 1.0)
                        })
                        .buttonStyle(PlainButtonStyle())
                        .help("Clear clipboard")
                        .onHover { hovering in
                            hoveredClearButton = hovering
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.1))
                    )
                }
                
                Spacer()
                
                // Settings button
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
                
                // Always on Top button
                Button(action: {
                    toggleAlwaysOnTop()
                }, label: {
                    ZStack {
                        Circle()
                            .fill(isAlwaysOnTop ? 
                                Color.accentColor :
                                Color(NSColor.controlBackgroundColor))
                            .frame(width: 28, height: 28)
                            .shadow(
                                color: isAlwaysOnTop ? 
                                    Color.accentColor.opacity(0.3) : 
                                    Color.black.opacity(0.1),
                                radius: 3,
                                y: 2
                            )
                        
                        Image(systemName: isAlwaysOnTop ? "pin.fill" : "pin")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isAlwaysOnTop ? .white : .secondary)
                            .rotationEffect(.degrees(isAlwaysOnTop ? 0 : -45))
                    }
                })
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(isAlwaysOnTop ? 1.0 : 0.9)
                .animation(.spring(response: 0.3), value: isAlwaysOnTop)
                .help(isAlwaysOnTop ? "Disable always on top" : "Enable always on top")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Color(NSColor.windowBackgroundColor).opacity(0.95)
            .background(.ultraThinMaterial)
        )
    }
    
    // MARK: - Actions
    private func confirmAction() {
        viewModel.copyEditor()
        
        // コピー時は常に通知を表示（ウィンドウは閉じない）
        showCopiedNotification(.copied)
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
        currentNotificationType = type
        if !isShowingCopiedNotification {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isShowingCopiedNotification = true
            }
        }
        // 既存の非表示タスクをキャンセルして延長（多重スケジュール防止）
        copiedHideWorkItem?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.isShowingCopiedNotification = false
            }
        }
        copiedHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
    
    private func isCategoryFilterEnabled(_ category: ClipItemCategory) -> Bool {
        switch category {
        case .all:
            return true // All is always enabled
        case .url, .urls:
            return appSettings.filterCategoryURL
        case .email, .emails:
            return appSettings.filterCategoryEmail
        case .code:
            return appSettings.filterCategoryCode
        case .filePath, .files:
            return appSettings.filterCategoryFilePath
        case .shortText:
            return appSettings.filterCategoryShortText
        case .longText:
            return appSettings.filterCategoryLongText
        case .numbers:
            return true // Numbers doesn't have a specific setting
        case .json:
            return true // JSON doesn't have a specific setting
        case .general:
            return appSettings.filterCategoryGeneral
        case .kipple:
            return appSettings.filterCategoryKipple
        }
    }
    
    private func formatRemainingTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        
        if minutes > 0 {
            return String(format: "%02d:%02d", minutes, seconds)
        } else {
            return String(format: "00:%02d", seconds)
        }
    }
    
    private func clearSystemClipboard() {
        NSPasteboard.general.clearContents()
        viewModel.currentClipboardContent = nil
    }
}
