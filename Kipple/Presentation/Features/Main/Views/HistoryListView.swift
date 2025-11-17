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
    @Binding var copyScrollRequest: HistoryCopyScrollRequest?
    @Binding var hoverResetRequest: HistoryHoverResetRequest?
    @State private var hoverResetSignal = UUID()

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
                        },
                        hoverResetSignal: hoverResetSignal
                    )
                    .frame(height: 32)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: item.isPinned)
                    .onAppear {
                        onLoadMore(item)
                    }
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
        .background(
            Color(NSColor.controlBackgroundColor).opacity(0.3)
        )
        .onChange(of: copyScrollRequest?.id) { _ in
            handleCopyScrollRequest(with: proxy)
        }
        .onChange(of: hoverResetRequest?.id) { _ in
            handleHoverResetRequest()
        }
        }
    }

    private func handleHoverResetRequest() {
        guard hoverResetRequest != nil else { return }
        hoverResetRequest = nil
        hoverResetSignal = UUID()
    }

    private func handleCopyScrollRequest(with proxy: ScrollViewProxy) {
        guard copyScrollRequest != nil else { return }
        copyScrollRequest = nil
        guard let topID = history.first?.id else { return }

        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                proxy.scrollTo(topID, anchor: .top)
            }
        }
    }
}

struct HistoryCopyScrollRequest: Identifiable, Equatable {
    let id = UUID()
}

struct HistoryHoverResetRequest: Identifiable, Equatable {
    let id = UUID()
}
