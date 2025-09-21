import Foundation
import Combine

// MARK: - Modern Clipboard Service Adapter

/// Adapter to bridge ModernClipboardService (Actor) with existing ClipboardServiceProtocol
@available(macOS 13.0, *)
@MainActor
final class ModernClipboardServiceAdapter: ObservableObject, ClipboardServiceProtocol {
    // MARK: - Published Properties

    @Published var history: [ClipItem] = []
    @Published var currentClipboardContent: String?
    @Published var autoClearRemainingTime: TimeInterval?

    // MARK: - Properties

    private let modernService = ModernClipboardService.shared
    private var refreshTask: Task<Void, Never>?
    private var autoClearTimer: Timer?

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

    func togglePin(for item: ClipItem) -> Bool {
        // Find the item in current history and toggle its pin state
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            // Toggle pin state locally first for immediate feedback
            history[index].isPinned.toggle()
            let isPinned = history[index].isPinned

            // Then update the backend asynchronously
            Task {
                _ = await modernService.togglePin(for: item)
                await refreshHistory()
            }

            return isPinned
        } else {
            // If item not in history, add it as pinned
            var newItem = item
            newItem.isPinned = true
            history.insert(newItem, at: 0)

            // Update backend
            Task {
                await modernService.updateItem(newItem)
                await refreshHistory()
            }

            return true
        }
    }

    func deleteItem(_ item: ClipItem) {
        Task {
            await modernService.deleteItem(item)
            await refreshHistory()
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
        // No-op for actor-based implementation
        // Actor handles all saves internally
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
                        await self.clearHistory(keepPinned: true)
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

    private func startPeriodicRefresh() {
        refreshTask = Task {
            while !Task.isCancelled {
                await refreshHistory()
                // Refresh every 0.5 seconds to keep UI responsive
                try? await Task.sleep(for: .seconds(0.5))
            }
        }
    }

    private func refreshHistory() async {
        let newHistory = await modernService.getHistory()
        let newCurrentContent = await modernService.getCurrentClipboardContent()

        // Only update if changed to avoid unnecessary UI updates
        if history != newHistory {
            history = newHistory
            // Call the history changed callback if set
            if let firstItem = newHistory.first {
                onHistoryChanged?(firstItem)
            }
        }
        if currentClipboardContent != newCurrentContent {
            currentClipboardContent = newCurrentContent
        }
    }
}

// MARK: - Extensions for Compatibility

@available(macOS 13.0, *)
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
    }
}
