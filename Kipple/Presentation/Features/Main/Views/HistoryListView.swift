import SwiftUI

struct HistoryListView: View {
    let history: [ClipItem]
    let selectedHistoryItem: ClipItem?
    let currentClipboardContent: String?
    let queueBadgeProvider: (ClipItem) -> Int?
    let queueSelectionPreview: Set<UUID>
    let pasteMode: MainViewModel.PasteMode
    let historyFont: Font
    let onSelectItem: (ClipItem) -> Void
    let onTogglePin: (ClipItem) -> Void
    let onDelete: ((ClipItem) -> Void)?
    let onChangeUserCategory: ((ClipItem, UUID?) -> Void)?
    let onOpenCategoryManager: (() -> Void)?
    let onOpenItem: ((ClipItem) -> Void)?
    let onInsertToEditor: ((ClipItem) -> Void)?
    let onLoadMore: (ClipItem) -> Void
    let hasMoreItems: Bool
    let isLoadingMore: Bool
    @State private var lastHistoryIDs: [UUID] = []
    @State private var scrollAnchorID: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2, pinnedViews: []) {
                    ForEach(history, id: \.id) { item in
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
                        onCategoryTap: nil,
                        onChangeCategory: onChangeUserCategory != nil ? { catId in
                            onChangeUserCategory?(item, catId)
                        } : nil,
                        onOpenCategoryManager: onOpenCategoryManager,
                        historyFont: historyFont,
                        onOpenItem: onOpenItem.map { handler in
                            { handler(item) }
                        },
                        onInsertToEditor: onInsertToEditor.map { handler in
                            { handler(item) }
                        }
                    )
                    .frame(height: 32)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: item.isPinned)
                    .onAppear {
                        onLoadMore(item)
                    }
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: HistoryVisibleRowPreference.self,
                                value: [
                                    HistoryVisibleRow(
                                        id: item.id,
                                        distanceToTop: geometry.frame(in: .named("HistoryListScroll")).minY
                                    )
                                ]
                            )
                        }
                    )
                    }
                    if hasMoreItems && isLoadingMore {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        .coordinateSpace(name: "HistoryListScroll")
        .background(
            Color(NSColor.controlBackgroundColor).opacity(0.3)
        )
        .onPreferenceChange(HistoryVisibleRowPreference.self) { rows in
            guard let nearest = rows.min(by: { abs($0.distanceToTop) < abs($1.distanceToTop) }) else { return }
            scrollAnchorID = nearest.id
        }
        .onChange(of: history.map(\.id)) { newIDs in
            guard lastHistoryIDs != newIDs else { return }
            lastHistoryIDs = newIDs
            guard let anchor = scrollAnchorID, newIDs.contains(anchor) else { return }
            DispatchQueue.main.async {
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
        .onAppear {
            lastHistoryIDs = history.map(\.id)
        }
        }
    }
}

private struct HistoryVisibleRow: Equatable {
    let id: UUID
    let distanceToTop: CGFloat
}

private struct HistoryVisibleRowPreference: PreferenceKey {
    static var defaultValue: [HistoryVisibleRow] { [] }

    static func reduce(value: inout [HistoryVisibleRow], nextValue: () -> [HistoryVisibleRow]) {
        value.append(contentsOf: nextValue())
    }
}
