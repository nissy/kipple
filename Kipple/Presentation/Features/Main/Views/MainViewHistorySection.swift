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
    let highlightRequest: HistoryHighlightRequest?
    let onHighlightFinished: (UUID) -> Void
    let onSelectItem: (ClipItem) -> Void
    let onOpenItem: ((ClipItem) -> Void)?
    let onSplitEditorIntoHistory: (ClipItem) -> Void
    let onDelete: ((ClipItem) -> Void)?
    // 追加: ユーザカテゴリ変更/管理
    let onChangeUserCategory: ((UUID, ClipCategoryChange) async throws -> Void)?
    let onOpenCategoryManager: (() -> Void)?
    @Binding var categoryFilter: CategoryFilter
    let historyCategoryIDs: Set<UUID>
    @Binding var showOnlyDesktopNotes: Bool
    @Binding var searchText: String
    let onLoadMore: (ClipItem) -> Void
    let hasMoreItems: Bool
    let isLoadingMore: Bool
    let pasteMode: MainViewModel.PasteMode
    let queueBadgeProvider: (ClipItem) -> Int?
    let queueSelectionPreview: Set<UUID>
    let queueReorder: QueueReorderActions?
    let startupPreviews: [HistoryRowPreview]
    let resolveStartupItem: ((UUID) async -> ClipItem?)?
    @ObservedObject private var fontManager = FontManager.shared
    @State private var canScrollToTop = false

    init(
        history: [ClipItem],
        currentClipboardContent: String?,
        currentClipboardItemID: UUID?,
        selectedHistoryItem: Binding<ClipItem?>,
        copyScrollRequest: Binding<HistoryCopyScrollRequest?>,
        hoverResetRequest: Binding<HistoryHoverResetRequest?>,
        highlightRequest: HistoryHighlightRequest?,
        onHighlightFinished: @escaping (UUID) -> Void,
        onSelectItem: @escaping (ClipItem) -> Void,
        onOpenItem: ((ClipItem) -> Void)? = nil,
        onSplitEditorIntoHistory: @escaping (ClipItem) -> Void,
        onDelete: ((ClipItem) -> Void)?,
        onChangeUserCategory: ((UUID, ClipCategoryChange) async throws -> Void)? = nil,
        onOpenCategoryManager: (() -> Void)? = nil,
        categoryFilter: Binding<CategoryFilter>,
        historyCategoryIDs: Set<UUID>,
        showOnlyDesktopNotes: Binding<Bool>,
        searchText: Binding<String>,
        onLoadMore: @escaping (ClipItem) -> Void,
        hasMoreItems: Bool,
        isLoadingMore: Bool,
        pasteMode: MainViewModel.PasteMode,
        queueBadgeProvider: @escaping (ClipItem) -> Int?,
        queueSelectionPreview: Set<UUID>,
        queueReorder: QueueReorderActions? = nil,
        startupPreviews: [HistoryRowPreview] = [],
        resolveStartupItem: ((UUID) async -> ClipItem?)? = nil
    ) {
        self.history = history
        self.currentClipboardContent = currentClipboardContent
        self.currentClipboardItemID = currentClipboardItemID
        self._selectedHistoryItem = selectedHistoryItem
        self._copyScrollRequest = copyScrollRequest
        self._hoverResetRequest = hoverResetRequest
        self.highlightRequest = highlightRequest
        self.onHighlightFinished = onHighlightFinished
        self.onSelectItem = onSelectItem
        self.onOpenItem = onOpenItem
        self.onSplitEditorIntoHistory = onSplitEditorIntoHistory
        self.onDelete = onDelete
        self.onChangeUserCategory = onChangeUserCategory
        self.onOpenCategoryManager = onOpenCategoryManager
        self._categoryFilter = categoryFilter
        self.historyCategoryIDs = historyCategoryIDs
        self._showOnlyDesktopNotes = showOnlyDesktopNotes
        self._searchText = searchText
        self.onLoadMore = onLoadMore
        self.hasMoreItems = hasMoreItems
        self.isLoadingMore = isLoadingMore
        self.pasteMode = pasteMode
        self.queueBadgeProvider = queueBadgeProvider
        self.queueSelectionPreview = queueSelectionPreview
        self.queueReorder = queueReorder
        self.startupPreviews = startupPreviews
        self.resolveStartupItem = resolveStartupItem
    }

    var body: some View {
        HStack(alignment: .top, spacing: MainViewMetrics.HistoryFilterSidebar.contentSpacing) {
            historyFilters

            VStack(spacing: 0) {
                historyToolbar
                historyList
            }
        }
        .padding(.horizontal, MainViewMetrics.contentHorizontalInset)
        .padding(.vertical, 6)
    }

    private var historyFilters: some View {
        VStack(spacing: MainViewMetrics.HistoryRows.spacing) {
            HistoryFilterButton(
                systemName: showOnlyDesktopNotes ? "pin.fill" : "pin",
                label: Text("Show Only Desktop Notes"),
                isActive: showOnlyDesktopNotes
            ) {
                showOnlyDesktopNotes.toggle()
            }

            CategoryFilterControl(
                selection: $categoryFilter,
                historyCategoryIDs: historyCategoryIDs,
                onOpenManager: onOpenCategoryManager
            )
        }
        .frame(width: MainViewMetrics.HistoryFilterSidebar.width)
    }

    private var historyToolbar: some View {
        HStack(spacing: MainViewMetrics.HistoryColumns.spacing) {
            HistorySearchField(searchText: $searchText)
            scrollToTopButton
        }
        .padding(.bottom, MainViewMetrics.HistoryColumns.toolbarBottomPadding)
    }

    private var historyList: some View {
        HistoryListView(
            history: history,
            selectedHistoryItem: selectedHistoryItem,
            currentClipboardItemID: currentClipboardItemID,
            queueBadgeProvider: queueBadgeProvider,
            queueSelectionPreview: queueSelectionPreview,
            pasteMode: pasteMode,
            historyFont: Font(fontManager.historyFont),
            onSelectItem: onSelectItem,
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
            hoverResetRequest: $hoverResetRequest,
            highlightRequest: highlightRequest,
            onHighlightFinished: onHighlightFinished,
            queueReorder: queueReorder,
            startupPreviews: startupPreviews,
            resolveStartupItem: resolveStartupItem
        )
    }

    private var scrollToTopButton: some View {
        Button {
            copyScrollRequest = HistoryCopyScrollRequest()
        } label: {
            circleFilterIcon(
                iconName: "arrow.up.to.line",
                iconColor: KippleButtonAppearance.inactiveForeground
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

    private func circleFilterIcon(iconName: String, iconColor: Color) -> some View {
        Image(systemName: iconName)
            .font(MainViewMetrics.HistoryFilterIcon.defaultFont)
            .foregroundStyle(iconColor)
            .frame(width: MainViewMetrics.HistoryFilterIcon.diameter,
                   height: MainViewMetrics.HistoryFilterIcon.diameter)
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
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: MainViewMetrics.HistorySearchField.height)
        .contentShape(Rectangle())
        .onTapGesture {
            isSearchFocused = true
        }
        .background(
            RoundedRectangle(cornerRadius: KippleGlassMetrics.inputCornerRadius, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: KippleGlassMetrics.inputCornerRadius, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 0.5)
        )
    }
}
