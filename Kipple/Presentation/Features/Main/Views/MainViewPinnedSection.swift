//
//  MainViewPinnedSection.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI
import Combine

struct MainViewPinnedSection: View {
    let pinnedItems: [ClipItem]
    let onSelectItem: (ClipItem) -> Void
    let onTogglePin: (ClipItem) -> Void
    let onDelete: ((ClipItem) -> Void)?
    let onReorderPins: (([ClipItem]) -> Void)?
    let onCategoryFilter: ((ClipItemCategory) -> Void)?
    @Binding var selectedItem: ClipItem?
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchCancellable: AnyCancellable?
    
    var body: some View {
        let filteredPinnedItems = debouncedSearchText.isEmpty ? pinnedItems : 
            pinnedItems.filter { $0.content.localizedCaseInsensitiveContains(debouncedSearchText) }
        
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Icon with gradient background
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.orange, Color.orange.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 28, height: 28)
                        .shadow(color: Color.orange.opacity(0.3), radius: 3, y: 2)
                    
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text("Pinned Items")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Pinned count badge
                if !pinnedItems.isEmpty {
                    Text("\(pinnedItems.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.8))
                        )
                        .transition(.scale.combined(with: .opacity))
                }
                
                Button(action: { 
                    withAnimation(.spring()) { 
                        isSearching.toggle() 
                    } 
                }, label: {
                    ZStack {
                        Circle()
                            .fill(isSearching ? 
                                Color.accentColor : 
                                Color(NSColor.controlBackgroundColor))
                            .frame(width: 28, height: 28)
                            .shadow(
                                color: isSearching ? 
                                    Color.accentColor.opacity(0.3) : 
                                    Color.black.opacity(0.05),
                                radius: 3,
                                y: 1
                            )
                        
                        Image(systemName: isSearching ? "magnifyingglass.circle.fill" : "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isSearching ? .white : .secondary)
                    }
                })
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(isSearching ? 1.1 : 1.0)
                .animation(.spring(response: 0.3), value: isSearching)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [
                        Color(NSColor.windowBackgroundColor).opacity(0.95),
                        Color(NSColor.windowBackgroundColor).opacity(0.8)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            // 検索バー
            if isSearching {
                HStack(spacing: 12) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(NSColor.textBackgroundColor))
                            .shadow(color: Color.black.opacity(0.05), radius: 3, y: 2)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.accentColor)
                                .padding(.leading, 10)
                            
                            TextField("Search pinned items...", text: $searchText)
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
                    .frame(height: 36)
                    
                    Button(action: { 
                        withAnimation(.spring(response: 0.3)) {
                            isSearching = false
                            searchText = ""
                        }
                    }, label: {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accentColor)
                    })
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
            
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(filteredPinnedItems) { item in
                        HistoryItemView(
                            item: item,
                            isSelected: selectedItem?.id == item.id,
                            onTap: {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedItem = item
                                    onSelectItem(item)
                                }
                            },
                            onTogglePin: {
                                withAnimation(.spring(response: 0.4)) {
                                    onTogglePin(item)
                                }
                            },
                            onDelete: onDelete != nil ? {
                                withAnimation(.spring(response: 0.3)) {
                                    onDelete?(item)
                                }
                            } : nil,
                            onCategoryTap: nil // カテゴリタップは無効化
                        )
                        .onDrag {
                            NSItemProvider(object: item.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: PinnedItemDropDelegate(
                            item: item,
                            items: pinnedItems,  // Use original items for reordering
                            onReorderPins: onReorderPins
                        ))
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
                    debouncedSearchText = value
                }
        }
    }
}

// MARK: - PinnedItemDropDelegate for handling reordering
struct PinnedItemDropDelegate: DropDelegate {
    let item: ClipItem
    let items: [ClipItem]
    let onReorderPins: (([ClipItem]) -> Void)?
    
    func performDrop(info: DropInfo) -> Bool {
        guard let onReorderPins = onReorderPins else { return false }
        
        // Get the dragged item ID from the drop info
        guard let draggedItemProvider = info.itemProviders(for: [.text]).first else { return false }
        
        draggedItemProvider.loadObject(ofClass: NSString.self) { draggedItemIdString, _ in
            DispatchQueue.main.async {
                guard let draggedItemIdString = draggedItemIdString as? String,
                      let draggedItemId = UUID(uuidString: draggedItemIdString),
                      let draggedItemIndex = items.firstIndex(where: { $0.id == draggedItemId }),
                      let targetIndex = items.firstIndex(where: { $0.id == item.id }) else {
                    return
                }
                
                // Create new array with reordered items
                var newItems = items
                let draggedItem = newItems.remove(at: draggedItemIndex)
                newItems.insert(draggedItem, at: targetIndex)
                
                // Call the reorder callback
                onReorderPins(newItems)
            }
        }
        
        return true
    }
    
    func dropEntered(info: DropInfo) {
        // Visual feedback when drag enters
    }
    
    func dropExited(info: DropInfo) {
        // Clean up visual feedback when drag exits
    }
}
