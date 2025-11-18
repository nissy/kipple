import SwiftUI
import AppKit

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
    @State private var isScrollLocked = false
    @StateObject private var hoverCoordinator = HistoryHoverCoordinator()

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
                        isScrollLocked: isScrollLocked,
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
            .transaction { tx in
                if isScrollLocked {
                    tx.disablesAnimations = true
                }
            }
        .background(
            Color(NSColor.controlBackgroundColor).opacity(0.3)
        )
        .background {
            ScrollLockObserver(isLocked: $isScrollLocked)
                .allowsHitTesting(false)
        }
        .onChange(of: copyScrollRequest?.id) { _ in
            handleCopyScrollRequest(with: proxy)
        }
        .onChange(of: hoverResetRequest?.id) { _ in
            handleHoverResetRequest()
        }
        .onChange(of: isScrollLocked) { locked in
            if locked {
                hoverCoordinator.clearHover()
            }
        }
        }
        .environmentObject(hoverCoordinator)
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

    private func handleHoverResetRequest() {
        guard hoverResetRequest != nil else { return }
        hoverResetRequest = nil
        hoverResetSignal = UUID()
    }
}

struct HistoryCopyScrollRequest: Identifiable, Equatable {
    let id = UUID()
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

private struct ScrollLockObserver: NSViewRepresentable {
    @Binding var isLocked: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLocked: $isLocked)
    }

    func makeNSView(context: Context) -> ScrollLockObserverView {
        let view = ScrollLockObserverView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ScrollLockObserverView, context: Context) {
        nsView.coordinator = context.coordinator
        nsView.attachIfNeeded()
    }

    final class Coordinator {
        private var isLocked: Binding<Bool>

        init(isLocked: Binding<Bool>) {
            self.isLocked = isLocked
        }

        func setLocked(_ locked: Bool) {
            if isLocked.wrappedValue != locked {
                isLocked.wrappedValue = locked
            }
        }
    }
}

private final class ScrollLockObserverView: NSView {
    weak var coordinator: ScrollLockObserver.Coordinator?
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
        let target = findEnclosingScrollView()
        if observedScrollView === target { return }
        detachObservers()
        guard let scrollView = target else { return }
        observedScrollView = scrollView
        attachObservers(to: scrollView)
    }

    private func findEnclosingScrollView() -> NSScrollView? {
        var current: NSView? = self
        while let view = current {
            if let scroll = view as? NSScrollView {
                return scroll
            }
            current = view.superview
        }
        return nil
    }

    private func attachObservers(to scrollView: NSScrollView) {
        let center = NotificationCenter.default
        let will = center.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: scrollView, queue: .main) { [weak self] _ in
            self?.coordinator?.setLocked(true)
            HistoryPopoverManager.shared.scheduleHide()
        }
        let did = center.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: scrollView, queue: .main) { [weak self] _ in
            self?.coordinator?.setLocked(false)
        }
        observers = [will, did]
    }

    private func detachObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        if observedScrollView != nil {
            coordinator?.setLocked(false)
        }
        observedScrollView = nil
    }

    override func removeFromSuperview() {
        detachObservers()
        super.removeFromSuperview()
    }

    deinit {
        detachObservers()
    }
}
