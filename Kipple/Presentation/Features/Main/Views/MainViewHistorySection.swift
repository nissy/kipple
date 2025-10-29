//
//  MainViewHistorySection.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI
import Combine

struct MainViewHistorySection: View {
    let history: [ClipItem]
    let currentClipboardContent: String?
    @Binding var selectedHistoryItem: ClipItem?
    let onSelectItem: (ClipItem) -> Void
    let onTogglePin: (ClipItem) -> Void
    let onDelete: ((ClipItem) -> Void)?
    let onCategoryFilter: ((ClipItemCategory) -> Void)?
    // 追加: ユーザカテゴリ変更/管理
    let onChangeUserCategory: ((ClipItem, UUID?) -> Void)?
    let onOpenCategoryManager: (() -> Void)?
    @Binding var selectedCategory: ClipItemCategory?
    let onSearchTextChanged: (String) -> Void
    let onLoadMore: (ClipItem) -> Void
    let hasMoreItems: Bool
    let isPinnedFilterActive: Bool
    let onTogglePinnedFilter: () -> Void
    let availableCategories: [ClipItemCategory]
    let customCategories: [UserCategory]
    let selectedUserCategoryId: UUID?
    let onToggleUserCategoryFilter: (UUID) -> Void
    let pasteMode: MainViewModel.PasteMode
    let queueBadgeProvider: (ClipItem) -> Int?
    let queueSelectionPreview: Set<UUID>
    @ObservedObject private var fontManager = FontManager.shared

    @State private var searchText: String
    @State private var searchCancellable: AnyCancellable?

    init(
        history: [ClipItem],
        currentClipboardContent: String?,
        selectedHistoryItem: Binding<ClipItem?>,
        onSelectItem: @escaping (ClipItem) -> Void,
        onTogglePin: @escaping (ClipItem) -> Void,
        onDelete: ((ClipItem) -> Void)?,
        onCategoryFilter: ((ClipItemCategory) -> Void)?,
        onChangeUserCategory: ((ClipItem, UUID?) -> Void)? = nil,
        onOpenCategoryManager: (() -> Void)? = nil,
        selectedCategory: Binding<ClipItemCategory?>,
        initialSearchText: String,
        onSearchTextChanged: @escaping (String) -> Void,
        onLoadMore: @escaping (ClipItem) -> Void,
        hasMoreItems: Bool,
        isPinnedFilterActive: Bool,
        onTogglePinnedFilter: @escaping () -> Void,
        availableCategories: [ClipItemCategory],
        customCategories: [UserCategory],
        selectedUserCategoryId: UUID?,
        onToggleUserCategoryFilter: @escaping (UUID) -> Void,
        pasteMode: MainViewModel.PasteMode,
        queueBadgeProvider: @escaping (ClipItem) -> Int?,
        queueSelectionPreview: Set<UUID>
    ) {
        self.history = history
        self.currentClipboardContent = currentClipboardContent
        self._selectedHistoryItem = selectedHistoryItem
        self.onSelectItem = onSelectItem
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
        self.onCategoryFilter = onCategoryFilter
        self.onChangeUserCategory = onChangeUserCategory
        self.onOpenCategoryManager = onOpenCategoryManager
        self._selectedCategory = selectedCategory
        self.onSearchTextChanged = onSearchTextChanged
        self.onLoadMore = onLoadMore
        self.hasMoreItems = hasMoreItems
        self.isPinnedFilterActive = isPinnedFilterActive
        self.onTogglePinnedFilter = onTogglePinnedFilter
        self.availableCategories = availableCategories
        self.customCategories = customCategories
        self.selectedUserCategoryId = selectedUserCategoryId
        self.onToggleUserCategoryFilter = onToggleUserCategoryFilter
        self.pasteMode = pasteMode
        self.queueBadgeProvider = queueBadgeProvider
        self.queueSelectionPreview = queueSelectionPreview
        _searchText = State(initialValue: initialSearchText)
    }

