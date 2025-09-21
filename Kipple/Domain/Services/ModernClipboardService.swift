import Foundation
import AppKit

// MARK: - Modern Clipboard Service (Actor-based)

@available(macOS 13.0, *)
actor ModernClipboardService: ModernClipboardServiceProtocol {
    // MARK: - Properties

    private var history: [ClipItem] = []
    private var pollingTask: Task<Void, Never>?
    private let state = ClipboardState()
    private var lastEventTime = Date()
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var currentInterval: TimeInterval = 0.5
    private let minInterval: TimeInterval = 0.5
    private let maxInterval: TimeInterval = 1.0
    private var maxHistoryItems = 1000
    private var isMonitoringFlag = false

    // MARK: - Singleton

    static let shared = ModernClipboardService()

    // MARK: - Core Functionality

    func getHistory() async -> [ClipItem] {
        history
    }

    func startMonitoring() async {
        guard !isMonitoringFlag else { return }
        isMonitoringFlag = true
        pollingTask?.cancel()
        pollingTask = Task { await startPollingLoop() }
    }

    func stopMonitoring() async {
        isMonitoringFlag = false
        pollingTask?.cancel()
        pollingTask = nil
    }

    func isMonitoring() async -> Bool {
        isMonitoringFlag
    }

    func copyToClipboard(_ content: String, fromEditor: Bool) async {
        // Mark as internal copy to avoid re-adding to history
        await state.setInternalCopy(true)
        await state.setFromEditor(fromEditor)

        // Add to history immediately
        let item = ClipItem(
            content: content,
            isPinned: false,
            isFromEditor: fromEditor
        )
        addToHistory(item)

        // Copy to system clipboard
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(content, forType: .string)
        }
    }

    // MARK: - History Management

    func clearAllHistory() async {
        history.removeAll()
    }

    func clearHistory(keepPinned: Bool) async {
        if keepPinned {
            history = history.filter { $0.isPinned }
        } else {
            history.removeAll()
        }
    }

    func togglePin(for item: ClipItem) async -> Bool {
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            history[index].isPinned.toggle()
            return history[index].isPinned
        }
        return false
    }

    func deleteItem(_ item: ClipItem) async {
        history.removeAll { $0.id == item.id }
    }

    func updateItem(_ item: ClipItem) async {
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            history[index] = item
        }
    }

    // MARK: - Search and Filter

    func searchHistory(query: String) async -> [ClipItem] {
        history.filter { item in
            item.content.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Status and Configuration

    func getCurrentClipboardContent() async -> String? {
        history.first?.content
    }

    func getCurrentInterval() async -> TimeInterval {
        currentInterval
    }

    func setMaxHistoryItems(_ max: Int) async {
        maxHistoryItems = max
        trimHistory()
    }

    // MARK: - Private Methods

    private func startPollingLoop() async {
        while !Task.isCancelled && isMonitoringFlag {
            await checkClipboard()

            // Dynamic interval adjustment
            let newInterval = calculateInterval()
            if newInterval != currentInterval {
                currentInterval = newInterval
            }

            // Wait for next check
            try? await Task.sleep(for: .seconds(currentInterval))
        }
    }

    private func calculateInterval() -> TimeInterval {
        let timeSinceLastEvent = Date().timeIntervalSince(lastEventTime)
        if timeSinceLastEvent > 10 {
            // Increase interval during inactivity
            return min(maxInterval, currentInterval * 1.1)
        } else {
            // Decrease interval during activity
            return max(minInterval, currentInterval * 0.9)
        }
    }

    private func checkClipboard() async {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount

        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        // Check if this is an internal copy
        let isInternal = await state.getInternalCopy()
        if isInternal {
            await state.setInternalCopy(false)
            return
        }

        // Get clipboard content
        if let content = await MainActor.run(body: {
            pasteboard.string(forType: .string)
        }) {
            let hash = content.hashValue

            // Check for duplicates
            let isDuplicate = await state.checkDuplicate(hash)
            if !isDuplicate {
                let item = ClipItem(
                    content: content,
                    isFromEditor: await state.getFromEditor()
                )
                addToHistory(item)
                lastEventTime = Date()
            }
        }

        // Reset flags
        await state.setFromEditor(false)
    }

    private func addToHistory(_ item: ClipItem) {
        // Remove existing item with same content if exists
        history.removeAll { $0.content == item.content }

        // Add new item at the beginning
        history.insert(item, at: 0)

        // Trim history to max size
        trimHistory()
    }

    private func trimHistory() {
        if history.count > maxHistoryItems {
            // Keep pinned items and most recent items
            let pinnedItems = history.filter { $0.isPinned }
            let unpinnedItems = history.filter { !$0.isPinned }
            let maxUnpinned = maxHistoryItems - pinnedItems.count

            if maxUnpinned > 0 {
                history = pinnedItems + Array(unpinnedItems.prefix(maxUnpinned))
            } else {
                history = Array(pinnedItems.prefix(maxHistoryItems))
            }
        }
    }
}

// MARK: - Clipboard State Actor

@available(macOS 13.0, *)
actor ClipboardState {
    private var isInternalCopy = false
    private var isFromEditor = false
    private var recentHashes: [Int] = []
    private let maxRecentHashes = 50

    func getInternalCopy() -> Bool { isInternalCopy }
    func setInternalCopy(_ value: Bool) { isInternalCopy = value }

    func getFromEditor() -> Bool { isFromEditor }
    func setFromEditor(_ value: Bool) { isFromEditor = value }

    func checkDuplicate(_ hash: Int) -> Bool {
        if recentHashes.contains(hash) {
            return true
        }

        recentHashes.append(hash)
        if recentHashes.count > maxRecentHashes {
            recentHashes.removeFirst()
        }
        return false
    }

    func clearRecentHashes() {
        recentHashes.removeAll()
    }
}
