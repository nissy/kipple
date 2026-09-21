//
//  MainViewHistorySection.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI
import AppKit

struct MainViewHistorySection: View {
    let history: [ClipItem]
    let currentClipboardContent: String?
    let currentClipboardItemID: UUID?
    @Binding var selectedHistoryItem: ClipItem?
    @Binding var copyScrollRequest: HistoryCopyScrollRequest?
    @Binding var hoverResetRequest: HistoryHoverResetRequest?
    let onSelectItem: (ClipItem) -> Void
    let onOpenItem: ((ClipItem) -> Void)?
    let onSplitEditorIntoHistory: (ClipItem) -> Void
    let onTogglePin: (ClipItem) -> Void
    let onDelete: ((ClipItem) -> Void)?
    // 追加: ユーザカテゴリ変更/管理
    let onChangeUserCategory: ((ClipItem, UUID, Bool) async throws -> Void)?
    let onOpenCategoryManager: (() -> Void)?
    @Binding var categoryFilter: CategoryFilter
    @Binding var searchText: String
    let onLoadMore: (ClipItem) -> Void
    let hasMoreItems: Bool
    let isLoadingMore: Bool
    let isPinnedFilterActive: Bool
    let onTogglePinnedFilter: () -> Void
    let pasteMode: MainViewModel.PasteMode
    let queueBadgeProvider: (ClipItem) -> Int?
    let queueSelectionPreview: Set<UUID>
    let isQueueLoopActive: Bool
    let canToggleQueueLoop: Bool
    let onToggleQueueLoop: () -> Void
    @ObservedObject private var fontManager = FontManager.shared
    @State private var canScrollToTop = false

    init(
        history: [ClipItem],
        currentClipboardContent: String?,
        currentClipboardItemID: UUID?,
        selectedHistoryItem: Binding<ClipItem?>,
        copyScrollRequest: Binding<HistoryCopyScrollRequest?>,
        hoverResetRequest: Binding<HistoryHoverResetRequest?>,
        onSelectItem: @escaping (ClipItem) -> Void,
        onOpenItem: ((ClipItem) -> Void)? = nil,
        onSplitEditorIntoHistory: @escaping (ClipItem) -> Void,
        onTogglePin: @escaping (ClipItem) -> Void,
        onDelete: ((ClipItem) -> Void)?,
        onChangeUserCategory: ((ClipItem, UUID, Bool) async throws -> Void)? = nil,
        onOpenCategoryManager: (() -> Void)? = nil,
        categoryFilter: Binding<CategoryFilter>,
        searchText: Binding<String>,
        onLoadMore: @escaping (ClipItem) -> Void,
        hasMoreItems: Bool,
        isLoadingMore: Bool,
        isPinnedFilterActive: Bool,
        onTogglePinnedFilter: @escaping () -> Void,
        pasteMode: MainViewModel.PasteMode,
        queueBadgeProvider: @escaping (ClipItem) -> Int?,
        queueSelectionPreview: Set<UUID>,
        isQueueLoopActive: Bool,
        canToggleQueueLoop: Bool,
        onToggleQueueLoop: @escaping () -> Void
    ) {
        self.history = history
        self.currentClipboardContent = currentClipboardContent
        self.currentClipboardItemID = currentClipboardItemID
        self._selectedHistoryItem = selectedHistoryItem
        self._copyScrollRequest = copyScrollRequest
        self._hoverResetRequest = hoverResetRequest
        self.onSelectItem = onSelectItem
        self.onOpenItem = onOpenItem
        self.onSplitEditorIntoHistory = onSplitEditorIntoHistory
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
        self.onChangeUserCategory = onChangeUserCategory
        self.onOpenCategoryManager = onOpenCategoryManager
        self._categoryFilter = categoryFilter
        self._searchText = searchText
        self.onLoadMore = onLoadMore
        self.hasMoreItems = hasMoreItems
        self.isLoadingMore = isLoadingMore
        self.isPinnedFilterActive = isPinnedFilterActive
        self.onTogglePinnedFilter = onTogglePinnedFilter
        self.pasteMode = pasteMode
        self.queueBadgeProvider = queueBadgeProvider
        self.queueSelectionPreview = queueSelectionPreview
        self.isQueueLoopActive = isQueueLoopActive
        self.canToggleQueueLoop = canToggleQueueLoop
        self.onToggleQueueLoop = onToggleQueueLoop
    }