    var body: some View {
        return VStack(spacing: 0) {
            // 検索バー（常に表示）
            HStack(spacing: 8) {
                if pasteMode != .clipboard {
                    queueColumnPlaceholder
                }
                pinnedFilterButton
                categoryFilterControl
                searchField
            }
            .padding(.horizontal, 8)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
                // 履歴リスト
                ScrollView {
                    LazyVStack(spacing: 2, pinnedViews: []) {
                        ForEach(history) { item in
                            let queueBadgeValue: Int? = {
                                if let badge = queueBadgeProvider(item) {
                                    return badge
                                }
                                if pasteMode != .clipboard {
                                    return 0
                                }
                                return nil
                            }()

                            HistoryItemView(
                                item: item,
                                isSelected: selectedHistoryItem?.id == item.id,
                                isCurrentClipboardItem: item.content == currentClipboardContent,
                                queueBadge: queueBadgeValue,
                                isQueuePreviewed: queueSelectionPreview.contains(item.id),
                                onTap: {
                                    withAnimation(.spring(response: 0.3)) {
                                        onSelectItem(item)
                                    }
                                },
                                onTogglePin: {
                                    onTogglePin(item)
                                },
                                onDelete: onDelete != nil ? {
                                    withAnimation(.spring(response: 0.3)) {
                                        onDelete?(item)
                                    }
                                } : nil,
                                onCategoryTap: nil, // カテゴリタップは無効化
                                onChangeCategory: onChangeUserCategory != nil ? { catId in
                                    onChangeUserCategory?(item, catId)
                                } : nil,
                                onOpenCategoryManager: onOpenCategoryManager,
                                historyFont: Font(fontManager.historyFont)
                            )
                            .frame(height: 32) // 固定高さでパフォーマンス向上
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: item.isPinned)
                            .onAppear {
                                onLoadMore(item)
                            }
                        }
                        if hasMoreItems {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(
                    Color(NSColor.controlBackgroundColor).opacity(0.3)
                )
        }
        .onChange(of: searchText) { newValue in
            // 検索テキストの変更をデバウンス（パフォーマンス最適化）
            searchCancellable?.cancel()
            searchCancellable = Just(newValue)
                .delay(for: .milliseconds(300), scheduler: RunLoop.main)
                .sink { value in
                    onSearchTextChanged(value)
                }
        }
        .onAppear {
            onSearchTextChanged(searchText)
        }
    }

    private var pinnedFilterButton: some View {
        Button {
            onTogglePinnedFilter()
        } label: {
            circleFilterIcon(
                background: isPinnedFilterActive ? Color.accentColor : Color.secondary.opacity(0.1),
                iconName: isPinnedFilterActive ? "pin.fill" : "pin",
                iconColor: isPinnedFilterActive ? .white : .secondary,
                iconSize: 10,
                rotation: isPinnedFilterActive ? 0 : -45
            )
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 22, height: 22)
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
                    background: Color.accentColor,
                    iconName: iconName,
                    iconColor: .white,
                    iconSize: 13
                )
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: 22, height: 22)
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
                    background: Color.secondary.opacity(0.1),
                    iconName: noneCategoryIconName,
                    iconColor: .secondary,
                    iconSize: 13
                )
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .menuIndicator(.hidden)
            .frame(width: 22, height: 22)
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
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }
            Text(verbatim: text)
                .font(.system(size: 12))
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
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

    private var queueColumnPlaceholder: some View {
        Color.clear
            .frame(width: 22, height: 22)
    }

    private var searchField: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)

                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Font(fontManager.historyFont))
                    .foregroundColor(.primary)

                if !searchText.isEmpty {
                    Button(action: {
                        withAnimation(.spring(response: 0.2)) {
                            searchText = ""
                        }
                    }, label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    })
                    .buttonStyle(PlainButtonStyle())
                    .padding(.trailing, 8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.35), lineWidth: 1)
        )
    }

    private func circleFilterIcon(
        background: Color,
        iconName: String,
        iconColor: Color,
        iconSize: CGFloat = 12,
        rotation: Double = 0
    ) -> some View {
        ZStack {
            Circle()
                .fill(background)
                .frame(width: 22, height: 22)

            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(iconColor)
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: 22, height: 22)
        .contentShape(Circle())
    }
}
