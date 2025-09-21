import Foundation
import AppKit
import Combine

// MARK: - Modern Clipboard Service (Actor-based)

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
    private var maxHistoryItems = 300  // Default value, will be updated from AppSettings
    private var isMonitoringFlag = false

    // Repository for persistence
    private var repository: ClipboardRepositoryProtocol?
    private let saveSubject = PassthroughSubject<[ClipItem], Never>()
    private var saveCancellable: AnyCancellable?
    private var pendingSaveTask: Task<Void, Never>?

    // MARK: - Singleton

    static let shared = ModernClipboardService()

    // MARK: - Initialization

    private init() {
        // Setup save pipeline and repository initialization in async context
        Task {
            // Get initial settings from AppSettings
            let maxItems = await MainActor.run {
                AppSettings.shared.maxHistoryItems
            }
            await self.setMaxHistoryItems(maxItems)

            await self.initializeRepository()
            await self.setupSavePipeline()
            await self.loadHistoryFromRepository()
            await self.setupAppTracking()
        }
    }

    private func initializeRepository() async {
        // Initialize repository
        self.repository = await MainActor.run {
            do {
                return try RepositoryProvider.resolve()
            } catch {
                Logger.shared.error("Failed to initialize repository: \(error)")
                return nil
            }
        }
    }

    private func setupSavePipeline() {
        saveCancellable = saveSubject
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] items in
                Task {
                    await self?.saveToRepository(items)
                }
            }
    }

    private func loadHistoryFromRepository() async {
        guard let repository = repository else { return }

        do {
            // Load all items first (repository may have more than current limit)
            let items = try await repository.load(limit: 1000)
            history = items
            Logger.shared.log("Loaded \(items.count) items from repository")

            // Apply current user's limit setting
            trimHistory()
            Logger.shared.log("Trimmed history to \(history.count) items (max: \(maxHistoryItems))")
        } catch {
            Logger.shared.error("Failed to load history: \(error)")
        }
    }

    private func saveToRepository(_ items: [ClipItem]) async {
        guard let repository = repository else { return }

        do {
            try await repository.save(items)
            Logger.shared.debug("Saved \(items.count) items to repository")
        } catch {
            Logger.shared.error("Failed to save to repository: \(error)")
        }
    }

    // MARK: - Core Functionality

    func getHistory() async -> [ClipItem] {
        history
    }

    func startMonitoring() async {
        guard !isMonitoringFlag else { return }
        isMonitoringFlag = true

        // Start app switching observation
        await setupAppTracking()

        pollingTask?.cancel()
        pollingTask = Task { await startPollingLoop() }
    }

    func stopMonitoring() async {
        isMonitoringFlag = false
        pollingTask?.cancel()
        pollingTask = nil

        // Stop app switching observation
        await stopAppSwitchObserver()
    }

    func isMonitoring() async -> Bool {
        isMonitoringFlag
    }

    func copyToClipboard(_ content: String, fromEditor: Bool) async {
        // Mark as internal copy to avoid re-adding to history
        await state.setInternalCopy(true)
        await state.setFromEditor(fromEditor)

        // Get app info for metadata
        let appInfo = await MainActor.run {
            getActiveAppInfo()
        }

        // Add to history immediately with metadata
        let item = ClipItem(
            content: content,
            isPinned: false,
            sourceApp: fromEditor ? "Kipple" : appInfo.appName,
            windowTitle: fromEditor ? "Quick Editor" : appInfo.windowTitle,
            bundleIdentifier: fromEditor ? Bundle.main.bundleIdentifier : appInfo.bundleId,
            processID: fromEditor ? ProcessInfo.processInfo.processIdentifier : appInfo.pid,
            isFromEditor: fromEditor
        )
        addToHistory(item)

        // Copy to system clipboard
        let newChangeCount = await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(content, forType: .string)
            return pasteboard.changeCount
        }

        // Record the expected changeCount for this internal operation
        await state.setExpectedChangeCount(newChangeCount)
    }

    func recopyFromHistory(_ item: ClipItem) async {
        // Set flags BEFORE updating clipboard to prevent race condition
        await state.setInternalCopy(true)
        await state.setFromEditor(item.isFromEditor ?? false)

        // Preserve all metadata from the original item but update timestamp
        var newItem = item
        newItem.timestamp = Date()  // Update timestamp to current time

        // Check if an item with same content exists and preserve its pin state
        if let existingIndex = history.firstIndex(where: { $0.content == item.content }) {
            let existingItem = history[existingIndex]
            // Preserve pin state from existing item
            if existingItem.isPinned {
                newItem.isPinned = true
            }
            // Remove the existing item
            history.remove(at: existingIndex)
        }

        // Add item at the beginning with preserved metadata and new timestamp
        history.insert(newItem, at: 0)

        // Trim history to max size
        trimHistory()

        // Trigger save
        saveSubject.send(history)

        // Copy to system clipboard
        let newChangeCount = await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(item.content, forType: .string)
            return pasteboard.changeCount
        }

        // Record the expected changeCount for this internal operation
        await state.setExpectedChangeCount(newChangeCount)
    }

    // MARK: - History Management

    func clearAllHistory() async {
        let pinnedItems = history.filter { $0.isPinned }
        let removedItems = history.filter { !$0.isPinned }

        // Keep pinned items to match legacy implementation behavior
        history = pinnedItems

        // No hash cleanup needed - we don't use hash-based duplicate detection

        // Save updated history to repository
        saveSubject.send(history)
    }

    func clearHistory(keepPinned: Bool) async {
        let removedItems: [ClipItem]

        if keepPinned {
            removedItems = history.filter { !$0.isPinned }
            history = history.filter { $0.isPinned }
        } else {
            removedItems = history
            history.removeAll()
        }

        // No hash cleanup needed - we don't use hash-based duplicate detection

        // Save updated history
        saveSubject.send(history)
    }

    func togglePin(for item: ClipItem) async -> Bool {
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            let currentlyPinned = history[index].isPinned

            // If we're trying to pin (currently unpinned)
            if !currentlyPinned {
                // Check if we've reached the max pinned items limit
                let currentPinnedCount = history.filter { $0.isPinned }.count
                let maxPinnedItems = await MainActor.run { AppSettings.shared.maxPinnedItems }

                if currentPinnedCount >= maxPinnedItems {
                    // Exceeded limit, don't allow pinning
                    Logger.shared.log("Cannot pin item: Maximum pinned items limit (\(maxPinnedItems)) reached", level: .warning)
                    return false
                }
            }

            // Toggle the pin status
            history[index].isPinned.toggle()
            let isPinned = history[index].isPinned

            // Trigger save
            saveSubject.send(history)

            return isPinned
        }
        return false
    }

    func deleteItem(_ item: ClipItem) async {
        history.removeAll { $0.id == item.id }

        // No hash cleanup needed - we don't use hash-based duplicate detection

        // Trigger save
        saveSubject.send(history)
    }

    func updateItem(_ item: ClipItem) async {
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            let oldItem = history[index]

            // Content change is allowed - no special handling needed

            history[index] = item

            // Trigger save
            saveSubject.send(history)
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
        // Return actual system clipboard content, not history
        await MainActor.run {
            NSPasteboard.general.string(forType: .string)
        }
    }

    func getCurrentInterval() async -> TimeInterval {
        currentInterval
    }

    func setMaxHistoryItems(_ max: Int) async {
        maxHistoryItems = max
        trimHistory()
    }

    func setInternalOperation(_ value: Bool) async {
        await state.setInternalCopy(value)
    }

    func setExpectedChangeCount(_ value: Int?) async {
        await state.setExpectedChangeCount(value)
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

        // Check if this changeCount is from an expected internal operation
        let expectedChangeCount = await state.getExpectedChangeCount()
        if let expected = expectedChangeCount, changeCount == expected {
            // This is the internal operation we were expecting, skip it
            lastChangeCount = changeCount
            await state.setExpectedChangeCount(nil)
            await state.setInternalCopy(false)
            await state.setFromEditor(false)
            return
        }

        // Clear any stale expected count if we've moved past it
        if let expected = expectedChangeCount, changeCount > expected {
            await state.setExpectedChangeCount(nil)
            await state.setInternalCopy(false)
            await state.setFromEditor(false)
        }

        lastChangeCount = changeCount

        // Get clipboard content
        if let content = await MainActor.run(body: { [pasteboard] in
            pasteboard.string(forType: .string)
        }) {
            // Get app info for metadata
            let appInfo = await MainActor.run {
                getActiveAppInfo()
            }

            let isFromEditor = await state.getFromEditor()
            let item = ClipItem(
                content: content,
                sourceApp: isFromEditor ? "Kipple" : appInfo.appName,
                windowTitle: isFromEditor ? "Quick Editor" : appInfo.windowTitle,
                bundleIdentifier: isFromEditor ? Bundle.main.bundleIdentifier : appInfo.bundleId,
                processID: isFromEditor ? ProcessInfo.processInfo.processIdentifier : appInfo.pid,
                isFromEditor: isFromEditor
            )

            // Always add to history - addToHistory handles duplicates by moving them to top
            addToHistory(item)
            lastEventTime = Date()
        }

        // Reset flags
        await state.setFromEditor(false)
    }

    private func addToHistory(_ item: ClipItem) {
        // Check if an item with same content exists and preserve its pin state
        var newItem = item
        if let existingIndex = history.firstIndex(where: { $0.content == item.content }) {
            let existingItem = history[existingIndex]
            // Preserve pin state and other metadata from existing item
            if existingItem.isPinned {
                newItem.isPinned = true
            }
            // Remove the existing item
            history.remove(at: existingIndex)
        }

        // Add new item at the beginning
        history.insert(newItem, at: 0)

        // Trim history to max size
        trimHistory()

        // Trigger save
        saveSubject.send(history)
    }

    // MARK: - Flush Pending Saves

    func flushPendingSaves() async {
        // Cancel any pending save task
        pendingSaveTask?.cancel()

        // Save immediately
        await saveToRepository(history)
    }

    // MARK: - App Info

    private struct ActiveAppInfo {
        let appName: String?
        let windowTitle: String?
        let bundleId: String?
        let pid: Int32
    }

    @MainActor
    private func getActiveAppInfo() -> ActiveAppInfo {
        // Use LastActiveAppTracker to get the correct app
        let tracker = LastActiveAppTracker.shared
        let appInfo = tracker.getSourceAppInfo()

        // Try to get window title using CGWindowList
        let windowTitle = getWindowTitle(for: appInfo.pid)

        return ActiveAppInfo(
            appName: appInfo.name,
            windowTitle: windowTitle,
            bundleId: appInfo.bundleId,
            pid: appInfo.pid
        )
    }

    @MainActor
    private func getWindowTitle(for pid: Int32) -> String? {
        // Get window list for the specific process
        let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        // Find windows belonging to the process
        for windowInfo in windowList {
            // Check if window belongs to the target process
            if let windowPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
               windowPID == pid {

                // Get window name (title)
                if let windowName = windowInfo[kCGWindowName as String] as? String,
                   !windowName.isEmpty {
                    return windowName
                }

                // Fallback to window owner name if no title
                if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                   !ownerName.isEmpty {
                    // Only return owner name if it's different from app name
                    // to avoid redundant information
                    if let appName = NSWorkspace.shared.frontmostApplication?.localizedName,
                       ownerName != appName {
                        return ownerName
                    }
                }
            }
        }

        // No window title found
        return nil
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

    // MARK: - App Tracking

    private func setupAppTracking() async {
        // Initialize the app tracker
        await MainActor.run {
            LastActiveAppTracker.shared.startTracking()
        }
    }

    private func stopAppSwitchObserver() async {
        // Cleanup if needed
    }
}

// MARK: - Clipboard State Actor

actor ClipboardState {
    private var isInternalCopy = false
    private var isFromEditor = false
    private var expectedInternalChangeCount: Int?

    func getInternalCopy() -> Bool { isInternalCopy }
    func setInternalCopy(_ value: Bool) { isInternalCopy = value }

    func getFromEditor() -> Bool { isFromEditor }
    func setFromEditor(_ value: Bool) { isFromEditor = value }

    func getExpectedChangeCount() -> Int? { expectedInternalChangeCount }
    func setExpectedChangeCount(_ value: Int?) { expectedInternalChangeCount = value }
}