    var body: some View {
        return VStack(spacing: 0) {
            historyToolbar

            HistoryListView(
                history: history,
                selectedHistoryItem: selectedHistoryItem,
                currentClipboardItemID: currentClipboardItemID,
                queueBadgeProvider: queueBadgeProvider,
                queueSelectionPreview: queueSelectionPreview,
                pasteMode: pasteMode,
                historyFont: Font(fontManager.historyFont),
                onSelectItem: onSelectItem,
                onTogglePin: onTogglePin,
                onDelete: onDelete,
                onChangeUserCategory: onChangeUserCategory,
                onOpenCategoryManager: onOpenCategoryManager,
                onOpenItem: onOpenItem,
                onSplitEditorIntoHistory: onSplitEditorIntoHistory,
                onLoadMore: onLoadMore,
                hasMoreItems: hasMoreItems,
                isLoadingMore: isLoadingMore,
                canScrollToTop: $canScrollToTop,
                copyScrollRequest: $copyScrollRequest,
                hoverResetRequest: $hoverResetRequest
            )
        }
        .padding(.horizontal, MainViewMetrics.HistoryColumns.sectionHorizontalPadding
                 + MainViewMetrics.HistoryColumns.horizontalInset)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var historyToolbar: some View {
        historyToolbarContent
    }

    private var historyToolbarContent: some View {
        HistoryColumnsRow(showsQueue: pasteMode != .clipboard) {
            queueLoopControl
        } pin: {
            pinnedFilterButton
        } category: {
            categoryFilterControl
        } content: {
            searchField
        } trailing: {
            scrollToTopButton
        }
        .padding(.top, MainViewMetrics.HistoryColumns.toolbarTopPadding)
        .padding(.bottom, MainViewMetrics.HistoryColumns.toolbarBottomPadding)
    }

    private var pinnedFilterButton: some View {
        Button {
            onTogglePinnedFilter()
        } label: {
            circleFilterIcon(
                iconName: isPinnedFilterActive ? "pin.fill" : "pin",
                iconColor: KippleButtonAppearance.foreground(isActive: isPinnedFilterActive),
                iconFont: MainViewMetrics.HistoryFilterIcon.defaultFont,
                rotation: isPinnedFilterActive ? 0 : -45,
                isActive: isPinnedFilterActive
            )
        }
        .kippleSystemCircleButton(
            size: MainViewMetrics.HistoryFilterIcon.diameter,
            isActive: isPinnedFilterActive
        )
        .frame(
            width: MainViewMetrics.HistoryFilterIcon.diameter,
            height: MainViewMetrics.HistoryFilterIcon.diameter
        )
        .help(
            Text(
                isPinnedFilterActive
                ? String(localized: "Pinned only")
                : String(localized: "Pins: All")
            )
        )
    }

    private var categoryFilterControl: some View {
        CategoryFilterControl(selection: $categoryFilter, onOpenManager: onOpenCategoryManager)
    }

    private func toolbarFilterAffordance(isActive: Bool, isHovered: Bool) -> some View {
        Circle()
            .fill(
                isActive || isHovered
                ? KippleButtonAppearance.inactivePillFill
                : Color.clear
            )
    }

    private func toolbarFilterIconForeground(isActive: Bool) -> Color {
        isActive ? .primary : KippleButtonAppearance.inactiveForeground
    }

    private var queueLoopControl: some View {
        Button {
            onToggleQueueLoop()
        } label: {
            circleFilterIcon(
                iconName: "repeat",
                iconColor: KippleButtonAppearance.foreground(
                    isActive: isQueueLoopActive,
                    isEnabled: canToggleQueueLoop
                ),
                iconFont: MainViewMetrics.HistoryFilterIcon.defaultFont,
                isActive: isQueueLoopActive
            )
        }
        .kippleSystemCircleButton(
            size: MainViewMetrics.HistoryFilterIcon.diameter,
            isActive: isQueueLoopActive,
            isEnabled: canToggleQueueLoop
        )
        .frame(
            width: MainViewMetrics.HistoryFilterIcon.diameter,
            height: MainViewMetrics.HistoryFilterIcon.diameter
        )
        .disabled(!canToggleQueueLoop)
        .help(Text(String(localized: "Queue loop")))
    }

    private var searchField: some View {
        HistorySearchField(searchText: $searchText)
    }

    private var scrollToTopButton: some View {
        Button {
            copyScrollRequest = HistoryCopyScrollRequest()
        } label: {
            circleFilterIcon(
                iconName: "arrow.up.to.line",
                iconColor: KippleButtonAppearance.foreground(isActive: false, isEnabled: canScrollToTop),
                iconFont: MainViewMetrics.HistoryFilterIcon.defaultFont
            )
        }
        .kippleSystemCircleButton(
            size: MainViewMetrics.HistoryFilterIcon.diameter,
            isEnabled: canScrollToTop
        )
        .frame(
            width: MainViewMetrics.HistoryFilterIcon.diameter,
            height: MainViewMetrics.HistoryFilterIcon.diameter
        )
        .disabled(!canScrollToTop)
        .help(Text(String(localized: "history.scrollToTop")))
        .accessibilityLabel(Text(String(localized: "history.scrollToTop")))
    }

    private func circleFilterIcon(
        iconName: String,
        iconColor: Color,
        iconFont: Font = MainViewMetrics.HistoryFilterIcon.defaultFont,
        rotation: Double = 0,
        isActive: Bool = false
    ) -> some View {
        ZStack {
            Image(systemName: iconName)
                .font(iconFont)
                .foregroundColor(iconColor)
                .rotationEffect(.degrees(rotation))
                .frame(width: MainViewMetrics.HistoryFilterIcon.diameter, height: MainViewMetrics.HistoryFilterIcon.diameter)
        }
        .frame(width: MainViewMetrics.HistoryFilterIcon.diameter, height: MainViewMetrics.HistoryFilterIcon.diameter)
        .contentShape(Circle())
    }
}

private struct HistorySearchField: View {
    @Binding var searchText: String
    @ObservedObject private var fontManager = FontManager.shared
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(MainViewMetrics.HistorySearchField.iconFont)
                .foregroundColor(KippleButtonAppearance.inactiveForeground)
                .padding(.leading, 8)

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(Font(fontManager.historyFont))
                .foregroundColor(MainViewMetrics.TextColor.primary)
                .focused($isSearchFocused)
                .frame(maxHeight: .infinity)

            if !searchText.isEmpty {
                Button(action: {
                    withAnimation(.spring(response: 0.2)) {
                        searchText = ""
                    }
                }, label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(MainViewMetrics.HistorySearchField.clearIconFont)
                        .foregroundColor(KippleButtonAppearance.inactiveForeground)
                })
                .buttonStyle(PlainButtonStyle())
                .padding(.trailing, 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: MainViewMetrics.HistorySearchField.height)
        .contentShape(Rectangle())
        .onTapGesture {
            isSearchFocused = true
        }
        .background(
            RoundedRectangle(cornerRadius: MainViewMetrics.HistorySearchField.height / 2, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MainViewMetrics.HistorySearchField.height / 2, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 0.5)
        )
    }
}
