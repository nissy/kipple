import Foundation
import AppKit
import Combine

// swiftlint:disable type_body_length file_length

extension Notification.Name {
    static let modernClipboardHistoryDidChange = Notification.Name("ModernClipboardServiceHistoryDidChange")
}

// MARK: - Modern Clipboard Service (Actor-based)

actor ModernClipboardService: ModernClipboardServiceProtocol {
    private struct AutoPinCopySequence {
        let content: String
        let firstCopiedAt: Date
        var count: Int
    }

    // MARK: - Properties

    private var history: [ClipItem] = []
    private let mutationGate: AsyncMutationGate
    private let clipboardWriter: @MainActor @Sendable (ClipItem) -> Int
    private let clipboardReader: ClipboardReader?
    private var copyGeneration: UInt64 = 0
    private var isRepositoryReady = false
    private var pollingTask: Task<Void, Never>?
    private let state = ClipboardState()
    private var lastEventTime = Date()
    private var lastChangeCount = 0
    private var lastClipboardAccessRevision: UInt64 = 0
    private var initialClipboardChangeCount: Int?
    // ポーリング間隔（アクティブ時は短めにして遅延を減らす）
    private var currentInterval: TimeInterval = 0.12
    private let minInterval: TimeInterval = 0.08
    private let maxInterval: TimeInterval = 0.25
    private var maxHistoryItems = 300  // Default value, will be updated from AppSettings
    private var isMonitoringFlag = false

    // Repository for persistence
    private var repository: ClipboardRepositoryProtocol?
    private let saveSubject = PassthroughSubject<Void, Never>()
    private var saveCancellable: AnyCancellable?
    private var persistedSnapshot: [UUID: ClipItem] = [:]
    private var historyRevision: UInt64 = 0
    private var itemIDByContent: [String: UUID] = [:]
    private var autoPinCopySequence: AutoPinCopySequence?

    // MARK: - Singleton

    static let shared = ModernClipboardService()

    // MARK: - Initialization

    #if DEBUG
    init(
        testRepository: ClipboardRepositoryProtocol,
        loadOnStartup: Bool = false,
        clipboardWriter: @escaping @MainActor @Sendable (ClipItem) -> Int = writeSystemClipboard,
        clipboardReader: ClipboardReader? = nil
    ) {
        mutationGate = AsyncMutationGate(initiallyOccupied: loadOnStartup)
        self.clipboardWriter = clipboardWriter
        self.clipboardReader = clipboardReader
        repository = testRepository
        isRepositoryReady = !loadOnStartup
        if loadOnStartup {
            Task { await initializeService() }
        }
    }
    #endif

    private init() {
        // Reserve the mutation gate before publishing the service, so startup always runs first.
        mutationGate = AsyncMutationGate(initiallyOccupied: true)
        clipboardWriter = Self.writeSystemClipboard
        clipboardReader = nil
        Task { await initializeService() }
    }

    private func initializeService() async {
        defer { mutationGate.release() }
        maxHistoryItems = await MainActor.run { AppSettings.shared.maxHistoryItems }
        let observation = await MainActor.run { (clipboardReader ?? .shared).observation }
        lastChangeCount = observation.changeCount
        lastClipboardAccessRevision = observation.accessRevision
        initialClipboardChangeCount = lastChangeCount
        if repository == nil {
            await initializeRepository()
        }
        setupSavePipeline()
        await loadHistoryWhileLocked()
        await setupAppTracking()
    }

    private func initializeRepository() async {
        let repository = await RepositoryProvider.resolve()
        setRepository(repository)
    }

    func setRepository(_ repo: ClipboardRepositoryProtocol) {
        self.repository = repo
        isRepositoryReady = false
        persistedSnapshot = [:]
        itemIDByContent = [:]
    }

    private func setupSavePipeline() {
        saveCancellable = saveSubject
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task(priority: .utility) {
                    await self.persistHistoryDiff()
                }
            }
    }

    func loadHistoryFromRepository() async {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        await loadHistoryWhileLocked()
    }

    private func loadHistoryWhileLocked() async {
        isRepositoryReady = false
        guard let repository = repository else { return }
        let previousHistory = history

        do {
            let pinnedItems = try await repository.loadPinned()
            history = pinnedItems

            if !pinnedItems.isEmpty {
                rebuildContentLookup()
                markHistoryChanged()
                notifyHistoryObservers()
            }

            let fetchLimit = await initialLoadLimit(pinnedCount: pinnedItems.count)

            async let allItemsTask = repository.load(limit: fetchLimit)
            let loadedItems = try await allItemsTask

            let loadedByID = Dictionary(uniqueKeysWithValues: loadedItems.map { ($0.id, $0) })

            var combinedByID = loadedByID

            for pinned in pinnedItems {
                combinedByID[pinned.id] = loadedByID[pinned.id] ?? pinned
            }

            let combinedItems = combinedByID.values.sorted {
                $0.timestamp > $1.timestamp
            }

            history = combinedItems
            let loadedIDs = Set(combinedItems.map(\.id))
            let wasTrimmed = trimHistory()
            rebuildContentLookup()
            markHistoryChanged()

            if wasTrimmed {
                let retainedIDs = Set(history.map(\.id))
                let removedIDs = loadedIDs.subtracting(retainedIDs)
                if !removedIDs.isEmpty {
                    try await repository.applyChanges(inserted: [], updated: [], removed: Array(removedIDs))
                }
            }
            persistedSnapshot = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) })
            isRepositoryReady = true
            notifyHistoryObservers()
        } catch {
            history = previousHistory
            rebuildContentLookup()
            markHistoryChanged()
            notifyHistoryObservers()
            Logger.shared.error("Failed to load history: \(error)")
        }
    }

    private func initialLoadLimit(pinnedCount: Int) async -> Int {
        let configuredPinned = await MainActor.run {
            AppSettings.shared.maxPinnedItems
        }
        let headroom = 10
        let pinnedAllowance = max(configuredPinned, pinnedCount)
        let computedLimit = maxHistoryItems + pinnedAllowance + headroom
        return max(computedLimit, pinnedCount)
    }

    private func persistHistoryDiff() async {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        do {
            try await saveHistory(history)
        } catch {
            Logger.shared.error("History persistence failed")
        }
    }

    private func saveHistory(_ candidate: [ClipItem], record: MCPStoredReceipt? = nil) async throws {
        guard isRepositoryReady, let repository else { throw MCPFailure.persistence }
        let items = candidate
        let current = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let inserted = items.filter { persistedSnapshot[$0.id] == nil }
        let updated = items.filter { persistedSnapshot[$0.id] != nil && persistedSnapshot[$0.id] != $0 }
        let removed = persistedSnapshot.keys.filter { current[$0] == nil }
        if let record {
            guard let repository = repository as? SwiftDataRepository else { throw MCPFailure.persistence }
            try await repository.commitMCP(inserted: inserted, updated: updated, removed: removed, record: record)
        } else if current != persistedSnapshot {
            try await repository.applyChanges(inserted: inserted, updated: updated, removed: removed)
        }
        persistedSnapshot = current
    }

    // MARK: - Core Functionality

    func getHistory() async -> [ClipItem] {
        history
    }

    func getHistoryRevision() async -> UInt64 {
        historyRevision
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
        await copyToClipboard(content, fromEditor: fromEditor) { true }
    }

    @discardableResult
    func copyToClipboard(
        _ content: String,
        fromEditor: Bool,
        source: ClipMetadata.Source? = nil,
        shouldCopy: @Sendable () async -> Bool
    ) async -> Bool {
        let generation = copyGeneration
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard generation == copyGeneration, !Task.isCancelled, await shouldCopy() else { return false }
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return false }
        if !isRepositoryReady {
            await loadHistoryWhileLocked()
        }
        guard isRepositoryReady, !Task.isCancelled else { return false }

        // Mark as internal copy to avoid re-adding to history
        await state.setInternalCopy(true)
        await state.setFromEditor(fromEditor)

        // Get app info for metadata
        let appInfo = await MainActor.run {
            getActiveAppInfo()
        }

        // Add to history immediately with metadata
        let monitoringState = isMonitoringFlag
        let metadata = fromEditor ? appInfo : await MainActor.run { sanitizeExternalAppInfo(appInfo, isMonitoring: monitoringState) }
        var item = ClipItem(
            content: content,
            isPinned: false,
            kind: determineKind(for: content, isFromEditor: fromEditor),
            sourceApp: fromEditor ? "Kipple" : metadata.appName,
            windowTitle: fromEditor
                ? "Live Editor"
                : metadata.windowTitle,
            bundleIdentifier: fromEditor ? Bundle.main.bundleIdentifier : metadata.bundleId,
            processID: fromEditor ? ProcessInfo.processInfo.processIdentifier : metadata.pid,
            isFromEditor: fromEditor,
            metadata: source.map { ClipMetadata(createdAt: Date(), source: $0) }
        )
        // Preserve the history identity and details when copying the same text.
        if let existing = history.first(where: { $0.content == content }) {
            item.id = existing.id
            item.metadata = (item.metadata ?? ClipMetadata()).inheritingDetails(from: existing.metadata)
        }
        guard generation == copyGeneration, !Task.isCancelled, await shouldCopy() else {
            _ = await recordClipboardWrite(-1)
            return false
        }
        let newChangeCount = await writeClipboardItem(item)

        // Record the expected changeCount for this internal operation
        guard await recordClipboardWrite(newChangeCount) else { return false }

        addToHistory(item)
        return true
    }

    func writeToClipboardOnly(_ content: String) async {
        await writeToClipboardOnly(content) { true }
    }

    func writeToClipboardOnly(
        _ content: String,
        shouldWrite: @Sendable () async -> Bool
    ) async {
        let generation = copyGeneration
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard generation == copyGeneration, await shouldWrite() else { return }
        await state.setInternalCopy(true)
        await state.setFromEditor(true)

        let newChangeCount: Int
        if content.isEmpty {
            newChangeCount = await MainActor.run {
                autoreleasepool {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                return pasteboard.changeCount
                }
            }
        } else {
            let richText = await MainActor.run {
                let snapshot = (clipboardReader ?? .shared).read()
                return snapshot?.text == content ? snapshot?.richText : nil
            }
            let draft = ClipItem(content: content, isFromEditor: true, richText: richText)
            newChangeCount = await writeClipboardItem(draft)
        }

        guard await recordClipboardWrite(newChangeCount) else { return }
        updateLastChangeCount(newChangeCount)
    }

    @MainActor
    private static func currentPasteboardChangeCount() -> Int {
        autoreleasepool {
            NSPasteboard.general.changeCount
        }
    }

    func addEditorItems(_ contents: [String]) async -> [ClipItem] {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        let sanitized = contents
            .filter { !$0.isEmpty }

        guard !sanitized.isEmpty else { return [] }

        var createdItems: [ClipItem] = []
        createdItems.reserveCapacity(sanitized.count)

        for content in sanitized {
            let item = ClipItem(
                content: content,
                kind: determineKind(for: content, isFromEditor: true),
                sourceApp: "Kipple",
                windowTitle: "Live Editor",
                bundleIdentifier: Bundle.main.bundleIdentifier,
                processID: ProcessInfo.processInfo.processIdentifier,
                isFromEditor: true
            )
            createdItems.append(item)
        }

        for item in createdItems.reversed() {
            addToHistory(item)
        }

        return createdItems
    }

    func recopyFromHistory(_ item: ClipItem) async {
        await recopyFromHistory(item) { true }
    }

    func recopyFromHistory(_ item: ClipItem, shouldCopy: @Sendable () async -> Bool) async {
        let generation = copyGeneration
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard generation == copyGeneration, await shouldCopy() else { return }
        // Set flags BEFORE updating clipboard to prevent race condition
        await state.setInternalCopy(true)
        await state.setFromEditor(item.isFromEditor ?? false)

        let newItem = recordHistoryRecopy(item)
        // Keep pasteboard access on MainActor; its type cache must not be read concurrently.
        let newChangeCount = await writeClipboardItem(newItem)
        guard await recordClipboardWrite(newChangeCount) else { return }
    }

    @discardableResult
    private func recordHistoryRecopy(_ item: ClipItem) -> ClipItem {
        // Preserve all metadata from the original item but update timestamp
        var newItem = item
        newItem.timestamp = Date()  // Update timestamp to current time

        // Try to match by ID first to avoid expensive content comparisons
        if let existingIndex = history.firstIndex(where: { $0.id == item.id }) {
            let existingItem = history.remove(at: existingIndex)
            if existingItem.isPinned { newItem.isPinned = true }
            newItem.userCategoryId = existingItem.userCategoryId
            newItem.metadata = (newItem.metadata ?? ClipMetadata()).inheritingDetails(from: existingItem.metadata)
        } else if let duplicateIndex = indexOfExistingContent(item.content) {
            // Preserve pin state and user category from any remaining duplicate content
            let existingItem = history.remove(at: duplicateIndex)
            if existingItem.isPinned { newItem.isPinned = true }
            newItem.userCategoryId = existingItem.userCategoryId
            newItem.metadata = (newItem.metadata ?? ClipMetadata()).inheritingDetails(from: existingItem.metadata)
        }

        // Add item at the beginning with preserved metadata and new timestamp
        history.insert(newItem, at: 0)

        // Trim history to max size
        if trimHistory() {
            rebuildContentLookup()
        }
        itemIDByContent[newItem.content] = newItem.id

        // Trigger save
        markHistoryChanged()
        saveSubject.send(())

        return newItem
    }

    func clearSystemClipboard() async {
        await clearSystemClipboard { true }
    }

    func clearSystemClipboard(shouldClear: @Sendable () async -> Bool) async {
        let generation = copyGeneration
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard generation == copyGeneration, await shouldClear() else { return }
        let newChangeCount = await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.changeCount
        }

        await state.setInternalCopy(true)
        await state.setFromEditor(false)
        guard await recordClipboardWrite(newChangeCount) else { return }
        updateLastChangeCount(newChangeCount)
    }

    // MARK: - History Management

    func clearAllHistory() async {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        let pinnedItems = history.filter { $0.isPinned }
        history = pinnedItems
        autoPinCopySequence = nil
        rebuildContentLookup()

        // Save updated history to repository
        markHistoryChanged()
        saveSubject.send(())
        notifyHistoryObservers()
    }

    func clearHistory(keepPinned: Bool) async {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        if keepPinned {
            history = history.filter { $0.isPinned }
        } else {
            history.removeAll()
        }
        autoPinCopySequence = nil
        rebuildContentLookup()

        // Save updated history
        markHistoryChanged()
        saveSubject.send(())
        notifyHistoryObservers()
    }

    func togglePin(for item: ClipItem) async -> Bool {
        await mutationGate.acquire()
        defer { mutationGate.release() }
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
            markHistoryChanged()
            saveSubject.send(())
            notifyHistoryObservers()

            return isPinned
        }
        return false
    }

    func deleteItem(_ item: ClipItem) async {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        history.removeAll { $0.id == item.id }
        rebuildContentLookup()

        // Trigger save
        markHistoryChanged()
        saveSubject.send(())
        notifyHistoryObservers()
    }

    func updateItem(_ item: ClipItem) async {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            var updated = item
            updated.metadata = (item.metadata ?? ClipMetadata()).inheritingDetails(from: history[index].metadata)
            history[index] = updated
            rebuildContentLookup()

            // Trigger save
            markHistoryChanged()
            saveSubject.send(())
            notifyHistoryObservers()
        }
    }

    // MARK: - Search and Filter

    func searchHistory(query: String) async -> [ClipItem] {
        history.filter { item in
            item.matchesSearch(query)
        }
    }

    // MARK: - Status and Configuration

    func getCurrentClipboardContent() async -> String? {
        await MainActor.run { (clipboardReader ?? .shared).read()?.text }
    }

    func getCurrentInterval() async -> TimeInterval {
        currentInterval
    }

    func setMaxHistoryItems(_ max: Int) async {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        maxHistoryItems = max
        if trimHistory() {
            rebuildContentLookup()
            markHistoryChanged()
            saveSubject.send(())
            notifyHistoryObservers()
        }
    }

    func setInternalOperation(_ value: Bool) async {
        await state.setInternalCopy(value)
        if value { await state.setExpectedChangeCount(nil) }
    }

    func setExpectedChangeCount(_ value: Int?) async {
        await state.setExpectedChangeCount(value)
    }

    private func updateLastChangeCount(_ value: Int) {
        lastChangeCount = value
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
        await mutationGate.acquire()
        defer { mutationGate.release() }
        await checkClipboardWhileLocked()
    }

    @discardableResult
    private func checkClipboardWhileLocked(forceCapture: Bool = false) async -> Bool {
        guard isRepositoryReady else { return false }
        let observation = await MainActor.run { (clipboardReader ?? .shared).observation }
        let changeCount = observation.changeCount

        guard forceCapture || changeCount != lastChangeCount
                || observation.accessRevision != lastClipboardAccessRevision else { return true }

        if await shouldSkipChange(for: changeCount) { return true }

        let detectedAt = PerformanceTrace.nowMicros()

        // Get clipboard content
        let fetchStartedAt = PerformanceTrace.nowMicros()
        let captured = await MainActor.run {
            (clipboardReader ?? .shared).read()
        }
        // A copy arriving between the change-count check and capture must be retried as a whole.
        guard let captured, captured.stamp.changeCount == changeCount else { return false }
        lastChangeCount = changeCount
        lastClipboardAccessRevision = captured.stamp.accessRevision
        guard var item = await fetchClipboardItem(captured.text) else { return true }
        item.richText = captured.richText
        PerformanceTrace.event(
            "pasteboard_change_detected",
            atMicros: detectedAt,
            content: item.content,
            details: ["changeCount": "\(changeCount)"]
        )
        PerformanceTrace.event(
            "clipboard_item_fetched",
            content: item.content,
            details: ["fetchStartedAt": "\(fetchStartedAt)"]
        )

        if await shouldAutoPinExternalCopy(content: item.content, copiedAt: Date()) {
            item.isPinned = true
        }

        // Always add to history - addToHistory handles duplicates by moving them to top
        addToHistory(item)
        lastEventTime = Date()
        currentInterval = minInterval

        // Reset flags
        await state.setFromEditor(false)
        return true
    }

    private func addToHistory(_ item: ClipItem) {
        let updateStartedAt = PerformanceTrace.nowMicros()
        PerformanceTrace.event(
            "history_update_started",
            atMicros: updateStartedAt,
            content: item.content,
            count: history.count
        )

        // Check if an item with same content exists and preserve its pin state
        var newItem = item
        if let existingIndex = indexOfExistingContent(item.content) {
            let existingItem = history[existingIndex]
            newItem.id = existingItem.id
            newItem.metadata = (newItem.metadata ?? ClipMetadata()).inheritingDetails(from: existingItem.metadata)
            // Preserve pin state and user-assigned category from existing item
            if existingItem.isPinned { newItem.isPinned = true }
            newItem.userCategoryId = existingItem.userCategoryId
            // Remove the existing item
            history.remove(at: existingIndex)
        }

        // Add new item at the beginning
        history.insert(newItem, at: 0)

        // Trim history to max size
        if trimHistory() {
            rebuildContentLookup()
        }
        itemIDByContent[newItem.content] = newItem.id

        // Trigger save
        markHistoryChanged()
        PerformanceTrace.event(
            "history_update_finished",
            content: newItem.content,
            revision: historyRevision,
            count: history.count
        )
        saveSubject.send(())
        PerformanceTrace.event(
            "history_save_enqueued",
            content: newItem.content,
            revision: historyRevision,
            count: history.count
        )
        notifyHistoryObservers(content: newItem.content)
    }

    private func shouldAutoPinExternalCopy(content: String, copiedAt: Date) async -> Bool {
        let settings = await MainActor.run {
            (
                isEnabled: AppSettings.shared.autoPinRepeatedCopyEnabled,
                interval: AppSettings.shared.autoPinRepeatedCopyIntervalSeconds,
                requiredCount: AppSettings.shared.autoPinRepeatedCopyCount,
                maxPinnedItems: AppSettings.shared.maxPinnedItems
            )
        }

        guard settings.isEnabled else {
            autoPinCopySequence = nil
            return false
        }

        let currentSequence: AutoPinCopySequence
        if let sequence = autoPinCopySequence,
           sequence.content == content,
           copiedAt.timeIntervalSince(sequence.firstCopiedAt) <= TimeInterval(settings.interval) {
            currentSequence = AutoPinCopySequence(
                content: content,
                firstCopiedAt: sequence.firstCopiedAt,
                count: sequence.count + 1
            )
        } else {
            currentSequence = AutoPinCopySequence(
                content: content,
                firstCopiedAt: copiedAt,
                count: 1
            )
        }

        guard currentSequence.count >= settings.requiredCount else {
            autoPinCopySequence = currentSequence
            return false
        }

        autoPinCopySequence = nil

        if let existingIndex = indexOfExistingContent(content),
           history[existingIndex].isPinned {
            return true
        }

        let pinnedCount = history.reduce(into: 0) { count, item in
            if item.isPinned {
                count += 1
            }
        }
        guard pinnedCount < settings.maxPinnedItems else {
            Logger.shared.log(
                "Cannot auto-pin item: Maximum pinned items limit (\(settings.maxPinnedItems)) reached",
                level: .warning
            )
            return false
        }

        return true
    }

    private func shouldSkipChange(for changeCount: Int) async -> Bool {
        let expectedChangeCount = await state.getExpectedChangeCount()
        if let expected = expectedChangeCount {
            if changeCount == expected {
                lastChangeCount = changeCount
                await state.setExpectedChangeCount(nil)
                await state.setInternalCopy(false)
                await state.setFromEditor(false)
                return true
            }

            if changeCount < expected {
                lastChangeCount = changeCount
                return true
            }

            if changeCount > expected {
                await state.setExpectedChangeCount(nil)
                await state.setInternalCopy(false)
                await state.setFromEditor(false)
            }
        }

        let isInternalCopy = await state.getInternalCopy()
        if isInternalCopy {
            lastChangeCount = changeCount
            await state.setInternalCopy(false)
            await state.setFromEditor(false)
            await state.setExpectedChangeCount(nil)
            return true
        }

        return false
    }

    private func fetchClipboardItem(_ clipboardContent: String?) async -> ClipItem? {
        guard let content = clipboardContent,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if await state.getInternalCopy() {
                return nil
            }
            await state.setInternalCopy(false)
            await state.setFromEditor(false)
            return nil
        }

        let appInfo = await MainActor.run {
            getActiveAppInfo()
        }

        let isFromEditor = await state.getFromEditor()
        let monitoringState = isMonitoringFlag
        let metadata = isFromEditor ? appInfo : await MainActor.run {
            sanitizeExternalAppInfo(appInfo, isMonitoring: monitoringState)
        }

        return ClipItem(
            content: content,
            kind: determineKind(for: content, isFromEditor: isFromEditor),
            sourceApp: isFromEditor ? "Kipple" : metadata.appName,
            windowTitle: isFromEditor
                ? "Live Editor"
                : metadata.windowTitle,
            bundleIdentifier: isFromEditor ? Bundle.main.bundleIdentifier : metadata.bundleId,
            processID: isFromEditor ? ProcessInfo.processInfo.processIdentifier : metadata.pid,
            isFromEditor: isFromEditor
        )
    }

    // MARK: - Flush Pending Saves

    func flushPendingSaves() async {
        await persistHistoryDiff()
    }

    func saveBeforeTermination() async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        try Task.checkCancellation()
        try await saveHistory(history)
        try Task.checkCancellation()
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
    private func sanitizeExternalAppInfo(_ info: ActiveAppInfo, isMonitoring: Bool) -> ActiveAppInfo {
        let bundleIdentifier = Bundle.main.bundleIdentifier
        let isKipple = info.bundleId == bundleIdentifier || info.appName == "Kipple"
        guard isKipple else { return info }

        let fallback = LastActiveAppTracker.shared.getSourceAppInfo()
        if fallback.bundleId != bundleIdentifier && fallback.name != "Kipple" {
            let title = getWindowTitle(for: fallback.pid)
            return ActiveAppInfo(
                appName: fallback.name,
                windowTitle: title,
                bundleId: fallback.bundleId,
                pid: fallback.pid
            )
        }

        guard isMonitoring else { return info }

        let syntheticPid = info.pid == 0 ? -1 : info.pid
        return ActiveAppInfo(
            appName: info.appName == "Kipple"
                ? "External Source"
                : info.appName,
            windowTitle: info.windowTitle,
            bundleId: info.bundleId == bundleIdentifier ? "external.app" : info.bundleId,
            pid: syntheticPid
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

    @discardableResult
    private func trimHistory() -> Bool {
        guard history.count > maxHistoryItems else { return false }

        let totalPinned = history.reduce(into: 0) { count, item in
            if item.isPinned { count += 1 }
        }
        let allowedPinned = min(totalPinned, maxHistoryItems)
        let allowedUnpinned = max(0, maxHistoryItems - allowedPinned)

        var trimmed: [ClipItem] = []
        trimmed.reserveCapacity(maxHistoryItems)

        var pinnedAdded = 0
        var unpinnedAdded = 0

        for item in history {
            if item.isPinned {
                if pinnedAdded < allowedPinned {
                    trimmed.append(item)
                    pinnedAdded += 1
                }
            } else if unpinnedAdded < allowedUnpinned {
                trimmed.append(item)
                unpinnedAdded += 1
            }

            if trimmed.count == maxHistoryItems {
                break
            }
        }

        if trimmed != history {
            history = trimmed
            return true
        }

        return false
    }

    private func notifyHistoryObservers(content: String? = nil) {
        Task { @MainActor in
            PerformanceTrace.event("history_notification_posted", content: content)
            NotificationCenter.default.post(name: .modernClipboardHistoryDidChange, object: nil)
        }
    }

    private func markHistoryChanged() {
        historyRevision &+= 1
    }

    private func rebuildContentLookup() {
        var lookup: [String: UUID] = [:]
        lookup.reserveCapacity(history.count)
        for item in history where lookup[item.content] == nil {
            lookup[item.content] = item.id
        }
        itemIDByContent = lookup
    }

    private func indexOfExistingContent(_ content: String) -> Int? {
        if let existingID = itemIDByContent[content],
           let existingIndex = history.firstIndex(where: { $0.id == existingID }) {
            return existingIndex
        }
        return history.firstIndex { $0.content == content }
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

    private func determineKind(for content: String, isFromEditor: Bool) -> ClipItemKind {
        let category = CategoryClassifier.shared.classify(content: content, isFromEditor: isFromEditor)
        switch category {
        case .url:
            return .url
        case .all:
            return .text
        }
    }
}

#if DEBUG
extension ModernClipboardService {
    func checkClipboardForTesting() async {
        await checkClipboard()
    }

    func addExternalClipboardItemForTesting(_ content: String, copiedAt: Date = Date()) async {
        var item = ClipItem(
            content: content,
            kind: determineKind(for: content, isFromEditor: false),
            sourceApp: "External Source",
            windowTitle: nil,
            bundleIdentifier: "external.app",
            processID: -1,
            isFromEditor: false
        )

        if await shouldAutoPinExternalCopy(content: item.content, copiedAt: copiedAt) {
            item.isPinned = true
        }

        addToHistory(item)
    }

    func resetAutoPinSequenceForTesting() async {
        autoPinCopySequence = nil
    }

    func reloadHistoryForTesting() async {
        await initializeRepository()
        await loadHistoryFromRepository()
    }

    func clearRepositoryForTesting() async {
        guard let repository else { return }
        do {
            try await repository.clear()
            persistedSnapshot = [:]
        } catch {
            Logger.shared.error("Failed to clear repository: \(error)")
        }
    }
}
#endif

// swiftlint:enable type_body_length

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

extension ModernClipboardService {
    /// Save the original representations before stripping them from the system clipboard.
    /// The operation returns its own write count so monitoring never replaces the rich history with plain text.
    /// Returns false when the original clipboard cannot be backed up safely.
    func performClipboardPaste(
        of queuedItem: ClipItem? = nil,
        _ operation: @MainActor @Sendable (ClipItem, Int) -> Int?
    ) async -> Bool {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard !Task.isCancelled else { return true }
        // A failed initial load must not discard the only remaining copy of rich text.
        guard !isMonitoringFlag || isRepositoryReady else { return false }
        let expectedChangeCount = await Self.currentPasteboardChangeCount()
        if isMonitoringFlag {
            // Startup normally ignores the pre-existing clipboard; save it before the first plain-text paste.
            guard await checkClipboardWhileLocked(
                forceCapture: initialClipboardChangeCount == expectedChangeCount
            ) else { return false }
        }
        let captured = await MainActor.run { (clipboardReader ?? .shared).read() }
        guard queuedItem != nil || captured != nil else { return false }
        let writtenChangeCount = await MainActor.run { () -> Int? in
            let pasteboard = NSPasteboard.general
            guard !Task.isCancelled, pasteboard.changeCount == expectedChangeCount else { return nil }
            let item: ClipItem
            if let queuedItem {
                item = queuedItem
            } else {
                guard let captured, captured.stamp.changeCount == expectedChangeCount,
                      let content = captured.text, !content.isEmpty else { return nil }
                item = ClipItem(content: content)
            }
            return operation(item, expectedChangeCount)
        }
        if let writtenChangeCount {
            updateLastChangeCount(writtenChangeCount)
            _ = await recordClipboardWrite(writtenChangeCount)
            if let queuedItem { recordHistoryRecopy(queuedItem) }
        }
        return true
    }

    private func recordClipboardWrite(_ count: Int) async -> Bool {
        guard count >= 0 else {
            await state.setInternalCopy(false)
            await state.setFromEditor(false)
            await state.setExpectedChangeCount(nil)
            return false
        }
        await state.setExpectedChangeCount(count)
        return true
    }

    private func writeClipboardItem(
        _ item: ClipItem,
        shouldWrite: @MainActor @Sendable () -> Bool = { true }
    ) async -> Int {
        let writer = clipboardWriter
        let count = await MainActor.run { () -> Int in
            guard !Task.isCancelled, shouldWrite() else { return -1 }
            return writer(item)
        }
        if count >= 0 { lastChangeCount = count }
        return count
    }

    @MainActor
    private static func writeSystemClipboard(_ item: ClipItem) -> Int {
        ClipboardRichText.write(item, to: .general)
    }

    func previousReceipt(key: String) async throws -> MCPStoredReceipt? {
        for _ in 0..<50 where !isRepositoryReady {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let repository = repository as? SwiftDataRepository else { throw MCPFailure.unavailable }
        return try await repository.receipt(for: key)
    }

    func updateDetails(id: UUID, title: String?) async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard let index = history.firstIndex(where: { $0.id == id }) else { throw MCPFailure.invalidInput }
        var item = history[index]
        var metadata = item.metadata ?? ClipMetadata()
        metadata.title = try MCPInputValidation.title(title)
        item.metadata = metadata
        var candidate = history
        candidate[index] = item
        try await saveHistory(candidate)
        history = candidate
        markHistoryChanged()
        notifyHistoryObservers()
    }

    func setCategory(itemID: UUID, categoryID: UUID, enabled: Bool) async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard let index = history.firstIndex(where: { $0.id == itemID }) else { throw MCPFailure.invalidInput }
        var candidate = history
        candidate[index].setCategory(categoryID, enabled: enabled)
        try await saveHistory(candidate)
        history = candidate
        markHistoryChanged()
        notifyHistoryObservers()
    }

    func removeCategoryDefinition(_ id: UUID) async throws {
        guard id != BuiltInCategory.none, !BuiltInCategory.automatic.contains(id) else {
            throw MCPFailure.invalidInput
        }
        await mutationGate.acquire()
        defer { mutationGate.release() }
        var candidate = history
        for index in candidate.indices { candidate[index].removeCategoryDefinition(id) }
        try await saveHistory(candidate)
        history = candidate
        markHistoryChanged()
        notifyHistoryObservers()
    }

    func copyMCPConfiguration(
        _ content: String,
        shouldCopy: @MainActor @Sendable () -> Bool
    ) async -> Bool {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard !Task.isCancelled, await shouldCopy() else { return false }
        copyGeneration &+= 1
        await MainActor.run { NotificationCenter.default.post(name: .mcpWillCopy, object: nil) }
        let count = await writeClipboardItem(ClipItem(content: content), shouldWrite: shouldCopy)
        guard count >= 0 else { return false }
        await state.setInternalCopy(true)
        return await recordClipboardWrite(count)
    }

    func registerMCP(
        _ items: [ClipItem],
        record: MCPStoredReceipt,
        isEnabled: @escaping @MainActor @Sendable () -> Bool = { true }
    ) async throws -> MCPReceipt {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard isRepositoryReady, let repository = repository as? SwiftDataRepository else {
            throw MCPFailure.unavailable
        }
        guard await isEnabled() else { return .failure(record.result.requestId, code: "INTEGRATION_DISABLED") }
        if let previous = try await repository.receipt(for: record.key) {
            return previous.replay(digest: record.digest)
        }
        let mutation = try MCPHistoryMutation(items: items, history: history, capacity: maxHistoryItems)
        let registered = mutation.registered
        let candidate = mutation.candidate
        var receipt = record
        receipt.result.items = registered.enumerated().map { .init(id: $0.element.id, inputIndex: $0.offset) }
        receipt.result.clipboardItemId = registered.first?.id
        receipt.result.status = "clipboard_unknown"
        receipt.result.clipboardWrite = "unknown"
        guard await isEnabled() else { return .failure(record.result.requestId, code: "INTEGRATION_DISABLED") }
        try await saveHistory(candidate, record: receipt)
        history = candidate
        rebuildContentLookup()
        markHistoryChanged()
        copyGeneration &+= 1
        await MainActor.run {
            NotificationCenter.default.post(name: .mcpWillCopy, object: nil)
        }
        if let first = registered.first {
            let count = await writeClipboardItem(first, shouldWrite: isEnabled)
            receipt.result.clipboardWrite = count >= 0 ? "written" : "failed"
            receipt.result.status = count >= 0 ? "completed" : "clipboard_failed"
            await state.setInternalCopy(true)
            _ = await recordClipboardWrite(count)
        } else {
            receipt.result.status = "clipboard_failed"
            receipt.result.clipboardWrite = "failed"
        }
        notifyHistoryObservers()
        do { try await repository.updateReceipt(receipt) } catch {
            receipt.result.status = "clipboard_unknown"
            receipt.result.clipboardWrite = "unknown"
        }
        return receipt.result
    }
}

extension Notification.Name {
    static let mcpWillCopy = Notification.Name("KippleMCPWillCopy")
}
