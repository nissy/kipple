import SwiftUI
import AppKit

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
    let onChangeUserCategory: ((ClipItem, ClipCategoryChange) async throws -> Void)?
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlightedRequestID: UUID?
    @State private var highlightOpacity = 0.0
    @State private var hoverResetSignal = UUID()
    @State private var isScrollLocked = false
    @StateObject private var hoverCoordinator = HistoryHoverCoordinator()
    @StateObject private var actionKeyMonitor = HistoryActionKeyMonitor()
    @StateObject private var queueDrag = HistoryQueueDragController()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: MainViewMetrics.HistoryRows.spacing) {
                    ForEach(history, id: \.id) { item in
                        historyRow(item)
                        .frame(height: MainViewMetrics.HistoryRows.height)
                        .overlay {
                            if let highlightRequest, highlightRequest.itemID == item.id,
                               highlightRequest.id == highlightedRequestID {
                                historyHighlight.opacity(highlightOpacity)
                            }
                        }
                        .opacity(queueDrag.itemID == item.id ? 0 : 1)
                        .background(HistoryQueueDragAnchor(controller: queueDrag, itemID: item.id))
                        .transition(.opacity)
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
                .padding(.vertical, MainViewMetrics.HistoryRows.verticalPadding)
                .background {
                    ScrollPositionObserver(
                        canScrollToTop: $canScrollToTop,
                        isScrollLocked: $isScrollLocked
                    )
                    .allowsHitTesting(false)
                }
            }
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .overlay {
                GeometryReader { _ in queueDragOverlay }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .clipped()
            }
            .onChange(of: copyScrollRequest?.id) { _, _ in
                handleCopyScrollRequest(with: proxy)
            }
            .task(id: highlightRequest?.id) {
                guard let highlightRequest else { return }
                await animateHighlight(highlightRequest, with: proxy)
            }
            .onChange(of: hoverResetRequest?.id) { _, _ in
                handleHoverResetRequest()
            }
            .onChange(of: history.first?.id) { _, _ in
                canScrollToTop = false
            }
            .onChange(of: isScrollLocked) { _, locked in
                if locked {
                    hoverCoordinator.clearHover()
                }
            }
        }
        .environmentObject(actionKeyMonitor)
        .onChange(of: queueDrag.itemID) { _, _ in
            hoverCoordinator.clearHover()
            hoverResetSignal = UUID()
        }
        .onDisappear { queueDrag.cancel() }
    }

    private func historyRow(_ item: ClipItem) -> some View {
        HistoryItemView(
            item: item,
            isSelected: selectedHistoryItem?.id == item.id,
            isCurrentClipboardItem: Self.isCurrentClipboardItem(item, currentID: currentClipboardItemID),
            queueBadge: HistoryQueueBadgeCalculator.queueBadgeValue(
                for: item, pasteMode: pasteMode, provider: queueBadgeProvider
            ),
            isQueuePreviewed: queueSelectionPreview.contains(item.id),
            isScrollLocked: isScrollLocked || queueDrag.itemID != nil,
            onTap: { onSelectItem(item) },
            onQueueDrag: { translation in
                queueDrag.begin(itemID: item.id, translation: translation)
            },
            onQueueLongPress: pasteMode == .clipboard ? {
                queueReorder?.startQueue(itemID: item.id)
            } : nil,
            onDelete: onDelete != nil ? {
                withAnimation(.spring(response: 0.3)) { onDelete?(item) }
            } : nil,
            onChangeCategory: onChangeUserCategory != nil ? { change in
                try await onChangeUserCategory?(item, change)
            } : nil,
            onOpenCategoryManager: onOpenCategoryManager,
            historyFont: historyFont,
            onOpenItem: onOpenItem.map { handler in { handler(item) } },
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
                historyRow(item)
                    .frame(width: queueDrag.previewFrame.width, height: queueDrag.previewFrame.height)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
                    .position(x: queueDrag.previewFrame.midX, y: queueDrag.previewFrame.midY)
            }
        }
    }

    private func handleCopyScrollRequest(with proxy: ScrollViewProxy) {
        guard copyScrollRequest != nil else { return }
        copyScrollRequest = nil
        guard highlightRequest == nil else { return }
        scrollToTop(with: proxy, animated: false)
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
    private func animateHighlight(_ request: HistoryHighlightRequest, with proxy: ScrollViewProxy) async {
        await Task.yield()
        guard !Task.isCancelled else { return }
        proxy.scrollTo(request.itemID, anchor: .top)
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

    private func scrollToTop(with proxy: ScrollViewProxy, animated: Bool) {
        guard let topID = history.first?.id else {
            canScrollToTop = false
            return
        }

        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(topID, anchor: .top)
                }
            } else {
                proxy.scrollTo(topID, anchor: .top)
            }
            canScrollToTop = false
        }
    }

    private func handleHoverResetRequest() {
        guard hoverResetRequest != nil else { return }
        hoverResetRequest = nil
        hoverResetSignal = UUID()
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

private struct ScrollPositionObserver: NSViewRepresentable {
    @Binding var canScrollToTop: Bool
    @Binding var isScrollLocked: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(canScrollToTop: $canScrollToTop, isScrollLocked: $isScrollLocked)
    }

    func makeNSView(context: Context) -> ScrollPositionObserverView {
        let view = ScrollPositionObserverView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ScrollPositionObserverView, context: Context) {
        nsView.coordinator = context.coordinator
        nsView.attachIfNeeded()
    }

    final class Coordinator {
        private var canScrollToTop: Binding<Bool>
        private var isScrollLocked: Binding<Bool>

        init(canScrollToTop: Binding<Bool>, isScrollLocked: Binding<Bool>) {
            self.canScrollToTop = canScrollToTop
            self.isScrollLocked = isScrollLocked
        }

        func setCanScrollToTop(_ canScroll: Bool) {
            if canScrollToTop.wrappedValue != canScroll {
                canScrollToTop.wrappedValue = canScroll
            }
        }

        func setLocked(_ locked: Bool) {
            if isScrollLocked.wrappedValue != locked {
                isScrollLocked.wrappedValue = locked
            }
        }
    }
}

