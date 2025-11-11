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
    let titleBarState: MainWindowTitleBarState
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
    @State var editorHeightResetID: UUID?
    @State private var lastKnownEditorPosition: String = AppSettings.shared.editorPosition
    private let minimumSectionHeight: Double = 150
    private let titleBarHeight: CGFloat = 8
    @State private var isShowingQuitConfirmation = false
    var quitConfirmationBinding: Binding<Bool> {
        Binding(
            get: { isShowingQuitConfirmation },
            set: { newValue in
                if !newValue {
                    onSetPreventAutoClose?(false)
                }
                isShowingQuitConfirmation = newValue
            }
        )
    }
    
    let onClose: (() -> Void)?
    let onAlwaysOnTopChanged: ((Bool) -> Void)?
    let onOpenSettings: (() -> Void)?
    let onOpenAbout: (() -> Void)?
    let onQuitApplication: (() -> Void)?
    let onSetPreventAutoClose: ((Bool) -> Void)?
    let onStartTextCapture: (() -> Void)?

    init(
        titleBarState: MainWindowTitleBarState = MainWindowTitleBarState(),
        onClose: (() -> Void)? = nil,
        onAlwaysOnTopChanged: ((Bool) -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onOpenAbout: (() -> Void)? = nil,
        onQuitApplication: (() -> Void)? = nil,
        onSetPreventAutoClose: ((Bool) -> Void)? = nil,
        onStartTextCapture: (() -> Void)? = nil
    ) {
        self.titleBarState = titleBarState
        self.onClose = onClose
        self.onAlwaysOnTopChanged = onAlwaysOnTopChanged
        self.onOpenSettings = onOpenSettings
        self.onOpenAbout = onOpenAbout
        self.onQuitApplication = onQuitApplication
        self.onSetPreventAutoClose = onSetPreventAutoClose
        self.onStartTextCapture = onStartTextCapture
    }
}

extension MainView {
    func showQuitConfirmationAlert() {
        onSetPreventAutoClose?(true)
        DispatchQueue.main.async {
            isShowingQuitConfirmation = true
        }
    }

    func cancelQuitConfirmationIfNeeded() {
        guard isShowingQuitConfirmation else { return }
        onSetPreventAutoClose?(false)
        isShowingQuitConfirmation = false
    }

    func confirmQuitFromDialog() {
        onSetPreventAutoClose?(false)
        isShowingQuitConfirmation = false
        onQuitApplication?()
    }

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
        defer { syncTitleBarState() }
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
                    topHeight: splitTopSectionHeight,
                    minTopHeight: minimumSectionHeight,
                    minBottomHeight: minimumSectionHeight,
                    reset: splitResetConfiguration,
                    preferredHeights: splitPreferredHeightsProvider,
                    onHeightsChanged: updateSectionHeights(topHeight:bottomHeight:),
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
        .background(
            Color(NSColor.windowBackgroundColor)
        )

        .padding(.top, titleBarHeight)
        .frame(minWidth: 300, maxWidth: .infinity)
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
        .onChange(of: appSettings.editorPosition) { newValue in
            if lastKnownEditorPosition == "disabled", newValue != "disabled" {
                editorHeightResetID = UUID()
            }
            if newValue == "disabled" {
                editorHeightResetID = nil
            }
            lastKnownEditorPosition = newValue
            syncTitleBarState()
        }
        .onAppear {
            titleBarState.toggleAlwaysOnTopHandler = {
                toggleAlwaysOnTop()
            }
            titleBarState.toggleEditorHandler = {
                toggleEditorVisibility(animated: true)
            }
            titleBarState.startCaptureHandler = {
                startCaptureFromTitleBar()
            }
            titleBarState.toggleQueueHandler = {
                toggleQueueModeFromTitleBar()
            }
            syncTitleBarState()
            userPreferredAlwaysOnTop = isAlwaysOnTop
            lastKnownEditorPosition = appSettings.editorPosition
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
            cancelQuitConfirmationIfNeeded()
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
            titleBarState.toggleAlwaysOnTopHandler = nil
            titleBarState.toggleEditorHandler = nil
            titleBarState.startCaptureHandler = nil
            titleBarState.toggleQueueHandler = nil
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

    private var splitTopSectionHeight: Binding<Double> {
        Binding(
            get: {
                if appSettings.editorPosition == "top" {
                    return editorSectionHeight
                }
                return historySectionHeight
            },
            set: { newValue in
                if appSettings.editorPosition == "top" {
                    editorSectionHeight = newValue
                } else {
                    historySectionHeight = newValue
                }
            }
        )
    }

    private func updateSectionHeights(topHeight: Double, bottomHeight: Double) {
        switch appSettings.editorPosition {
        case "top":
            editorSectionHeight = topHeight
            historySectionHeight = bottomHeight
        case "bottom":
            historySectionHeight = topHeight
            editorSectionHeight = bottomHeight
        default:
            break
        }
        if editorHeightResetID != nil {
            editorHeightResetID = nil
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
                onClear: clearAction,
                onSplitCopy: splitEditorIntoHistory
            )
        }
        .id(editorRefreshID)
    }
    
