import SwiftUI
import AppKit

struct HistoryItemEditorAction {
    let handler: @MainActor (ClipItem) -> Void

    @MainActor func callAsFunction(_ item: ClipItem) { handler(item) }
}

extension EnvironmentValues {
    @Entry var openHistoryItemEditor = HistoryItemEditorAction { _ in }
}

struct HistoryListView: View {
    let history: [ClipItem]
    let selectedHistoryItem: ClipItem?
    let currentClipboardItemID: UUID?
    let queueBadgeProvider: (ClipItem) -> Int?
    let queueSelectionPreview: Set<UUID>
    let pasteMode: MainViewModel.PasteMode
    let historyFont: Font
    let onSelectItem: (ClipItem) -> Void
    let onDelete: ((ClipItem) -> Void)?
    let onChangeUserCategory: ((UUID, ClipCategoryChange) async throws -> Void)?
    let onOpenCategoryManager: (() -> Void)?
    let onOpenItem: ((ClipItem) -> Void)?
    let onSplitEditorIntoHistory: ((ClipItem) -> Void)?
    let onLoadMore: (ClipItem) -> Void
    let hasMoreItems: Bool
    let isLoadingMore: Bool
    @Binding var canScrollToTop: Bool
    @Binding var copyScrollRequest: HistoryCopyScrollRequest?
    @Binding var hoverResetRequest: HistoryHoverResetRequest?
    let highlightRequest: HistoryHighlightRequest?
    let onHighlightFinished: (UUID) -> Void
    var queueReorder: QueueReorderActions?
    var startupPreviews: [HistoryRowPreview] = []
    var resolveStartupItem: ((UUID) async -> ClipItem?)?
    @Environment(\.openHistoryItemEditor) private var openHistoryItemEditor
    @Environment(\.categoryPopoverChanged) private var categoryPopoverChanged
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlightedRequestID: UUID?
    @State private var highlightOpacity = 0.0
    @State private var hoverResetSignal = UUID()
    @State private var isScrollLocked = false
    @State private var tableProxy = HistoryTableProxy()
    @StateObject private var hoverCoordinator = HistoryHoverCoordinator()
    @StateObject private var actionKeyMonitor = HistoryActionKeyMonitor()
    @StateObject private var queueDrag = HistoryQueueDragController()

    private var entries: HistoryListEntries {
        startupPreviews.isEmpty ? .full(history) : .startup(startupPreviews)
    }

    private var firstEntryID: UUID? { entries.first?.id }

    var body: some View {
        HistoryTableView(
            entries: entries,
            hasMoreItems: hasMoreItems,
            showsProgress: hasMoreItems && isLoadingMore,
            proxy: tableProxy,
            canScrollToTop: $canScrollToTop,
            isScrollLocked: $isScrollLocked,
            onLoadMore: onLoadMore
        ) { entry in
            displayedRow(entry)
                .id(entry.id)
                .environmentObject(actionKeyMonitor)
                .environment(\.openHistoryItemEditor, openHistoryItemEditor)
                .environment(\.categoryPopoverChanged, categoryPopoverChanged)
        }
        .overlay {
            GeometryReader { _ in queueDragOverlay }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .clipped()
        }
        .onChange(of: copyScrollRequest?.id) { _, _ in handleCopyScrollRequest() }
        .task(id: highlightRequest?.id) {
            guard let highlightRequest else { return }
            await animateHighlight(highlightRequest)
        }
        .onChange(of: hoverResetRequest?.id) { _, _ in handleHoverResetRequest() }
        .onChange(of: isScrollLocked) { _, locked in
            if locked { hoverCoordinator.clearHover() }
        }
        .environmentObject(actionKeyMonitor)
        .onChange(of: queueDrag.itemID) { _, _ in
            hoverCoordinator.clearHover()
            hoverResetSignal = UUID()
        }
        .onDisappear { queueDrag.cancel() }
    }

    private func displayedRow(_ entry: HistoryListEntry) -> some View {
        historyRow(entry)
            .frame(height: MainViewMetrics.HistoryRows.height)
            .overlay {
                if let highlightRequest, highlightRequest.itemID == entry.id,
                   highlightRequest.id == highlightedRequestID {
                    historyHighlight.opacity(highlightOpacity)
                }
            }
            .opacity(queueDrag.itemID == entry.id ? 0 : 1)
            .background(HistoryQueueDragAnchor(controller: queueDrag, itemID: entry.id))
    }

