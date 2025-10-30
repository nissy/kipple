import Foundation
import AppKit

// MARK: - Modern Clipboard Service Adapter

/// Adapter to bridge ModernClipboardService (Actor) with existing ClipboardServiceProtocol
@MainActor
final class ModernClipboardServiceAdapter: ObservableObject, ClipboardServiceProtocol, QueueAutoClearControlling {
    // MARK: - Published Properties

    @Published var history: [ClipItem] = []
    @Published var currentClipboardContent: String?
    @Published var autoClearRemainingTime: TimeInterval?

    // MARK: - Properties

    private let modernService = ModernClipboardService.shared
    private var refreshTask: Task<Void, Never>?
    private nonisolated(unsafe) var autoClearTimer: Timer?
    private var pendingClipboardContent: String?
    private var autoClearPausedByQueue = false

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
        autoClearTimer?.invalidate()
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
        restartAutoClearTimerIfNeeded()
        Task {
            await modernService.copyToClipboard(content, fromEditor: fromEditor)
            await refreshHistory()
        }
    }

    func recopyFromHistory(_ item: ClipItem) {
        pendingClipboardContent = item.content
        currentClipboardContent = item.content
        restartAutoClearTimerIfNeeded()
        Task {
            await modernService.recopyFromHistory(item)
            await refreshHistory()
        }
    }

    func clearSystemClipboard() async {
        await modernService.clearSystemClipboard()
        pendingClipboardContent = nil
        currentClipboardContent = nil
        stopAutoClearTimer()
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
                        self.autoClearRemainingTime = nil
                        // Clear only system clipboard, not history (matches legacy behavior)
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            await self.performAutoClear()
                            self.stopAutoClearTimer()
                        }
                    }
                }
            }
        }
        }

    func stopAutoClearTimer(resetRemaining: Bool = true) {
        autoClearTimer?.invalidate()
        autoClearTimer = nil
        if resetRemaining || autoClearPausedByQueue {
            autoClearRemainingTime = nil
        }
    }

    // MARK: - Private Methods

    /// Clear only the system clipboard, preserving history (matches legacy behavior)
    internal func performAutoClear() async {
        // Check if current clipboard content is text
        guard NSPasteboard.general.string(forType: .string) != nil else {
            return
        }

        await clearSystemClipboard()
    }

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
        let newHistory = await modernService.getHistory()
        let newCurrentContent = await modernService.getCurrentClipboardContent()

        // Only update if history actually changed (comparing IDs and pinned states)
        let historyChanged = historiesDiffer(lhs: history, rhs: newHistory)

        if historyChanged {
            history = newHistory

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
            }
        } else if currentClipboardContent != newCurrentContent {
            currentClipboardContent = newCurrentContent
        }

        if let updatedContent = currentClipboardContent,
           updatedContent != previousClipboardContent,
           !updatedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            restartAutoClearTimerIfNeeded()
        }
    }

    #if DEBUG
    func resetAdapterStateForTesting() async {
        refreshTask?.cancel()
        refreshTask = nil
        history = []
        currentClipboardContent = nil
        autoClearRemainingTime = nil
        pendingClipboardContent = nil
        autoClearPausedByQueue = false

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
    private func historiesDiffer(lhs: [ClipItem], rhs: [ClipItem]) -> Bool {
        guard lhs.count == rhs.count else { return true }
        return zip(lhs, rhs).contains { left, right in
            left.id != right.id ||
            left.isPinned != right.isPinned ||
            left.timestamp != right.timestamp
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

    func pauseAutoClearForQueue() {
        guard !autoClearPausedByQueue else { return }
        guard AppSettings.shared.enableAutoClear else { return }
        autoClearPausedByQueue = true
        stopAutoClearTimer(resetRemaining: false)
    }

    func resumeAutoClearAfterQueue() {
        guard autoClearPausedByQueue else { return }
        autoClearPausedByQueue = false
        restartAutoClearTimerIfNeeded()
    }
}

private extension ModernClipboardServiceAdapter {
    func restartAutoClearTimerIfNeeded() {
        if autoClearPausedByQueue {
            stopAutoClearTimer(resetRemaining: false)
            return
        }
        let settings = AppSettings.shared
        guard settings.enableAutoClear else {
            stopAutoClearTimer()
            return
        }

        let interval = settings.autoClearInterval
        guard interval > 0 else {
            stopAutoClearTimer()
            return
        }

        startAutoClearTimer(minutes: interval)
    }
}