private final class ScrollPositionObserverView: NSView {
    weak var coordinator: ScrollPositionObserver.Coordinator?
    private var observers: [NSObjectProtocol] = []
    private weak var observedScrollView: NSScrollView?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        attachIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfNeeded()
    }

    func attachIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let target = self.findEnclosingScrollView()
            if self.observedScrollView === target {
                self.updateScrollState()
                return
            }
            self.detachObservers()
            guard let scrollView = target else { return }
            self.observedScrollView = scrollView
            self.attachObservers(to: scrollView)
            self.updateScrollState()
        }
    }

    private func findEnclosingScrollView() -> NSScrollView? {
        var current: NSView? = self
        while let view = current {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }

    private func attachObservers(to scrollView: NSScrollView) {
        scrollView.contentView.postsBoundsChangedNotifications = true

        let center = NotificationCenter.default
        let bounds = center.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateScrollState()
            }
        }
        let will = center.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.coordinator?.setLocked(true)
                HistoryPopoverManager.shared.scheduleHide()
                self?.updateScrollState()
            }
        }
        let did = center.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.coordinator?.setLocked(false)
                self?.updateScrollState()
            }
        }
        observers = [bounds, will, did]
    }

    private func updateScrollState() {
        guard let scrollView = observedScrollView else {
            coordinator?.setCanScrollToTop(false)
            return
        }

        let visibleBounds = scrollView.contentView.bounds
        let documentBounds = scrollView.documentView?.bounds ?? .zero
        let topOffset: CGFloat
        if scrollView.documentView?.isFlipped == true {
            topOffset = visibleBounds.minY
        } else {
            topOffset = max(0, documentBounds.maxY - visibleBounds.maxY)
        }
        coordinator?.setCanScrollToTop(topOffset > Self.topTolerance)
    }

    private func detachObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        if observedScrollView != nil {
            coordinator?.setCanScrollToTop(false)
            coordinator?.setLocked(false)
        }
        observedScrollView = nil
    }

    override func removeFromSuperview() {
        detachObservers()
        super.removeFromSuperview()
    }

    deinit {
        MainActor.assumeIsolated {
            detachObservers()
        }
    }

    private static let topTolerance: CGFloat = 8
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
