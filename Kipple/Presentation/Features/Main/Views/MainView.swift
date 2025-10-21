//
//  MainView.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import SwiftUI
import AppKit
import Combine

struct MainView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var selectedHistoryItem: ClipItem?
    @State var isShowingCopiedNotification = false
    @State var currentNotificationType: CopiedNotificationView.NotificationType = .copied
    @State var isAlwaysOnTop = false
    @State var isAlwaysOnTopForcedByQueue = false
    @State var userPreferredAlwaysOnTop = false
    @State var hasQueueForceOverride = false
    @AppStorage("editorSectionHeight") private var editorSectionHeight: Double = 250
    @AppStorage("historySectionHeight") private var historySectionHeight: Double = 300
    @ObservedObject var appSettings = AppSettings.shared
    @ObservedObject var fontManager = FontManager.shared
    @ObservedObject private var userCategoryStore = UserCategoryStore.shared
    
    // パフォーマンス最適化: 部分更新用のID
    @State private var editorRefreshID = UUID()
    @State private var historyRefreshID = UUID()
    @State var hoveredClearButton = false
    // キーボードイベントモニタ（リーク防止のため保持して明示的に解除）
    @State private var keyDownMonitor: Any?
    @State private var modifierMonitor: Any?
    // Copied通知の遅延非表示を管理（多重スケジュール防止）
    @State var copiedHideWorkItem: DispatchWorkItem?
    
    let onClose: (() -> Void)?
    let onAlwaysOnTopChanged: ((Bool) -> Void)?
    let onOpenSettings: (() -> Void)?
    let onSetPreventAutoClose: ((Bool) -> Void)?
    
    init(
        onClose: (() -> Void)? = nil,
        onAlwaysOnTopChanged: ((Bool) -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onSetPreventAutoClose: ((Bool) -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onAlwaysOnTopChanged = onAlwaysOnTopChanged
        self.onOpenSettings = onOpenSettings
        self.onSetPreventAutoClose = onSetPreventAutoClose
    }
}

extension MainView {
    private func handleItemSelection(_ item: ClipItem) {
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if viewModel.canUsePasteQueue,
           viewModel.isQueueModeActive {
            viewModel.handleQueueSelection(for: item, modifiers: modifiers)
            return
        }

        if viewModel.shouldInsertToEditor() {
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

    func enforceQueueAlwaysOnTopIfNeeded(queueCount: Int, isQueueModeActive: Bool) {
        let shouldForce = isQueueModeActive && queueCount > 0
        if shouldForce {
            if !isAlwaysOnTopForcedByQueue {
                isAlwaysOnTopForcedByQueue = true
                userPreferredAlwaysOnTop = isAlwaysOnTop
            }
            if !hasQueueForceOverride && !isAlwaysOnTop {
                isAlwaysOnTop = true
                onAlwaysOnTopChanged?(true)
            }
        } else {
            if isAlwaysOnTopForcedByQueue {
                isAlwaysOnTopForcedByQueue = false
                hasQueueForceOverride = false
                let target = userPreferredAlwaysOnTop
                if isAlwaysOnTop != target {
                    isAlwaysOnTop = target
                    onAlwaysOnTopChanged?(target)
                }
            }
        }
    }

    var body: some View {
        mainContent
            .environment(\.locale, appSettings.appLocale)
    }
    
    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            if appSettings.editorPosition == "disabled" {
                historyAndPinnedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
        .onReceive(
            NotificationCenter.default.publisher(for: .editorFontSettingsChanged)
                .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        ) { _ in
            // エディタセクションのみを更新（デバウンスを長くしてパフォーマンス向上）
            editorRefreshID = UUID()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .historyFontSettingsChanged)
                .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        ) { _ in
            // 履歴セクションのみを更新（デバウンスを長くしてパフォーマンス向上）
            historyRefreshID = UUID()
        }
        .onAppear {
            userPreferredAlwaysOnTop = isAlwaysOnTop
            enforceQueueAlwaysOnTopIfNeeded(
                queueCount: viewModel.pasteQueue.count,
                isQueueModeActive: viewModel.isQueueModeActive
            )
            // 既存のモニタがあれば解除
            if let monitor = keyDownMonitor {
                NSEvent.removeMonitor(monitor)
                keyDownMonitor = nil
            }
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let eventModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let copyModifiers = NSEvent.ModifierFlags(
                    rawValue: UInt(appSettings.editorCopyHotkeyModifierFlags)
                )
                    .intersection(.deviceIndependentFlagsMask)
                let clearModifiers = NSEvent.ModifierFlags(
                    rawValue: UInt(appSettings.editorClearHotkeyModifierFlags)
                )
                    .intersection(.deviceIndependentFlagsMask)

                // Editor Copy Hotkey (always enabled)
                if appSettings.editorCopyHotkeyKeyCode > 0,
                   event.keyCode == UInt16(appSettings.editorCopyHotkeyKeyCode),
                   eventModifiers == copyModifiers {
                    confirmAction()
                    return nil
                }

                // Editor Clear Hotkey (always enabled)
                if appSettings.editorClearHotkeyKeyCode > 0,
                   event.keyCode == UInt16(appSettings.editorClearHotkeyKeyCode),
                   eventModifiers == clearModifiers {
                    clearAction()
                    return nil
                }

                // Enter キーでアクションを実行
                if event.keyCode == 36 { // Enter key
                    if let selectedItem = selectedHistoryItem,
                       selectedItem.isActionable {
                        selectedItem.performAction()
                        return nil // イベントを消費
                    }
                }
                // Cmd+O 実行は不要（削除）
                return event
            }

            if let monitor = modifierMonitor {
                NSEvent.removeMonitor(monitor)
                modifierMonitor = nil
            }
            modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                let normalized = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                viewModel.handleModifierFlagsChanged(normalized)
                return event
            }
            let currentFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            viewModel.handleModifierFlagsChanged(currentFlags)
        }
        .onDisappear {
            if let monitor = keyDownMonitor {
                NSEvent.removeMonitor(monitor)
                keyDownMonitor = nil
            }
            if let monitor = modifierMonitor {
                NSEvent.removeMonitor(monitor)
                modifierMonitor = nil
            }
            // Cancel any scheduled hide for copied notification to avoid retaining self after window closes
            copiedHideWorkItem?.cancel()
            copiedHideWorkItem = nil
            isShowingCopiedNotification = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCopiedNotification)) { _ in
            showCopiedNotification(.copied)
        }
        .onReceive(viewModel.$pasteQueue) { queue in
            enforceQueueAlwaysOnTopIfNeeded(
                queueCount: queue.count,
                isQueueModeActive: viewModel.isQueueModeActive
            )
        }
        .onReceive(viewModel.$pasteMode) { _ in
            enforceQueueAlwaysOnTopIfNeeded(
                queueCount: viewModel.pasteQueue.count,
                isQueueModeActive: viewModel.isQueueModeActive
            )
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
                ClipItemCategory.url
            ]
                .filter { isCategoryFilterEnabled($0) }
            let customCategories: [UserCategory] = {
                var list = userCategoryStore.userDefinedFilters()
                if appSettings.filterCategoryNone {
                    list.insert(userCategoryStore.noneCategory(), at: 0)
                }
                return list
            }()
            
            // フィルターパネルを常に表示（ピンフィルターがあるため）
                VStack(spacing: 6) {
                    // ピン留めフィルター（一番上に配置）
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.togglePinnedFilter()
                        }
                    }, label: {
                        VStack(spacing: 3) {
                            ZStack {
                                Circle()
                                    .fill(viewModel.isPinnedFilterActive ? 
                                        Color.accentColor : 
                                        Color.secondary.opacity(0.1))
                                    .frame(width: 30, height: 30)
                                    .shadow(
                                        color: viewModel.isPinnedFilterActive ? 
                                            Color.accentColor.opacity(0.3) : .clear,
                                        radius: 3,
                                        y: 2
                                    )
                                
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(viewModel.isPinnedFilterActive ? 
                                        .white : .secondary)
                            }
                            
                            Text("Pinned")
                                .font(.system(size: 9))
                                .foregroundColor(viewModel.isPinnedFilterActive ? 
                                    .primary : .secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 52)
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
                            VStack(spacing: 3) {
                                ZStack {
                                    Circle()
                                        .fill(viewModel.selectedCategory == category ? 
                                            Color.accentColor : 
                                            Color.secondary.opacity(0.1))
                                        .frame(width: 30, height: 30)
                                        .shadow(
                                            color: viewModel.selectedCategory == category ? 
                                                Color.accentColor.opacity(0.3) : .clear,
                                            radius: 3,
                                            y: 2
                                        )
                                    
                                    Image(systemName: category.icon)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(viewModel.selectedCategory == category ? 
                                            .white : .secondary)
                                }
                                
                                Text(category.localizedName)
                                    .font(.system(size: 9))
                                    .foregroundColor(viewModel.selectedCategory == category ? 
                                        .primary : .secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 52)
                        })
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(viewModel.selectedCategory == category ? 1.05 : 1.0)
                        .animation(.spring(response: 0.3), value: viewModel.selectedCategory)
                    }
                    // ユーザ定義カテゴリのフィルタ
                    ForEach(customCategories) { cat in
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                viewModel.toggleUserCategoryFilter(cat.id)
                            }
                        }, label: {
                            VStack(spacing: 3) {
                                ZStack {
                                    Circle()
                                        .fill(viewModel.selectedUserCategoryId == cat.id ?
                                              Color.accentColor :
                                              Color.secondary.opacity(0.1))
                                        .frame(width: 30, height: 30)
                                        .shadow(
                                            color: viewModel.selectedUserCategoryId == cat.id ?
                                                Color.accentColor.opacity(0.3) : .clear,
                                            radius: 3,
                                            y: 2
                                        )

                                    Image(systemName: cat.iconSystemName)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(viewModel.selectedUserCategoryId == cat.id ?
                                                         .white : .secondary)
                                }

                                Text(cat.name)
                                    .font(.system(size: 9))
                                    .foregroundColor(viewModel.selectedUserCategoryId == cat.id ?
                                                     .primary : .secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 52)
                        })
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(viewModel.selectedUserCategoryId == cat.id ? 1.05 : 1.0)
                        .animation(.spring(response: 0.3), value: viewModel.selectedUserCategoryId)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 6)
                .background(
                    Color(NSColor.controlBackgroundColor).opacity(0.5)
                )
            
            // メインコンテンツ（履歴セクションのみ）
            MainViewHistorySection(
                history: viewModel.history,
                currentClipboardContent: viewModel.currentClipboardContent,
                selectedHistoryItem: $selectedHistoryItem,
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
                onChangeUserCategory: { item, catId in
                    Task { @MainActor in
                        var updated = item
                        updated.userCategoryId = catId
                        if let adapter = viewModel.clipboardService as? ModernClipboardServiceAdapter {
                            await adapter.updateItem(updated)
                        }
                    }
                },
                onOpenCategoryManager: { presentCategoryManager() },
                selectedCategory: $viewModel.selectedCategory,
                initialSearchText: viewModel.searchText,
                onSearchTextChanged: { text in
                    viewModel.searchText = text
                },
                onLoadMore: { item in
                    viewModel.loadMoreHistoryIfNeeded(currentItem: item)
                },
                hasMoreItems: viewModel.hasMoreHistory,
                queueEnabled: viewModel.canUsePasteQueue,
                pasteMode: viewModel.pasteMode,
                onToggleQueueMode: { viewModel.toggleQueueMode() },
                onToggleQueueRepetition: { viewModel.toggleQueueRepetition() },
                queueBadgeProvider: viewModel.queueBadge(for:),
                queueSelectionPreview: viewModel.queueSelectionPreview
            )
            .id(historyRefreshID)
        }
    }

    // 下部バー
    @ViewBuilder
    private var bottomBar: some View { bottomBarContent }
}
