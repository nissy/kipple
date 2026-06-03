import Foundation
import AppKit

// MARK: - Modern Clipboard Service Adapter

/// Adapter to bridge ModernClipboardService (Actor) with existing ClipboardServiceProtocol
@MainActor
final class ModernClipboardServiceAdapter: ObservableObject, ClipboardServiceProtocol {
    // MARK: - Published Properties

    @Published var history: [ClipItem] = []
    @Published var currentClipboardContent: String?

    // MARK: - Properties

    private let modernService = ModernClipboardService.shared
    private var refreshTask: Task<Void, Never>?
    private var pendingClipboardContent: String?
    private var lastKnownHistoryRevision: UInt64?

    // ClipboardServiceProtocol requirement
    var onHistoryChanged: ((ClipItem) -> Void)?

    // MARK: - Singleton

    static let shared = ModernClipboardServiceAdapter()

    // MARK: - Initialization

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(historyDidChange(_:)),
            name: .modernClipboardHistoryDidChange,
            object: nil
        )
        startPeriodicRefresh()
    }

    deinit {
        refreshTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - ClipboardServiceProtocol Implementation

    func startMonitoring() {
        Task {
            await modernService.startMonitoring()
        }
    }

    func stopMonitoring() {
        Task {
            await modernService.stopMonitoring()
        }
    }

    func copyToClipboard(_ content: String, fromEditor: Bool) {
        pendingClipboardContent = content
        currentClipboardContent = content
        Task {
            await modernService.copyToClipboard(content, fromEditor: fromEditor)
            await refreshHistory()
        }
    }

    func writeToClipboardOnly(_ content: String) {
        pendingClipboardContent = content
        currentClipboardContent = content.isEmpty ? nil : content

        Task {
            await modernService.writeToClipboardOnly(content)
        }
    }

    @discardableResult
    func addEditorItems(_ contents: [String]) async -> [ClipItem] {
        let items = await modernService.addEditorItems(contents)
        await refreshHistory()
        return items
    }

    func recopyFromHistory(_ item: ClipItem) {
        prepareForRecopy(of: item)
        Task {
            await modernService.recopyFromHistory(item)
            await refreshHistory()
        }
    }

    func clearSystemClipboard() async {
        await modernService.clearSystemClipboard()
        pendingClipboardContent = nil
        currentClipboardContent = nil
        await refreshHistory()
    }

    func togglePin(for item: ClipItem) -> Bool {
        // Find the item in current history
        guard let index = history.firstIndex(where: { $0.id == item.id }) else {
            // Item not in current history - should not happen in normal flow
            Logger.shared.log("togglePin: Item not found in history", level: .warning)
            return false
        }

        let currentlyPinned = history[index].isPinned

        // If we're trying to pin (currently unpinned)
        if !currentlyPinned {
            // Check if we've reached the max pinned items limit
            let currentPinnedCount = history.filter { $0.isPinned }.count
            let maxPinnedItems = AppSettings.shared.maxPinnedItems

            if currentPinnedCount >= maxPinnedItems {
                // Exceeded limit, don't allow pinning
                Logger.shared.log("Cannot pin item: Maximum pinned items limit (\(maxPinnedItems)) reached", level: .warning)
                return false
            }
        }

        // Update backend synchronously via Task and wait for result
        history[index].isPinned.toggle()
        let newState = history[index].isPinned

        Task { [weak self] in
            guard let self else { return }
            let result = await self.modernService.togglePin(for: item)

            if result != newState {
                await MainActor.run {
                    if let currentIndex = self.history.firstIndex(where: { $0.id == item.id }) {
                        self.history[currentIndex].isPinned = result
                    }
                }
            }

            // Always refresh history to ensure consistency
            await self.refreshHistory()
        }

        // Return expected new state (backend will be updated async)
        return newState
    }

    func deleteItem(_ item: ClipItem) {
        Task {
            await self.deleteItem(item)
        }
    }

    func deleteItem(_ item: ClipItem) async {
        await modernService.deleteItem(item)
        await refreshHistory()
    }

    func clearHistory(keepPinned: Bool) async {
        await modernService.clearHistory(keepPinned: keepPinned)
        await refreshHistory()
    }

    func updateItem(_ item: ClipItem) async {
        await modernService.updateItem(item)
        await refreshHistory()
    }

    func clearAllHistory(keepPinned: Bool = false) {
        Task {
            await modernService.clearHistory(keepPinned: keepPinned)
            await refreshHistory()
        }
    }

    func clearAllHistory() {
        Task {
            await modernService.clearAllHistory()
            await refreshHistory()
        }
    }

    func flushPendingSaves() async {
        // Delegate to the modern service
        await modernService.flushPendingSaves()
    }

    func searchHistory(_ query: String) -> [ClipItem] {
        // Synchronous search on current cached history
        history.filter { item in
            item.content.localizedCaseInsensitiveContains(query)
        }
    }

    func searchHistoryAsync(_ query: String) async -> [ClipItem] {
        await modernService.searchHistory(query: query)
    }

    // MARK: - Private Methods

    private func startPeriodicRefresh() {
        let interval: TimeInterval = 5.0
        refreshTask = Task {
            while !Task.isCancelled {
                await refreshHistory()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func refreshHistory() async {
        let previousClipboardContent = currentClipboardContent
        let newRevision = await modernService.getHistoryRevision()
        let newCurrentContent = await modernService.getCurrentClipboardContent()

        let historyChanged = lastKnownHistoryRevision != newRevision

        if historyChanged {
            PerformanceTrace.event("adapter_refresh_started", revision: newRevision)
            let newHistory = await modernService.getHistory()
            PerformanceTrace.event(
                "adapter_history_will_publish",
                content: newHistory.first?.content,
                revision: newRevision,
                count: newHistory.count
            )
            history = newHistory
            lastKnownHistoryRevision = newRevision
            PerformanceTrace.event(
                "adapter_history_did_publish",
                content: newHistory.first?.content,
                revision: newRevision,
                count: newHistory.count
            )

            // Call the history changed callback if set
            if let firstItem = newHistory.first {
                onHistoryChanged?(firstItem)
            }
        }

        // Update current clipboard content if changed
        if let pending = pendingClipboardContent {
            if newCurrentContent == pending {
                currentClipboardContent = pending
                pendingClipboardContent = nil
            } else if newCurrentContent != previousClipboardContent {
                currentClipboardContent = newCurrentContent
                pendingClipboardContent = nil
            }
        } else if currentClipboardContent != newCurrentContent {
            currentClipboardContent = newCurrentContent
        }
    }

    #if DEBUG
    func resetAdapterStateForTesting() async {
        refreshTask?.cancel()
        refreshTask = nil
        history = []
        currentClipboardContent = nil
        pendingClipboardContent = nil
        lastKnownHistoryRevision = nil

        // Ensure we are in sync with the service after it resets.
        await refreshHistory()
        startPeriodicRefresh()
    }
    #endif

    @objc private func historyDidChange(_ notification: Notification) {
        Task { [weak self] in
            guard let self else { return }
            await self.refreshHistory()
        }
    }
}

// MARK: - Extensions for Compatibility

extension ModernClipboardServiceAdapter: ClipboardServiceAsyncRecopying {
    func recopyFromHistoryAndWait(_ item: ClipItem) async {
        prepareForRecopy(of: item)
        await modernService.recopyFromHistory(item)
        await refreshHistory()
    }

    /// pasteboard 書き込みのみ待機する軽量版。history 再同期は後段で finalizeRecopyRefresh() を呼ぶこと
    func recopyFromHistoryAwaitingPasteboard(_ item: ClipItem) async {
        prepareForRecopy(of: item)
        await modernService.recopyFromHistory(item)
    }

    /// recopyFromHistoryAwaitingPasteboard 後の history 再同期
    func finalizeRecopyRefresh() async {
        await refreshHistory()
    }

    private func prepareForRecopy(of item: ClipItem) {
        pendingClipboardContent = item.content
        currentClipboardContent = item.content
    }

    /// Get pinned items from history
    var pinnedItems: [ClipItem] {
        history.filter { $0.isPinned }
    }

    /// Get unpinned items from history
    var unpinnedItems: [ClipItem] {
        history.filter { !$0.isPinned }
    }

    /// Check if monitoring is active
    func isMonitoring() async -> Bool {
        await modernService.isMonitoring()
    }

    /// Set maximum history items
    func setMaxHistoryItems(_ max: Int) async {
        await modernService.setMaxHistoryItems(max)
        await refreshHistory()
    }
}
