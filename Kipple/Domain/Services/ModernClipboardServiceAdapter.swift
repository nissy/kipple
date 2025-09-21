import Foundation
import Combine
import AppKit

// MARK: - Modern Clipboard Service Adapter

/// Adapter to bridge ModernClipboardService (Actor) with existing ClipboardServiceProtocol
@MainActor
final class ModernClipboardServiceAdapter: ObservableObject, ClipboardServiceProtocol {
    // MARK: - Published Properties

    @Published var history: [ClipItem] = []
    @Published var currentClipboardContent: String?
    @Published var autoClearRemainingTime: TimeInterval?

    // MARK: - Properties

    private let modernService = ModernClipboardService.shared
    private var refreshTask: Task<Void, Never>?
    private nonisolated(unsafe) var autoClearTimer: Timer?

    // ClipboardServiceProtocol requirement
    var onHistoryChanged: ((ClipItem) -> Void)?

    // MARK: - Singleton

    static let shared = ModernClipboardServiceAdapter()

    // MARK: - Initialization

    private init() {
        startPeriodicRefresh()
    }

    deinit {
        refreshTask?.cancel()
        autoClearTimer?.invalidate()
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
        Task {
            await modernService.copyToClipboard(content, fromEditor: fromEditor)
            await refreshHistory()
        }
    }

    func recopyFromHistory(_ item: ClipItem) {
        Task {
            await modernService.recopyFromHistory(item)
            await refreshHistory()
        }
    }

    func clearSystemClipboard() {
        // Clear the system clipboard
        NSPasteboard.general.clearContents()
        let newChangeCount = NSPasteboard.general.changeCount

        // Update our state immediately
        currentClipboardContent = nil

        // Mark the new changeCount as an internal operation to skip
        Task {
            await modernService.setInternalOperation(true)
            await modernService.setExpectedChangeCount(newChangeCount)
        }
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
        Task {
            _ = await modernService.togglePin(for: item)
            // Always refresh history to ensure consistency
            await refreshHistory()
        }

        // Return expected new state (backend will be updated async)
        return !currentlyPinned
    }

    func deleteItem(_ item: ClipItem) {
        Task {
            await modernService.deleteItem(item)
            await refreshHistory()
        }
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

    // MARK: - Auto Clear Timer

    func startAutoClearTimer(minutes: Int) {
        autoClearTimer?.invalidate()
        autoClearRemainingTime = TimeInterval(minutes * 60)

        autoClearTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if let remaining = self.autoClearRemainingTime {
                    self.autoClearRemainingTime = max(0, remaining - 1)
                    if remaining <= 0 {
                        // Clear only system clipboard, not history (matches legacy behavior)
                        self.performAutoClear()
                        self.stopAutoClearTimer()
                    }
                }
            }
        }
    }

    func stopAutoClearTimer() {
        autoClearTimer?.invalidate()
        autoClearTimer = nil
        autoClearRemainingTime = nil
    }

    // MARK: - Private Methods

    /// Clear only the system clipboard, preserving history (matches legacy behavior)
    internal func performAutoClear() {
        // Check if current clipboard content is text
        guard NSPasteboard.general.string(forType: .string) != nil else {
            Logger.shared.log("Skipping auto-clear: current clipboard content is not text")
            return
        }

        Logger.shared.log("Performing auto-clear of system clipboard (Modern pathway)")

        // Clear the system clipboard only
        NSPasteboard.general.clearContents()

        // Update the current clipboard content
        currentClipboardContent = nil
    }

    private func startPeriodicRefresh() {
        refreshTask = Task {
            while !Task.isCancelled {
                await refreshHistory()
                // Refresh every 1 second for balanced performance
                // This reduces CPU usage while maintaining reasonable responsiveness
                try? await Task.sleep(for: .seconds(1.0))
            }
        }
    }

    private func refreshHistory() async {
        let newHistory = await modernService.getHistory()
        let newCurrentContent = await modernService.getCurrentClipboardContent()

        // Only update if history actually changed (comparing IDs and pinned states)
        let historyChanged = history.count != newHistory.count ||
            !zip(history, newHistory).allSatisfy { old, new in
                old.id == new.id && old.isPinned == new.isPinned
            }

        if historyChanged {
            history = newHistory

            // Call the history changed callback if set
            if let firstItem = newHistory.first {
                onHistoryChanged?(firstItem)
            }
        }

        // Update current clipboard content if changed
        if currentClipboardContent != newCurrentContent {
            currentClipboardContent = newCurrentContent
        }
    }
}

// MARK: - Extensions for Compatibility

extension ModernClipboardServiceAdapter {
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