    // 履歴とピン留めセクションのコンテンツ
    @ViewBuilder
    private var historyAndPinnedContent: some View {
        // 有効なフィルターを取得
        let enabledCategories = [
            ClipItemCategory.url
        ]
            .filter { isCategoryFilterEnabled($0) }
        let customCategories: [UserCategory] = {
            var list = userCategoryStore.userDefinedFilters()
            if appSettings.filterCategoryNone {
                var noneCategory = userCategoryStore.noneCategory()
                if noneCategory.name != "None" {
                    noneCategory.name = "None"
                }
                list.insert(noneCategory, at: 0)
            }
            return list
        }()

        let queueLoopToggleHandler: () -> Void = {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                viewModel.toggleQueueRepetition()
            }
            syncTitleBarState()
        }

        return MainViewHistorySection(
                history: viewModel.history,
                currentClipboardContent: viewModel.currentClipboardContent,
                selectedHistoryItem: $selectedHistoryItem,
                onSelectItem: handleItemSelection,
                onOpenItem: { item in
                    guard item.isActionable else { return }
                    item.performAction()
                },
                onInsertToEditor: { item in
                    viewModel.selectHistoryItem(item, forceInsert: true)
                },
                onTogglePin: { item in
                    let wasPinned = item.isPinned
                    let newState = viewModel.togglePinSync(for: item)
                    if !wasPinned && !newState {
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
                isLoadingMore: viewModel.isLoadingMoreHistory,
                isPinnedFilterActive: viewModel.isPinnedFilterActive,
                onTogglePinnedFilter: { viewModel.togglePinnedFilter() },
                availableCategories: enabledCategories,
                customCategories: customCategories,
                selectedUserCategoryId: viewModel.selectedUserCategoryId,
                onToggleUserCategoryFilter: { viewModel.toggleUserCategoryFilter($0) },
                pasteMode: viewModel.pasteMode,
                queueBadgeProvider: viewModel.queueBadge(for:),
                queueSelectionPreview: viewModel.queueSelectionPreview,
                isQueueLoopActive: viewModel.pasteMode == .queueToggle,
                canToggleQueueLoop: viewModel.canUsePasteQueue,
                onToggleQueueLoop: queueLoopToggleHandler
            )
            .id(historyRefreshID)
    }

    // 下部バー
    @ViewBuilder
    private var bottomBar: some View { bottomBarContent }
}

private extension MainView {
    var splitPreferredHeightsProvider: (() -> (top: Double?, bottom: Double?))? {
        switch appSettings.editorPosition {
        case "top":
            return { (top: editorSectionHeight, bottom: nil) }
        case "bottom":
            return { (top: nil, bottom: editorSectionHeight) }
        default:
            return nil
        }
    }

    var splitResetConfiguration: SplitViewResetConfiguration? {
        guard let id = editorHeightResetID else { return nil }
        switch appSettings.editorPosition {
        case "top":
            return SplitViewResetConfiguration(
                id: id,
                preferredTopHeight: minimumSectionHeight,
                preferredBottomHeight: nil
            )
        case "bottom":
            return SplitViewResetConfiguration(
                id: id,
                preferredTopHeight: nil,
                preferredBottomHeight: minimumSectionHeight
            )
        default:
            return nil
        }
    }
}
