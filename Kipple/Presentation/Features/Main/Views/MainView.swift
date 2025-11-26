//
//  MainView.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//
import SwiftUI
import AppKit
import Combine

enum MainViewPreventAutoCloseReason: Hashable {
    case pinRelease
    case quitConfirmation
    case categoryManager
}

struct MainView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State var selectedHistoryItem: ClipItem?
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
    @ObservedObject var userCategoryStore = UserCategoryStore.shared
    
    // パフォーマンス最適化: 部分更新用のID
    @State private var editorRefreshID = UUID()
    @State var historyRefreshID = UUID()
    @State var historyCopyScrollRequest: HistoryCopyScrollRequest?
    @State var historyHoverResetRequest: HistoryHoverResetRequest?
    @State var hoveredClearButton = false
    // キーボードイベントモニタ（リーク防止のため保持して明示的に解除）
    @State private var keyDownMonitor: Any?
    @State private var modifierMonitor: Any?
    // Copied通知の遅延非表示を管理（多重スケジュール防止）
    @State var copiedHideWorkItem: DispatchWorkItem?
    @State var activePreventAutoCloseReasons: Set<MainViewPreventAutoCloseReason> = []
    @State var editorHeightResetID: UUID?
    @State private var lastKnownEditorPosition: String = AppSettings.shared.editorPosition
    private let minimumSectionHeight: Double = 150
    private let titleBarHeight: CGFloat = 8
    @State private var isShowingQuitConfirmation = false
    @State private var ignoreNextAutoCloseAfterQueueFinish = false
    @State private var pendingReactivateAfterQueueFinish = false
    @State private var wasQueueEngagedBeforeLatestUpdate = false
    var quitConfirmationBinding: Binding<Bool> {
        Binding(
            get: { isShowingQuitConfirmation },
            set: { newValue in
                if newValue {
                    requestPreventAutoClose(.quitConfirmation)
                } else {
                    releasePreventAutoClose(.quitConfirmation)
                }
                isShowingQuitConfirmation = newValue
            }
        )
    }
    
    let onClose: (() -> Void)?
    let onReactivatePreviousApp: (() -> Void)?
    let onAlwaysOnTopChanged: ((Bool) -> Void)?
    let onOpenSettings: (() -> Void)?
    let onOpenAbout: (() -> Void)?
    let onQuitApplication: (() -> Void)?
    let onSetPreventAutoClose: ((Bool) -> Void)?
    let onStartTextCapture: (() -> Void)?

    init(
        titleBarState: MainWindowTitleBarState = MainWindowTitleBarState(),
        onClose: (() -> Void)? = nil,
        onReactivatePreviousApp: (() -> Void)? = nil,
        onAlwaysOnTopChanged: ((Bool) -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onOpenAbout: (() -> Void)? = nil,
        onQuitApplication: (() -> Void)? = nil,
        onSetPreventAutoClose: ((Bool) -> Void)? = nil,
        onStartTextCapture: (() -> Void)? = nil
    ) {
        self.titleBarState = titleBarState
        self.onClose = onClose
        self.onReactivatePreviousApp = onReactivatePreviousApp
        self.onAlwaysOnTopChanged = onAlwaysOnTopChanged
        self.onOpenSettings = onOpenSettings
        self.onOpenAbout = onOpenAbout
        self.onQuitApplication = onQuitApplication
        self.onSetPreventAutoClose = onSetPreventAutoClose
        self.onStartTextCapture = onStartTextCapture
    }
}

extension MainView {
    /// 履歴コピー後に前面アプリへフォーカスを戻す
    func reactivatePreviousAppAfterCopy() {
        onReactivatePreviousApp?()
    }

    func showQuitConfirmationAlert() {
        requestPreventAutoClose(.quitConfirmation)
        DispatchQueue.main.async {
            isShowingQuitConfirmation = true
        }
    }

    func cancelQuitConfirmationIfNeeded() {
        guard isShowingQuitConfirmation else { return }
        releasePreventAutoClose(.quitConfirmation)
        isShowingQuitConfirmation = false
    }

    func confirmQuitFromDialog() {
        releasePreventAutoClose(.quitConfirmation)
        isShowingQuitConfirmation = false
        onQuitApplication?()
    }

