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
    let onCategoryFilter: ((ClipItemCategory) -> Void)?
    // 追加: ユーザカテゴリ変更/管理
    let onChangeUserCategory: ((ClipItem, UUID?) -> Void)?
    let onOpenCategoryManager: (() -> Void)?
    @Binding var selectedCategory: ClipItemCategory?
    @Binding var searchText: String
    let onLoadMore: (ClipItem) -> Void
    let hasMoreItems: Bool
    let isLoadingMore: Bool
    let isPinnedFilterActive: Bool
    let onTogglePinnedFilter: () -> Void
    let availableCategories: [ClipItemCategory]
    let customCategories: [UserCategory]
    let selectedUserCategoryId: UUID?
    let onToggleUserCategoryFilter: (UUID) -> Void
    let pasteMode: MainViewModel.PasteMode
    let queueBadgeProvider: (ClipItem) -> Int?
    let queueSelectionPreview: Set<UUID>
    let isQueueLoopActive: Bool
    let canToggleQueueLoop: Bool
    let onToggleQueueLoop: () -> Void
    @ObservedObject private var fontManager = FontManager.shared
    @State private var isCategoryFilterHovered = false

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
        onCategoryFilter: ((ClipItemCategory) -> Void)?,
        onChangeUserCategory: ((ClipItem, UUID?) -> Void)? = nil,
        onOpenCategoryManager: (() -> Void)? = nil,
        selectedCategory: Binding<ClipItemCategory?>,
        searchText: Binding<String>,
        onLoadMore: @escaping (ClipItem) -> Void,
        hasMoreItems: Bool,
        isLoadingMore: Bool,
        isPinnedFilterActive: Bool,
        onTogglePinnedFilter: @escaping () -> Void,
        availableCategories: [ClipItemCategory],
        customCategories: [UserCategory],
        selectedUserCategoryId: UUID?,
        onToggleUserCategoryFilter: @escaping (UUID) -> Void,
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
        self.onCategoryFilter = onCategoryFilter
        self.onChangeUserCategory = onChangeUserCategory
        self.onOpenCategoryManager = onOpenCategoryManager
        self._selectedCategory = selectedCategory
        self._searchText = searchText
        self.onLoadMore = onLoadMore
        self.hasMoreItems = hasMoreItems
        self.isLoadingMore = isLoadingMore
        self.isPinnedFilterActive = isPinnedFilterActive
        self.onTogglePinnedFilter = onTogglePinnedFilter
        self.availableCategories = availableCategories
        self.customCategories = customCategories
        self.selectedUserCategoryId = selectedUserCategoryId
        self.onToggleUserCategoryFilter = onToggleUserCategoryFilter
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
                copyScrollRequest: $copyScrollRequest,
                hoverResetRequest: $hoverResetRequest
            )
        }
        .padding(.horizontal, MainViewMetrics.HistoryColumns.sectionHorizontalPadding)
        .padding(.vertical, 6)
        .kippleGlassPanel(
            cornerRadius: 20,
            fillOpacity: 0.30,
            strokeOpacity: 0,
            highlightOpacity: 0.05
        )
    }

    @ViewBuilder
    private var historyToolbar: some View {
        historyToolbarContent
    }

    private var historyToolbarContent: some View {
        HStack(spacing: MainViewMetrics.HistoryColumns.spacing) {
            if pasteMode != .clipboard {
                queueLoopControl
            }
            pinnedFilterButton
            categoryFilterControl
            searchField
        }
        .padding(.horizontal, MainViewMetrics.HistoryColumns.horizontalInset)
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

    @ViewBuilder
    private var categoryFilterControl: some View {
        let isActive = selectedCategory != nil || selectedUserCategoryId != nil
        if isActive {
            let iconName: String = {
                if let category = selectedCategory {
                    return category.icon
                }
                if let selectedUserCategoryId,
                   let custom = customCategories.first(where: { $0.id == selectedUserCategoryId }) {
                    return custom.iconSystemName
                }
                return noneCategoryIconName
            }()

            Button {
                if let category = selectedCategory {
                    onCategoryFilter?(category)
                } else if let userCategoryId = selectedUserCategoryId {
                    onToggleUserCategoryFilter(userCategoryId)
                } else {
                    onCategoryFilter?(.all)
                }
            } label: {
                circleFilterIcon(
                    iconName: iconName,
                    iconColor: toolbarFilterIconForeground(isActive: true),
                    iconFont: MainViewMetrics.HistoryFilterIcon.categoryFont,
                    isActive: true
                )
            }
            .buttonStyle(PlainButtonStyle())
            .frame(
                width: MainViewMetrics.HistoryFilterIcon.diameter,
                height: MainViewMetrics.HistoryFilterIcon.diameter
            )
            .background(toolbarFilterAffordance(isActive: true, isHovered: isCategoryFilterHovered))
            .contentShape(Circle())
            .onHover { hovering in
                isCategoryFilterHovered = hovering
            }
            .help(Text(verbatim: currentCategoryFilterLabel))
        } else {
            Menu {
                if let onCategoryFilter {
                    ForEach(availableCategories, id: \.self) { category in
                        Button {
                            onCategoryFilter(category)
                        } label: {
                            filterMenuItemLabel(
                                category.localizedName,
                            selected: false,
                            systemImage: category.icon
                            )
                        }
                    }
                }

                if !customCategories.isEmpty {
                    if onCategoryFilter != nil {
                        Divider()
                    }
                    ForEach(customCategories) { category in
                        Button {
                            onToggleUserCategoryFilter(category.id)
                        } label: {
                            filterMenuItemLabel(
                                category.name,
                                selected: false,
                                systemImage: category.iconSystemName
                            )
                        }
                    }
                }
            } label: {
                circleFilterIcon(
                    iconName: noneCategoryIconName,
                    iconColor: KippleButtonAppearance.inactiveForeground,
                    iconFont: MainViewMetrics.HistoryFilterIcon.categoryFont,
                    isActive: false
                )
            }
            .menuIndicator(.hidden)
            .buttonStyle(PlainButtonStyle())
            .frame(
                width: MainViewMetrics.HistoryFilterIcon.diameter,
                height: MainViewMetrics.HistoryFilterIcon.diameter
            )
            .background(toolbarFilterAffordance(isActive: false, isHovered: isCategoryFilterHovered))
            .contentShape(Circle())
            .onHover { hovering in
                isCategoryFilterHovered = hovering
            }
            .help(Text(verbatim: noneCategoryDisplayName))
        }
    }

    private var currentCategoryFilterLabel: String {
        if let category = selectedCategory {
            return category.localizedName
        }
        if let selectedUserCategoryId,
           let custom = customCategories.first(where: { $0.id == selectedUserCategoryId }) {
            return custom.name
        }
        return noneCategoryDisplayName
    }

    private func filterMenuItemLabel(
        _ text: String,
        selected: Bool,
        systemImage: String? = nil
    ) -> some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(MainViewMetrics.HistoryFilterMenu.iconFont)
                    .foregroundColor(KippleButtonAppearance.inactiveForeground)
            }
            Text(verbatim: text)
                .font(MainViewMetrics.HistoryFilterMenu.labelFont)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(MainViewMetrics.HistoryFilterMenu.checkmarkFont)
            }
        }
        .padding(.vertical, 2)
    }

    private var noneCategoryIconName: String {
        UserCategoryStore.shared.noneCategory().iconSystemName
    }

    private var noneCategoryDisplayName: String {
        "None"
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
        ZStack(alignment: .leading) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(MainViewMetrics.HistorySearchField.iconFont)
                    .foregroundColor(KippleButtonAppearance.inactiveForeground)
                    .padding(.leading, 8)

                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Font(fontManager.historyFont))
                    .foregroundColor(MainViewMetrics.TextColor.primary)

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
        }
        .frame(maxWidth: .infinity)
        .frame(height: MainViewMetrics.HistorySearchField.height)
        .background(
            RoundedRectangle(cornerRadius: MainViewMetrics.HistorySearchField.height / 2, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MainViewMetrics.HistorySearchField.height / 2, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 0.5)
        )
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
