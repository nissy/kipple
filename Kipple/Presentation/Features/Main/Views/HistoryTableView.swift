import AppKit
import SwiftUI

@MainActor
final class HistoryTableProxy {
    weak var table: NSTableView?
    var itemIDs: [UUID] = []

    func scrollTo(_ itemID: UUID) {
        guard let table, let scroll = table.enclosingScrollView, let index = itemIDs.firstIndex(of: itemID),
              index < table.numberOfRows else { return }
        let clip = scroll.contentView
        var bounds = clip.bounds
        bounds.origin.y = table.rect(ofRow: index).minY - scroll.contentInsets.top
        clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
        scroll.reflectScrolledClipView(clip)
    }
}

struct HistoryTableView<Row: View>: NSViewRepresentable {
    let entries: HistoryListEntries
    let hasMoreItems: Bool
    let showsProgress: Bool
    let proxy: HistoryTableProxy
    @Binding var canScrollToTop: Bool
    @Binding var isScrollLocked: Bool
    let onLoadMore: (ClipItem) -> Void
    let row: (HistoryListEntry) -> Row

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView()
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        withTransaction(context.transaction) {
            context.coordinator.update(self, in: scroll)
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.detach(from: scroll)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private var parent: HistoryTableView
        private var itemIDs: [UUID] = []
        private var showsProgress = false
        private var requestedLastID: UUID?
        private var observers: [NSObjectProtocol] = []
        private weak var attachedScrollView: NSScrollView?

        private let rowIdentifier = NSUserInterfaceItemIdentifier("history-row")
        private let progressIdentifier = NSUserInterfaceItemIdentifier("history-progress")

        init(parent: HistoryTableView) {
            self.parent = parent
        }

        func makeScrollView() -> NSScrollView {
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = false
            scroll.automaticallyAdjustsContentInsets = false
            let padding = MainViewMetrics.HistoryRows.verticalPadding
            scroll.contentInsets = NSEdgeInsets(top: padding, left: 0, bottom: padding, right: 0)

            let table = NSTableView()
            table.style = .plain
            table.headerView = nil
            table.backgroundColor = .clear
            table.selectionHighlightStyle = .none
            table.usesAutomaticRowHeights = false
            table.rowHeight = MainViewMetrics.HistoryRows.height
            table.intercellSpacing = CGSize(width: 0, height: MainViewMetrics.HistoryRows.spacing)
            table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
            table.autoresizingMask = [.width]
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
            column.minWidth = 0
            column.resizingMask = [.autoresizingMask]
            table.addTableColumn(column)
            table.dataSource = self
            table.delegate = self
            scroll.documentView = table

            attachedScrollView = scroll
            parent.proxy.table = table
            observeScrolling(in: scroll)
            return scroll
        }

        func update(_ parent: HistoryTableView, in scroll: NSScrollView) {
            guard let table = scroll.documentView as? NSTableView else { return }
            let previousIDs = itemIDs
            let previousProgress = showsProgress
            let hadMoreItems = self.parent.hasMoreItems
            self.parent = parent
            itemIDs = parent.entries.map(\.id)
            showsProgress = parent.showsProgress
            parent.proxy.itemIDs = itemIDs

            if previousIDs != itemIDs || hadMoreItems != parent.hasMoreItems || previousProgress != showsProgress {
                requestedLastID = nil
            }
            if itemIDs.count > previousIDs.count, itemIDs.starts(with: previousIDs),
               !previousProgress, !showsProgress, !previousIDs.isEmpty {
                let indexes = IndexSet(integersIn: previousIDs.count..<itemIDs.count)
                table.insertRows(at: indexes, withAnimation: [])
            } else if previousIDs != itemIDs || previousProgress != showsProgress {
                table.reloadData()
            }
            updateAvailableRows(in: table)
        }

        private func updateAvailableRows(in table: NSTableView) {
            table.enumerateAvailableRowViews { rowView, index in
                guard parent.entries.indices.contains(index) else { return }
                for case let host as NSHostingView<Row?> in rowView.subviews {
                    host.rootView = parent.row(parent.entries[index])
                }
            }
            let lastIndex = itemIDs.count - 1
            if lastIndex >= 0 && NSLocationInRange(lastIndex, table.rows(in: table.visibleRect)) {
                requestMoreIfNeeded()
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { itemIDs.count + (showsProgress ? 1 : 0) }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            row == itemIDs.count ? 38 : MainViewMetrics.HistoryRows.height
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
            guard index < parent.entries.count else { return progressView(in: tableView) }
            let row = parent.row(parent.entries[index])
            let host: NSHostingView<Row?>
            if let reused = tableView.makeView(withIdentifier: rowIdentifier, owner: nil) as? NSHostingView<Row?> {
                host = reused
                host.rootView = row
            } else {
                host = NSHostingView(rootView: row)
                host.identifier = rowIdentifier
                host.sizingOptions = []
            }
            if index == parent.entries.count - 1 { requestMoreIfNeeded() }
            return host
        }

        func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int) {
            // End the old SwiftUI row's lifetime before AppKit gives this cell a new item.
            for case let host as NSHostingView<Row?> in rowView.subviews {
                host.rootView = nil
            }
        }

        private func progressView(in table: NSTableView) -> NSView {
            typealias ProgressHost = NSHostingView<ProgressView<EmptyView, EmptyView>>
            let view = table.makeView(withIdentifier: progressIdentifier, owner: nil) as? ProgressHost
                ?? ProgressHost(rootView: ProgressView())
            view.identifier = progressIdentifier
            view.sizingOptions = []
            return view
        }

        private func requestMoreIfNeeded() {
            guard parent.hasMoreItems, !showsProgress, let item = parent.entries.last?.fullItem,
                  item.id != requestedLastID else { return }
            requestedLastID = item.id
            Task { @MainActor [weak self] in
                guard let self, self.attachedScrollView != nil, self.parent.hasMoreItems, !self.showsProgress,
                      self.parent.entries.last?.id == item.id else { return }
                self.parent.onLoadMore(item)
            }
        }

        private func observeScrolling(in scroll: NSScrollView) {
            scroll.contentView.postsBoundsChangedNotifications = true
            let center = NotificationCenter.default
            observers = [
                center.addObserver(
                    forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
                ) { [weak self, weak scroll] _ in
                    Task { @MainActor in
                        guard let self, let scroll, self.attachedScrollView === scroll else { return }
                        let offset = scroll.contentView.bounds.minY + scroll.contentInsets.top
                        if self.parent.canScrollToTop != (offset > 8) { self.parent.canScrollToTop = offset > 8 }
                    }
                },
                center.addObserver(
                    forName: NSScrollView.willStartLiveScrollNotification, object: scroll, queue: .main
                ) { [weak self, weak scroll] _ in
                    Task { @MainActor in
                        guard let self, let scroll, self.attachedScrollView === scroll else { return }
                        self.parent.isScrollLocked = true
                        HistoryPopoverManager.shared.scheduleHide()
                    }
                },
                center.addObserver(
                    forName: NSScrollView.didEndLiveScrollNotification, object: scroll, queue: .main
                ) { [weak self, weak scroll] _ in
                    Task { @MainActor in
                        guard let self, let scroll, self.attachedScrollView === scroll else { return }
                        self.parent.isScrollLocked = false
                    }
                }
            ]
        }

        func detach(from scroll: NSScrollView) {
            attachedScrollView = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            if parent.proxy.table === scroll.documentView {
                parent.proxy.table = nil
                parent.proxy.itemIDs = []
            }
            (scroll.documentView as? NSTableView)?.delegate = nil
            (scroll.documentView as? NSTableView)?.dataSource = nil
        }
    }
}