    func handleItemSelection(_ item: ClipItem) {
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if viewModel.canUsePasteQueue,
           viewModel.isQueueModeActive {
            viewModel.handleQueueSelection(for: item, modifiers: modifiers)
            return
        }

        if viewModel.shouldInsertToEditor() {
            viewModel.selectHistoryItem(item, forceInsert: true)
            return
        }

        historyHoverResetRequest = HistoryHoverResetRequest()

        let wantsAutoPaste = appSettings.historySelectPaste && !viewModel.isQueueModeActive
        let shouldAutoPaste = wantsAutoPaste && AutoPasteController.shared.canAutoPaste()

        if shouldAutoPaste {
            Task { @MainActor in
                await viewModel.selectHistoryItemAndWait(item)
                if !isAlwaysOnTop {
                    onClose?()
                }
                onReactivatePreviousApp?()
                AutoPasteController.shared.schedulePaste()
            }
            return
        }

        Task { @MainActor in
            let needsNotification = isAlwaysOnTop
            if !isAlwaysOnTop {
                onClose?()
            }

            await viewModel.selectHistoryItemAndWait(item)

            // Always return focus to前面アプリ（ピン留め中でも復帰）
            reactivatePreviousAppAfterCopy()

            // コピー時の処理
            if needsNotification {
                // Always on Topが有効な場合のみ通知を表示
                showCopiedNotification(.copied)
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
                let shouldDisablePin = isAlwaysOnTop && !target
                if shouldDisablePin {
                    requestPreventAutoClose(.pinRelease)
                }
                if isAlwaysOnTop != target {
                    isAlwaysOnTop = target
                    onAlwaysOnTopChanged?(target)
                }
                if shouldDisablePin {
                    releasePreventAutoClose(.pinRelease)
                    if !isQueueModeActive {
                        pendingReactivateAfterQueueFinish = true
                        attemptPendingReactivateAfterQueueFinish()
                    }
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
        .onReceive(NotificationCenter.default.publisher(for: .mainWindowDidHide)) { _ in
            if historyCopyScrollRequest == nil {
                historyCopyScrollRequest = HistoryCopyScrollRequest()
            }
            historyHoverResetRequest = HistoryHoverResetRequest()
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
            ignoreNextAutoCloseAfterQueueFinish = false
            pendingReactivateAfterQueueFinish = false
            if !activePreventAutoCloseReasons.isEmpty {
                activePreventAutoCloseReasons.removeAll()
                onSetPreventAutoClose?(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCopiedNotification)) { _ in
            showCopiedNotification(.copied)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if ignoreNextAutoCloseAfterQueueFinish {
                ignoreNextAutoCloseAfterQueueFinish = false
            }
            attemptPendingReactivateAfterQueueFinish(ignoreWindowActiveState: true)
        }
        .onReceive(viewModel.$pasteQueue) { queue in
            enforceQueueAlwaysOnTopIfNeeded(
                queueCount: queue.count,
                isQueueModeActive: viewModel.isQueueModeActive
            )
            syncTitleBarState()
            updateQueueFinishAutoCloseState(
                queueCount: queue.count,
                isQueueModeActive: viewModel.isQueueModeActive
            )
            if queue.isEmpty, viewModel.pasteMode != .clipboard {
                viewModel.resetPasteQueue()
            }
        }
        .onReceive(viewModel.$pasteMode) { _ in
            enforceQueueAlwaysOnTopIfNeeded(
                queueCount: viewModel.pasteQueue.count,
                isQueueModeActive: viewModel.isQueueModeActive
            )
            syncTitleBarState()
            updateQueueFinishAutoCloseState(
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

    private func updateQueueFinishAutoCloseState(queueCount: Int, isQueueModeActive: Bool) {
        let queueFinished = queueCount == 0 && !isQueueModeActive && wasQueueEngagedBeforeLatestUpdate
        let queueEngaged = isQueueModeActive || queueCount > 0
        defer { wasQueueEngagedBeforeLatestUpdate = queueEngaged }
        if queueFinished {
            pendingReactivateAfterQueueFinish = true
            if NSApp.isActive {
                ignoreNextAutoCloseAfterQueueFinish = true
            } else if ignoreNextAutoCloseAfterQueueFinish {
                ignoreNextAutoCloseAfterQueueFinish = false
                attemptPendingReactivateAfterQueueFinish(ignoreWindowActiveState: true)
            } else {
                attemptPendingReactivateAfterQueueFinish(ignoreWindowActiveState: true)
            }
        } else if ignoreNextAutoCloseAfterQueueFinish {
            ignoreNextAutoCloseAfterQueueFinish = false
            pendingReactivateAfterQueueFinish = false
        } else if pendingReactivateAfterQueueFinish {
            pendingReactivateAfterQueueFinish = false
        }
    }

    private func attemptPendingReactivateAfterQueueFinish(ignoreWindowActiveState: Bool = false) {
        guard pendingReactivateAfterQueueFinish else { return }
        guard activePreventAutoCloseReasons.isEmpty else { return }
        guard !viewModel.isQueueModeActive else { return }
        let canReactivateNow: Bool
        if ignoreWindowActiveState {
            canReactivateNow = true
        } else {
            canReactivateNow = !ignoreNextAutoCloseAfterQueueFinish && !NSApp.isActive
        }
        guard canReactivateNow else { return }
        pendingReactivateAfterQueueFinish = false
        onReactivatePreviousApp?()
    }
    
    // エディタセクション
    @ViewBuilder
    private var editorSection: some View {
        VStack(spacing: 0) {
            MainViewEditorSection(
                editorText: $viewModel.editorText,
                isAlwaysOnTop: $isAlwaysOnTop,
                onToggleAlwaysOnTop: toggleAlwaysOnTop,
                onClear: clearAction
            )
            MainViewControlSection(
                onCopy: confirmAction,
                onSplitCopy: splitEditorIntoHistory,
                onTrim: trimAction
            )
        }
        .id(editorRefreshID)
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
