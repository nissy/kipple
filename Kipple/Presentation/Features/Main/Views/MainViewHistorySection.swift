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
    let queueEnabled: Bool
    let pasteMode: MainViewModel.PasteMode
    let onToggleQueueMode: () -> Void
    let onToggleQueueRepetition: () -> Void
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
        queueEnabled: Bool,
        pasteMode: MainViewModel.PasteMode,
        onToggleQueueMode: @escaping () -> Void,
        onToggleQueueRepetition: @escaping () -> Void,
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
        self.queueEnabled = queueEnabled
        self.pasteMode = pasteMode
        self.onToggleQueueMode = onToggleQueueMode
        self.onToggleQueueRepetition = onToggleQueueRepetition
        self.queueBadgeProvider = queueBadgeProvider
        self.queueSelectionPreview = queueSelectionPreview
        _searchText = State(initialValue: initialSearchText)
    }

    var body: some View {
        return VStack(spacing: 0) {
            // 検索バー（常に表示）
            HStack(spacing: 10) {
                queueControls
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
                .frame(height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(NSColor.separatorColor).opacity(0.35), lineWidth: 1)
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
                // 履歴リスト
                ScrollView {
                    LazyVStack(spacing: 2, pinnedViews: []) {
                        ForEach(history) { item in
                            HistoryItemView(
                                item: item,
                                isSelected: selectedHistoryItem?.id == item.id,
                                isCurrentClipboardItem: item.content == currentClipboardContent,
                                queueBadge: queueBadgeProvider(item),
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

    @ViewBuilder
    private var queueControls: some View {
        HStack(spacing: 4) {
            queueModeButton
            if pasteMode != .clipboard {
                queueLoopButton
            }
        }
    }

    private var queueModeButton: some View {
        let isActive = pasteMode != .clipboard
        return Button {
            guard queueEnabled else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                onToggleQueueMode()
            }
        } label: {
            VStack(spacing: 1) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.1))
                        .frame(width: 24, height: 24)
                        .shadow(color: isActive ? Color.accentColor.opacity(0.3) : .clear,
                                radius: 3,
                                y: 2)

                    Image(systemName: "list.number")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isActive ? .white : .secondary)
                }

                Text("Queue")
                    .font(.system(size: 7.5))
                    .foregroundColor(isActive ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 34)
            .opacity(queueEnabled ? 1.0 : 0.4)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!queueEnabled)
    }

    private var queueLoopButton: some View {
        let isLooping = pasteMode == .queueToggle
        return Button {
            guard queueEnabled else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                onToggleQueueRepetition()
            }
        } label: {
            VStack(spacing: 1) {
                ZStack {
                    Circle()
                        .fill(isLooping ? Color.accentColor : Color.secondary.opacity(0.1))
                        .frame(width: 24, height: 24)
                        .shadow(color: isLooping ? Color.accentColor.opacity(0.3) : .clear,
                                radius: 3,
                                y: 2)

                    Image(systemName: isLooping ? "repeat.circle.fill" : "repeat")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isLooping ? .white : .secondary)
                }

                Text("Loop")
                    .font(.system(size: 7.5))
                    .foregroundColor(isLooping ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 34)
            .opacity(queueEnabled ? 1.0 : 0.4)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!queueEnabled)
    }
}
