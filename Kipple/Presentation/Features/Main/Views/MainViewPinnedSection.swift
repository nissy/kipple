//
//  MainViewPinnedSection.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI

struct MainViewPinnedSection: View {
    let pinnedItems: [ClipItem]
    let currentClipboardContent: String?
    let onSelectItem: (ClipItem) -> Void
    let onTogglePin: (ClipItem) -> Void
    let onDelete: ((ClipItem) -> Void)?
    let onReorderPins: (([ClipItem]) -> Void)?
    let onCategoryFilter: ((ClipItemCategory) -> Void)?
    @Binding var selectedItem: ClipItem?
    @Binding var selectedCategory: ClipItemCategory?
    @ObservedObject private var fontManager = FontManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
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
                
                // カテゴリフィルターが選択されている場合、アイコンを表示
                if let category = selectedCategory {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Image(systemName: category.icon)
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.1))
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            onCategoryFilter?(category)
                        }
                    }
                }
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
            
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(pinnedItems) { item in
                        HistoryItemView(
                            item: item,
                            isSelected: false,  // ピンアイテムは選択状態を表示しない
                            isCurrentClipboardItem: item.content == currentClipboardContent,
                            onTap: {
                                withAnimation(.spring(response: 0.3)) {
                                    // selectedItemは設定しない（背景を青くしない）
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
                            onCategoryTap: onCategoryFilter != nil ? { 
                                onCategoryFilter?(item.category)
                            } : nil,
                            historyFont: Font(fontManager.historyFont)
                        )
                        .frame(height: 44) // 固定高さでパフォーマンス向上
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
