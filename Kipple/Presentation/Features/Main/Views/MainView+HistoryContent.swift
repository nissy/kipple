//
//  MainView+HistoryContent.swift
//  Kipple
//
//  Created by Kipple on 2025/11/16.

import SwiftUI

extension MainView {
    // 履歴とピン留めセクションのコンテンツ
    @ViewBuilder
    var historyAndPinnedContent: some View {
        let queueLoopToggleHandler: () -> Void = {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                viewModel.toggleQueueRepetition()
            }
            syncTitleBarState()
        }

        MainViewHistorySection(
            history: viewModel.history,
            currentClipboardContent: viewModel.currentClipboardContent,
            currentClipboardItemID: viewModel.currentClipboardItemID,
            selectedHistoryItem: $selectedHistoryItem,
            copyScrollRequest: $historyCopyScrollRequest,
            hoverResetRequest: $historyHoverResetRequest,
            onSelectItem: handleItemSelection,
            onLongPressItem: { item in
                guard viewModel.canUsePasteQueue else {
                    NotificationCenter.default.post(
                        name: .queuePastePermissionRequested,
                        object: nil
                    )
                    return
                }
                guard !viewModel.isQueueModeActive else { return }
                AutoPasteController.shared.cancelPendingPaste()
                historyHoverResetRequest = HistoryHoverResetRequest()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    viewModel.startQueueMode(with: item)
                }
                syncTitleBarState()
            },
            onOpenItem: { item in
                guard item.isActionable else { return }
                item.performAction()
            },
            onSplitEditorIntoHistory: { item in
                splitHistoryItemIntoLines(item)
            },
            onTogglePin: { item in
                let wasPinned = item.isPinned
                let newState = viewModel.togglePinSync(for: item)
                if !wasPinned && !newState {
                    showCopiedNotification(.pinLimitReached)
                }
            },
            onDelete: { item in
                viewModel.deleteItemSync(item)
            },
            onChangeUserCategory: { item, categoryID, enabled in
                guard let adapter = viewModel.clipboardService as? ModernClipboardServiceAdapter else {
                    throw MCPFailure.unavailable
                }
                try await adapter.setCategory(itemID: item.id, categoryID: categoryID, enabled: enabled)
            },
            onOpenCategoryManager: { presentCategoryManager() },
            categoryFilter: $viewModel.categoryFilter,
            searchText: $viewModel.searchText,
            onLoadMore: { item in
                viewModel.loadMoreHistoryIfNeeded(currentItem: item)
            },
            hasMoreItems: viewModel.hasMoreHistory,
            isLoadingMore: viewModel.isLoadingMoreHistory,
            isPinnedFilterActive: viewModel.isPinnedFilterActive,
            onTogglePinnedFilter: { viewModel.togglePinnedFilter() },
            pasteMode: viewModel.pasteMode,
            queueBadgeProvider: viewModel.queueBadge(for:),
            queueSelectionPreview: viewModel.queueSelectionPreview,
            isQueueLoopActive: viewModel.pasteMode == .queueToggle,
            canToggleQueueLoop: viewModel.canUsePasteQueue,
            onToggleQueueLoop: queueLoopToggleHandler
        )
        .id(historyRefreshID)
        .environment(\.categoryPopoverChanged, CategoryPopoverAction { itemID, presented in
            if presented {
                requestPreventAutoClose(.categoryPopover(itemID))
                if let itemID { viewModel.categoryEditingItemID = itemID }
                historyHoverResetRequest = HistoryHoverResetRequest()
            } else {
                if viewModel.categoryEditingItemID == itemID { viewModel.categoryEditingItemID = nil }
                releasePreventAutoClose(.categoryPopover(itemID))
            }
        })
    }
}