    private func historyRow(_ entry: HistoryListEntry) -> some View {
        HistoryItemView(
            entry: entry,
            resolveStartupItem: resolveStartupItem,
            isSelected: selectedHistoryItem?.id == entry.id,
            isCurrentClipboardItem: currentClipboardItemID == entry.id,
            queueBadge: entry.fullItem.flatMap {
                HistoryQueueBadgeCalculator.queueBadgeValue(for: $0, pasteMode: pasteMode, provider: queueBadgeProvider)
            },
            isQueuePreviewed: queueSelectionPreview.contains(entry.id),
            isScrollLocked: isScrollLocked || queueDrag.itemID != nil,
            onTap: onSelectItem,
            onQueueDrag: entry.fullItem != nil ? { translation in
                queueDrag.begin(itemID: entry.id, translation: translation)
            } : nil,
            onQueueLongPress: pasteMode == .clipboard && entry.fullItem != nil ? {
                queueReorder?.startQueue(itemID: entry.id)
            } : nil,
            onDelete: onDelete != nil ? { item in
                withAnimation(.spring(response: 0.3)) { onDelete?(item) }
            } : nil,
            onChangeCategory: onChangeUserCategory != nil ? { change in
                try await onChangeUserCategory?(entry.id, change)
            } : nil,
            onOpenCategoryManager: onOpenCategoryManager,
            historyFont: historyFont,
            onOpenItem: onOpenItem,
            onSplitEditorIntoHistory: onSplitEditorIntoHistory,
            hoverResetSignal: hoverResetSignal,
            hoverCoordinator: hoverCoordinator
        )
    }

    private var queueDragOverlay: some View {
        ZStack(alignment: .topLeading) {
            HistoryQueueDragAnchor(controller: queueDrag, actions: queueReorder, visibleIDs: history.map(\.id))
            if let line = queueDrag.insertionFrame {
                Rectangle().fill(Color.accentColor)
                    .frame(width: line.width, height: line.height)
                    .position(x: line.midX, y: line.midY)
            }
            if let item = history.first(where: { $0.id == queueDrag.itemID }) {
                historyRow(.full(item))
                    .frame(width: queueDrag.previewFrame.width, height: queueDrag.previewFrame.height)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
                    .position(x: queueDrag.previewFrame.midX, y: queueDrag.previewFrame.midY)
            }
        }
    }

    private func handleCopyScrollRequest() {
        guard copyScrollRequest != nil else { return }
        copyScrollRequest = nil
        guard highlightRequest == nil else { return }
        guard let firstEntryID else {
            canScrollToTop = false
            return
        }
        DispatchQueue.main.async {
            tableProxy.scrollTo(firstEntryID)
            canScrollToTop = false
        }
    }

    private var historyHighlight: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return shape
            .fill(Color.accentColor.opacity(0.16))
            .overlay { shape.strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @MainActor
    private func animateHighlight(_ request: HistoryHighlightRequest) async {
        await Task.yield()
        guard !Task.isCancelled else { return }
        tableProxy.scrollTo(request.itemID)
        withTransaction(Transaction(animation: nil)) {
            highlightedRequestID = request.id
            highlightOpacity = 1
        }

        do {
            try await Task.sleep(for: .milliseconds(reduceMotion ? 800 : 230))
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.65)) { highlightOpacity = 0 }
                try await Task.sleep(for: .milliseconds(650))
            }
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        highlightedRequestID = nil
        onHighlightFinished(request.id)
    }

    private func handleHoverResetRequest() {
        guard hoverResetRequest != nil else { return }
        hoverResetRequest = nil
        hoverResetSignal = UUID()
    }
}

enum HistoryListEntries: RandomAccessCollection {
    case full([ClipItem])
    case startup([HistoryRowPreview])

    var startIndex: Int { 0 }

    var endIndex: Int {
        switch self {
        case let .full(items): items.count
        case let .startup(previews): previews.count
        }
    }

    subscript(index: Int) -> HistoryListEntry {
        switch self {
        case let .full(items): .full(items[index])
        case let .startup(previews): .startup(previews[index])
        }
    }
}

struct HistoryCopyScrollRequest: Identifiable, Equatable {
    let id = UUID()
}

struct HistoryHighlightRequest: Identifiable, Equatable {
    let id = UUID()
    let itemID: UUID
}

struct HistoryHoverResetRequest: Identifiable, Equatable {
    let id = UUID()
}

final class HistoryHoverCoordinator: ObservableObject {
    @Published private(set) var hoveredItemID: UUID?

    func setHovered(itemID: UUID) {
        if hoveredItemID != itemID {
            hoveredItemID = itemID
        }
    }

    func clearHover(ifMatches id: UUID? = nil) {
        guard let current = hoveredItemID else { return }
        if let id, current != id {
            return
        }
        hoveredItemID = nil
    }
}

enum HistoryQueueBadgeCalculator {
    static func queueBadgeValue(
        for item: ClipItem,
        pasteMode: MainViewModel.PasteMode,
        provider: (ClipItem) -> Int?
    ) -> Int? {
        guard pasteMode != .clipboard else {
            return nil
        }
        return provider(item) ?? 0
    }
}

extension HistoryListView {
    static func isCurrentClipboardItem(_ item: ClipItem, currentID: UUID?) -> Bool {
        guard let currentID else { return false }
        return item.id == currentID
    }
}
