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
    @Binding var selectedCategory: ClipItemCategory?
    let onSearchTextChanged: (String) -> Void
    let onLoadMore: (ClipItem) -> Void
    let hasMoreItems: Bool
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
        selectedCategory: Binding<ClipItemCategory?>,
        initialSearchText: String,
        onSearchTextChanged: @escaping (String) -> Void,
        onLoadMore: @escaping (ClipItem) -> Void,
        hasMoreItems: Bool
    ) {
        self.history = history
        self.currentClipboardContent = currentClipboardContent
        self._selectedHistoryItem = selectedHistoryItem
        self.onSelectItem = onSelectItem
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
        self.onCategoryFilter = onCategoryFilter
        self._selectedCategory = selectedCategory
        self.onSearchTextChanged = onSearchTextChanged
        self.onLoadMore = onLoadMore
        self.hasMoreItems = hasMoreItems
        _searchText = State(initialValue: initialSearchText)
    }

    var body: some View {
        return VStack(spacing: 0) {
            // 検索バー（常に表示）
            HStack(spacing: 12) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(NSColor.textBackgroundColor))
                        .shadow(color: Color.black.opacity(0.05), radius: 3, y: 2)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.leading, 10)
                        
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                        
                        if !searchText.isEmpty {
                            Button(action: { 
                                withAnimation(.spring(response: 0.2)) {
                                    searchText = ""
                                }
                            }, label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            })
                            .buttonStyle(PlainButtonStyle())
                            .padding(.trailing, 10)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
                // 履歴リスト
                ScrollView {
                    LazyVStack(spacing: 3, pinnedViews: []) {
                        ForEach(history) { item in
                            HistoryItemView(
                                item: item,
                                isSelected: selectedHistoryItem?.id == item.id,
                                isCurrentClipboardItem: item.content == currentClipboardContent,
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
                                historyFont: Font(fontManager.historyFont)
                            )
                            .frame(height: 36) // 固定高さでパフォーマンス向上
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
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
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
}
