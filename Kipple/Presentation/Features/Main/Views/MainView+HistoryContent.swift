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

        MainViewHistorySection(
            history: viewModel.history,
            currentClipboardContent: viewModel.currentClipboardContent,
            currentClipboardItemID: viewModel.currentClipboardItemID,
            selectedHistoryItem: $selectedHistoryItem,
            copyScrollRequest: $historyCopyScrollRequest,
            hoverResetRequest: $historyHoverResetRequest,
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
}
