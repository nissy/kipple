import Foundation
import AppKit
import Combine

// swiftlint:disable type_body_length file_length

extension Notification.Name {
    static let modernClipboardHistoryDidChange = Notification.Name("ModernClipboardServiceHistoryDidChange")
    static let historyTextLimitExceeded = Notification.Name("KippleHistoryTextLimitExceeded")
    static let desktopNoteRequestedByRepeatedCopy = Notification.Name("DesktopNoteRequestedByRepeatedCopy")
}

enum ClipItemEditError: Error {
    case itemUnavailable
    case invalidTitle
    case emptyContent
    case contentTooLong
    case duplicateContent
    case categoryUnavailable
    case richTextLossRequiresConfirmation
}

// MARK: - Modern Clipboard Service (Actor-based)

actor ModernClipboardService: ModernClipboardServiceProtocol {
    private struct RepeatedCopySequence {
        let content: String
        let firstCopiedAt: ContinuousClock.Instant
        let settingRevision: UInt64
        var count = 1
    }

    struct QueueHeadChange {
        let revision: UInt64
        let itemID: UUID?
    }

    struct HistorySnapshot {
        let items: [ClipItem]
        let revision: UInt64
        let isLoaded: Bool
        let lastQueueHeadChange: QueueHeadChange?
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
    private var categoryStore: UserCategoryStore?
    private var definedCustomCategoryIDs: Set<UUID>?
    private var desktopNoteItemIDs: Set<UUID> = []
    private var repeatedCopySequence: RepeatedCopySequence?

    // Repository for persistence
    private var repository: ClipboardRepositoryProtocol?
    private let saveSubject = PassthroughSubject<Void, Never>()
    private var saveCancellable: AnyCancellable?
    private var persistedSnapshot: [UUID: ClipItem] = [:]
    private var historyRevision: UInt64 = 0
    private var lastQueueHeadChange: QueueHeadChange?
    private var itemIDByContent: [String: UUID] = [:]

    // MARK: - Singleton

    static let shared = ModernClipboardService()

    // MARK: - Initialization

    #if DEBUG
    init(
        testRepository: ClipboardRepositoryProtocol,
        loadOnStartup: Bool = false,
        categoryStore: UserCategoryStore? = nil,
        desktopNoteItemIDs: Set<UUID> = [],
        clipboardWriter: @escaping @MainActor @Sendable (ClipItem) -> Int = writeSystemClipboard,
        clipboardReader: ClipboardReader? = nil
    ) {
        mutationGate = AsyncMutationGate(initiallyOccupied: loadOnStartup)
        self.clipboardWriter = clipboardWriter
        self.clipboardReader = clipboardReader
        self.categoryStore = categoryStore
        self.desktopNoteItemIDs = desktopNoteItemIDs
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
        desktopNoteItemIDs = Set(DesktopNotePlacement.load(from: .standard).keys)
        Task { await initializeService(categoryStore: UserCategoryStore.shared) }
    }

    private func initializeService(categoryStore: UserCategoryStore? = nil) async {
        defer { mutationGate.release() }
        if let categoryStore { self.categoryStore = categoryStore }
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
            if let categoryStore {
                definedCustomCategoryIDs = Set(await categoryStore.userDefined().map(\.id))
            }
            let categorizedItems = try await repository.loadCategorized()
            let liveNoteItems = previousHistory.filter { desktopNoteItemIDs.contains($0.id) }
            let storedNoteItems = try await repository.load(ids: desktopNoteItemIDs.subtracting(liveNoteItems.map(\.id)))
            let desktopNoteItems = storedNoteItems + liveNoteItems
            let protectedByID = Dictionary((categorizedItems + desktopNoteItems).map { ($0.id, $0) }) { _, latest in latest }
            history = protectedByID.values.map(withDefinedCategories)
                .filter(isProtectedFromHistoryRemoval)
                .sorted { $0.timestamp > $1.timestamp }

            if !history.isEmpty {
                rebuildContentLookup()
                markHistoryChanged()
                notifyHistoryObservers()
            }

            let fetchLimit = max(0, maxHistoryItems) + history.count + 10
            let recentItems = try await repository.load(limit: fetchLimit)
            let loadedByID = Dictionary((categorizedItems + storedNoteItems + recentItems).map { ($0.id, $0) }) { _, latest in
                latest
            }
            let combinedByID = loadedByID.merging(desktopNoteItems.map { ($0.id, $0) }) { _, current in current }
            let combinedItems = combinedByID.values.sorted { $0.timestamp > $1.timestamp }

            history = combinedItems.map(withDefinedCategories)
            let wasTrimmed = trimHistory()
            rebuildContentLookup()
            markHistoryChanged()

            let filledLoadWindow = recentItems.count == fetchLimit
            if wasTrimmed || filledLoadWindow {
                let storedIDs = filledLoadWindow ? try await repository.loadItemIDs() : Set(combinedByID.keys)
                try await removeTrimmedItems(storedIDs, from: repository)
            }
            persistedSnapshot = history.reduce(into: [:]) { snapshot, item in
                snapshot[item.id] = loadedByID[item.id] ?? persistedSnapshot[item.id]
            }
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

    private func removeTrimmedItems(_ storedIDs: Set<UUID>, from repository: ClipboardRepositoryProtocol) async throws {
        let removedIDs = storedIDs.subtracting(history.map(\.id))
        guard !removedIDs.isEmpty else { return }
        try await repository.applyChanges(inserted: [], updated: [], removed: Array(removedIDs))
    }

    private func withDefinedCategories(_ item: ClipItem) -> ClipItem {
        guard let definedCustomCategoryIDs else { return item }
        var updated = item
        updated.removeUndefinedCategories(definedIDs: definedCustomCategoryIDs)
        return updated
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

    private func saveHistory(
        _ candidate: [ClipItem], record: MCPStoredReceipt? = nil, additionallyRemoving: Set<UUID> = []
    ) async throws {
        guard isRepositoryReady, let repository else { throw MCPFailure.persistence }
        let items = candidate
        let current = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let inserted = items.filter { persistedSnapshot[$0.id] == nil }
        let updated = items.filter { persistedSnapshot[$0.id] != nil && persistedSnapshot[$0.id] != $0 }
        let removed = additionallyRemoving.union(persistedSnapshot.keys.filter { current[$0] == nil })
        if let record {
            guard let repository = repository as? SwiftDataRepository else { throw MCPFailure.persistence }
            try await repository.commitMCP(inserted: inserted, updated: updated, removed: Array(removed), record: record)
        } else if current != persistedSnapshot || !removed.isEmpty {
            try await repository.applyChanges(inserted: inserted, updated: updated, removed: Array(removed))
        }
        persistedSnapshot = current
    }

    // MARK: - Core Functionality

    func getHistory() async -> [ClipItem] {
        history
    }

    func getHistorySnapshot() -> HistorySnapshot {
        HistorySnapshot(
            items: history, revision: historyRevision, isLoaded: isRepositoryReady, lastQueueHeadChange: lastQueueHeadChange
        )
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
        repeatedCopySequence = nil

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
        await copyHistoryItem(content, fromEditor: fromEditor, source: source, shouldCopy: shouldCopy) != nil
    }

    func copyRecognizedText(_ content: String, shouldCopy: @Sendable () async -> Bool) async -> UUID? {
        await copyHistoryItem(content, fromEditor: false, source: .ocr, shouldCopy: shouldCopy)
    }

    private func copyHistoryItem(
        _ content: String,
        fromEditor: Bool,
        source: ClipMetadata.Source?,
        shouldCopy: @Sendable () async -> Bool
    ) async -> UUID? {
        let generation = copyGeneration
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard generation == copyGeneration, !Task.isCancelled, await shouldCopy() else { return nil }
        guard ClipboardTextLimit.allows(content) else {
            await notifyHistoryTextLimitExceeded()
            return nil
        }
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return nil }
        if !isRepositoryReady {
            await loadHistoryWhileLocked()
        }
        guard isRepositoryReady, !Task.isCancelled else { return nil }

        // Mark as internal copy to avoid re-adding to history
        await state.setInternalCopy(true)
        await state.setFromEditor(fromEditor)

        let monitoringState = isMonitoringFlag
        let app = await MainActor.run {
            fromEditor || source == .ocr ? nil : getActiveAppInfo(isMonitoring: monitoringState)
        }
        var item = ClipItem(
            content: content,
            kind: determineKind(for: content, isFromEditor: fromEditor),
            sourceApp: fromEditor ? "Kipple" : app?.name,
            windowTitle: fromEditor ? "Live Editor" : app?.windowTitle,
            bundleIdentifier: fromEditor ? Bundle.main.bundleIdentifier : app?.bundleID,
            processID: fromEditor ? ProcessInfo.processInfo.processIdentifier : app?.processID,
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
            return nil
        }
        let newChangeCount = await writeClipboardItem(item)

        // Record the expected changeCount for this internal operation
        guard await recordClipboardWrite(newChangeCount) else { return nil }

        return addToHistory(item)
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
        guard contents.allSatisfy(ClipboardTextLimit.allows) else {
            await notifyHistoryTextLimitExceeded()
            return []
        }
        let createdItems = contents
            .filter { !$0.isEmpty }
            .map { makeEditorItem(content: $0, windowTitle: "Live Editor") }

        for item in createdItems.reversed() {
            addToHistory(item)
        }

        return createdItems
    }

    private func makeEditorItem(content: String, windowTitle: String?) -> ClipItem {
        ClipItem(
            content: content,
            kind: determineKind(for: content, isFromEditor: true),
            sourceApp: "Kipple",
            windowTitle: windowTitle,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            processID: ProcessInfo.processInfo.processIdentifier,
            isFromEditor: true
        )
    }

    func recopyFromHistory(_ item: ClipItem) async {
        await recopyFromHistory(item) { true }
    }

    @discardableResult
    func recopyFromHistory(_ item: ClipItem, shouldCopy: @Sendable () async -> Bool) async -> Bool {
        let generation = copyGeneration
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard generation == copyGeneration, await shouldCopy() else { return false }
        // Set flags BEFORE updating clipboard to prevent race condition
        await state.setInternalCopy(true)
        await state.setFromEditor(item.isFromEditor ?? false)

        let newItem = recordHistoryRecopy(item)
        // Keep pasteboard access on MainActor; its type cache must not be read concurrently.
        let newChangeCount = await writeClipboardItem(newItem)
        return await recordClipboardWrite(newChangeCount)
    }

    @discardableResult
    private func recordHistoryRecopy(_ item: ClipItem) -> ClipItem {
        var newItem = item

        if let existingIndex = history.firstIndex(where: { $0.id == item.id }) {
            // A row or queue action can still hold a snapshot taken before the item was edited.
            newItem = history.remove(at: existingIndex)
        } else if let duplicateIndex = indexOfExistingContent(item.content) {
            let existingItem = history.remove(at: duplicateIndex)
            if desktopNoteItemIDs.contains(existingItem.id) || !ClipboardTextLimit.allows(item.content) {
                newItem = existingItem
            } else {
                newItem.userCategoryId = existingItem.userCategoryId
                newItem.metadata = (newItem.metadata ?? ClipMetadata()).inheritingDetails(from: existingItem.metadata)
            }
        } else if !ClipboardTextLimit.allows(item.content) {
            // Previously saved text can still be copied even if it has since left history.
            return item
        }

        // Add item at the beginning with preserved metadata and new timestamp
        newItem.timestamp = Date()
        newItem = withDefinedCategories(newItem)
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

    func protectHistoryForDesktopNote(_ itemID: UUID) async -> ClipItem? {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard let item = history.first(where: { $0.id == itemID }),
              desktopNoteItemIDs.insert(itemID).inserted else { return nil }
        return item
    }

    func desktopNoteItemsToRestore(_ ids: Set<UUID>) async -> [ClipItem]? {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard isRepositoryReady else { return nil }
        let items = history.filter { ids.contains($0.id) && desktopNoteItemIDs.contains($0.id) }
        desktopNoteItemIDs.subtract(ids.subtracting(items.map(\.id)))
        return items
    }

    func removeDesktopNoteProtection(_ itemID: UUID) async {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        desktopNoteItemIDs.remove(itemID)
    }

    private func isProtectedFromHistoryRemoval(_ item: ClipItem) -> Bool {
        item.hasCustomCategory || desktopNoteItemIDs.contains(item.id)
    }

    @discardableResult
    func clearHistory(keepingCategories: Bool) async -> Result<Int, Error> {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        if !isRepositoryReady { await loadHistoryWhileLocked() }
        guard isRepositoryReady, let repository else { return .failure(MCPFailure.persistence) }

        let retained = history.filter { item in
            desktopNoteItemIDs.contains(item.id) || (keepingCategories && item.hasCustomCategory)
        }
        let retainedIDs = Set(retained.map(\.id))
        do {
            let storedIDs = try await repository.loadItemIDs()
            let removedIDs = storedIDs.subtracting(retainedIDs)
            try await saveHistory(retained, additionallyRemoving: removedIDs)

            let clearedCount = removedIDs.union(history.map(\.id)).subtracting(retainedIDs).count
            history = retained
            repeatedCopySequence = nil
            rebuildContentLookup()
            markHistoryChanged()
            notifyHistoryObservers()
            return .success(clearedCount)
        } catch {
            Logger.shared.error("Failed to clear history: \(error)")
            return .failure(error)
        }
    }

    func deleteItem(_ item: ClipItem) async {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard let index = history.firstIndex(where: { $0.id == item.id }),
              !isProtectedFromHistoryRemoval(history[index]) else { return }
        history.remove(at: index)
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
            guard ClipboardTextLimit.allows(item.content) || history[index].content.utf8.elementsEqual(item.content.utf8) else {
                await notifyHistoryTextLimitExceeded()
                return
            }
            var updated = item
            updated.metadata = (item.metadata ?? ClipMetadata()).inheritingDetails(from: history[index].metadata)
            history[index] = withDefinedCategories(updated)
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
        await mutationGate.acquire()
        defer { mutationGate.release() }
        return await MainActor.run { (clipboardReader ?? .shared).read()?.text }
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
        let isNewWrite = changeCount != lastChangeCount

        guard forceCapture || isNewWrite
                || observation.accessRevision != lastClipboardAccessRevision else { return true }

        if await shouldSkipChange(for: changeCount) { return true }

        let copiedAt = ContinuousClock.now
        let detectedAt = PerformanceTrace.nowMicros()

        // Get clipboard content
        let fetchStartedAt = PerformanceTrace.nowMicros()
        let reader = await MainActor.run { clipboardReader ?? .shared }
        let captured = await reader.readForHistory(changeCount: changeCount)
        // A copy arriving between the change-count check and capture must be retried as a whole.
        guard let captured, captured.stamp.changeCount == changeCount else { return false }
        lastChangeCount = changeCount
        lastClipboardAccessRevision = captured.stamp.accessRevision
        guard !captured.shouldExcludeFromHistory,
              let item = await fetchClipboardItem(captured, reportsLimit: isNewWrite) else {
            if isNewWrite { repeatedCopySequence = nil }
            return true
        }
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

        // Always add to history - addToHistory handles duplicates by moving them to top
        let itemID = addToHistory(item)
        if isNewWrite {
            await trackRepeatedCopy(of: item, itemID: itemID, at: copiedAt)
        }
        lastEventTime = Date()
        currentInterval = minInterval

        // Reset flags
        await state.setFromEditor(false)
        return true
    }

    private func trackRepeatedCopy(of item: ClipItem, itemID: UUID, at copiedAt: ContinuousClock.Instant) async {
        // The clipboard changed, but native copies from Kipple views may bypass its clipboard service.
        guard item.isFromEditor != true, item.processID != ProcessInfo.processInfo.processIdentifier,
              Bundle.main.bundleIdentifier.map({ item.bundleIdentifier != $0 }) ?? true else { return }
        let revision = await MainActor.run {
            let settings = AppSettings.shared
            return settings.desktopNoteOnRepeatedCopy ? settings.desktopNoteRepeatedCopySettingRevision : nil
        }
        guard let revision else {
            repeatedCopySequence = nil
            return
        }
        guard var sequence = repeatedCopySequence, sequence.content == item.content,
              sequence.settingRevision == revision, copiedAt - sequence.firstCopiedAt <= .seconds(5) else {
            repeatedCopySequence = RepeatedCopySequence(
                content: item.content, firstCopiedAt: copiedAt, settingRevision: revision
            )
            return
        }
        sequence.count += 1
        if sequence.count < 3 {
            repeatedCopySequence = sequence
        } else {
            repeatedCopySequence = nil
            Task { @MainActor in
                let settings = AppSettings.shared
                guard settings.desktopNoteOnRepeatedCopy,
                      settings.desktopNoteRepeatedCopySettingRevision == revision else { return }
                NotificationCenter.default.post(
                    name: .desktopNoteRequestedByRepeatedCopy, object: self, userInfo: ["itemID": itemID]
                )
            }
        }
    }

    @discardableResult
    private func addToHistory(_ item: ClipItem) -> UUID {
        let updateStartedAt = PerformanceTrace.nowMicros()
        PerformanceTrace.event(
            "history_update_started",
            atMicros: updateStartedAt,
            content: item.content,
            count: history.count
        )

        // Check if an item with same content exists and preserve its categories
        var newItem = item
        if let existingIndex = indexOfExistingContent(item.content) {
            let existingItem = history[existingIndex]
            newItem.id = existingItem.id
            newItem.metadata = (newItem.metadata ?? ClipMetadata()).inheritingDetails(from: existingItem.metadata)
            // Preserve the user-assigned category from existing item
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
        return newItem.id
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

    private func fetchClipboardItem(_ captured: ClipboardReader.Snapshot, reportsLimit: Bool) async -> ClipItem? {
        if let text = captured.text, !ClipboardTextLimit.allows(text) {
            await state.setFromEditor(false)
            if reportsLimit { await notifyHistoryTextLimitExceeded() }
            return nil
        }
        guard let content = captured.text,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if await state.getInternalCopy() {
                return nil
            }
            await state.setInternalCopy(false)
            await state.setFromEditor(false)
            return nil
        }

        let isFromEditor = await state.getFromEditor()
        let source = captured.source
        var item = ClipItem(
            content: content,
            kind: determineKind(for: content, isFromEditor: isFromEditor),
            sourceApp: isFromEditor ? "Kipple" : source?.name,
            windowTitle: isFromEditor ? "Live Editor" : source?.windowTitle,
            bundleIdentifier: isFromEditor ? Bundle.main.bundleIdentifier : source?.bundleID,
            processID: isFromEditor ? ProcessInfo.processInfo.processIdentifier : source?.processID,
            isFromEditor: isFromEditor,
            richText: captured.richText
        )
        item.metadata?.sourceURI = captured.sourceURI
        return item
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

    @MainActor
    private func getActiveAppInfo(isMonitoring: Bool) -> ClipboardReader.Source? {
        let app = LastActiveAppTracker.shared.getSourceAppInfo()
        let isKipple = app.bundleId == Bundle.main.bundleIdentifier || app.name == "Kipple"
        guard app.pid > 0, !isMonitoring || !isKipple else { return nil }
        return ClipboardReader.Source(
            name: app.name,
            bundleID: app.bundleId,
            processID: app.pid,
            windowTitle: LastActiveAppTracker.singleVisibleWindowTitle(for: app.pid)
        )
    }

    @discardableResult
    private func trimHistory() -> Bool {
        let trimmed = historyWithinLimit(history)
        guard trimmed.count < history.count else { return false }
        history = trimmed
        return true
    }

    private func historyWithinLimit(_ items: [ClipItem]) -> [ClipItem] {
        guard items.count > maxHistoryItems else { return items }
        var available = maxHistoryItems
        return items.filter { item in
            if isProtectedFromHistoryRemoval(item) { return true }
            guard available > 0 else { return false }
            available -= 1
            return true
        }
    }

    private func notifyHistoryObservers(content: String? = nil) {
        Task { @MainActor in
            PerformanceTrace.event("history_notification_posted", content: content)
            NotificationCenter.default.post(name: .modernClipboardHistoryDidChange, object: nil)
        }
    }

    private func notifyHistoryTextLimitExceeded() async {
        await MainActor.run { NotificationCenter.default.post(name: .historyTextLimitExceeded, object: self) }
    }

    private func markHistoryChanged(checkQueueHead: Bool = true) {
        historyRevision &+= 1
        if checkQueueHead {
            lastQueueHeadChange = QueueHeadChange(revision: historyRevision, itemID: history.first?.id)
        }
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
    func setCategoryStoreForTesting(_ store: UserCategoryStore) async {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        categoryStore = store
        definedCustomCategoryIDs = Set(await store.userDefined().map(\.id))
    }

    func checkClipboardForTesting() async {
        await checkClipboard()
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
    /// Hold history polling and Kipple writes until the comparison copy is resolved.
    func performClipboardComparison(
        at stamp: ClipboardReader.Stamp,
        _ capture: @MainActor @Sendable () async -> ComparisonClipboardCopy.Result
    ) async -> ComparisonClipboardCopy.Result {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        let reader = await MainActor.run { clipboardReader ?? .shared }
        guard !Task.isCancelled, await reader.observation == stamp else { return .interrupted }
        if isMonitoringFlag, !(await checkClipboardWhileLocked()) {
            return await reader.observation == stamp ? .clipboardUnavailable : .interrupted
        }
        let result = await capture()
        if case .restored(_, let restored, _) = result {
            lastChangeCount = restored.changeCount
            lastClipboardAccessRevision = restored.accessRevision
            _ = await recordClipboardWrite(restored.changeCount)
        }
        return result
    }

    /// Serialize a paste with pending copies and preserve the current clipboard in history before a queue write.
    /// The operation returns the clipboard revision it used, whether or not it wrote a queued item.
    /// Returns false when history or clipboard contents cannot be read safely.
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
        let currentQueuedItem = queuedItem.map { queued in history.first { $0.id == queued.id } ?? queued }
        guard currentQueuedItem != nil || captured != nil else { return false }
        let writtenChangeCount = await MainActor.run { () -> Int? in
            let pasteboard = NSPasteboard.general
            guard !Task.isCancelled, pasteboard.changeCount == expectedChangeCount else { return nil }
            let item: ClipItem
            if let currentQueuedItem {
                item = currentQueuedItem
            } else {
                guard let captured, captured.stamp.changeCount == expectedChangeCount,
                      let content = captured.text, !content.isEmpty else { return nil }
                item = ClipItem(content: content, richText: captured.richText)
            }
            return operation(item, expectedChangeCount)
        }
        if let writtenChangeCount {
            updateLastChangeCount(writtenChangeCount)
            _ = await recordClipboardWrite(writtenChangeCount)
            if let currentQueuedItem { recordHistoryRecopy(currentQueuedItem) }
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

    func createHistoryItem(title: String?, content: String, categoryChanges: [UUID: Bool]) async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard !content.isEmpty else { throw ClipItemEditError.emptyContent }
        guard ClipboardTextLimit.allows(content) else { throw ClipItemEditError.contentTooLong }
        guard indexOfExistingContent(content) == nil else { throw ClipItemEditError.duplicateContent }
        let draft = makeEditorItem(content: content, windowTitle: nil)
        let item = try await itemApplyingDetails(draft, title: title, categoryChanges: categoryChanges)
        let candidate = historyWithinLimit([item] + history)
        guard candidate.first?.id == item.id else { throw MCPFailure.capacity }
        try await saveHistory(candidate)
        history = candidate
        rebuildContentLookup()
        markHistoryChanged(checkQueueHead: false)
        notifyHistoryObservers(content: item.content)
    }

    // Pass only the changed fields. An empty title clears the saved title.
    func updateDetails(
        id: UUID,
        title: String? = nil,
        content: String? = nil,
        categoryChanges: [UUID: Bool] = [:],
        allowsRemovingRichText: Bool = true
    ) async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard let index = history.firstIndex(where: { $0.id == id }) else { throw ClipItemEditError.itemUnavailable }
        let original = history[index]
        var item = original
        if let content, content != original.content {
            guard !content.isEmpty else { throw ClipItemEditError.emptyContent }
            guard ClipboardTextLimit.allows(content) else { throw ClipItemEditError.contentTooLong }
            if let duplicate = indexOfExistingContent(content), duplicate != index {
                throw ClipItemEditError.duplicateContent
            }
            guard allowsRemovingRichText || original.richText == nil else {
                throw ClipItemEditError.richTextLossRequiresConfirmation
            }
            item = item.replacingContent(with: content)
        }
        item = try await itemApplyingDetails(item, title: title, categoryChanges: categoryChanges)
        guard item != original else { return }
        var candidate = history
        candidate[index] = item
        try await saveHistory(candidate)
        history = candidate
        if item.content != original.content { rebuildContentLookup() }
        markHistoryChanged()
        notifyHistoryObservers()
    }

    private func itemApplyingDetails(_ original: ClipItem, title: String?, categoryChanges: [UUID: Bool]) async throws -> ClipItem {
        var item = original
        if let title {
            var metadata = item.metadata ?? ClipMetadata()
            do {
                metadata.title = try MCPInputValidation.title(title)
            } catch {
                throw ClipItemEditError.invalidTitle
            }
            item.metadata = metadata
        }
        let addedCategories = Set(categoryChanges.compactMap { id, enabled in enabled ? id : nil })
        guard await areCustomCategoriesDefined(addedCategories) else { throw ClipItemEditError.categoryUnavailable }
        for (id, enabled) in categoryChanges {
            item.setCategory(id, enabled: enabled)
        }
        return item
    }

    private func areCustomCategoriesDefined(_ ids: Set<UUID>) async -> Bool {
        let customIDs = ids.filter(BuiltInCategory.isCustom)
        guard !customIDs.isEmpty, let categoryStore else { return true }
        let definedIDs = Set(await categoryStore.userDefined().map(\.id))
        guard customIDs.isSubset(of: definedIDs) else { return false }
        definedCustomCategoryIDs = definedIDs
        return true
    }

    func setCategory(itemID: UUID, categoryID: UUID, enabled: Bool) async throws {
        try await updateCategories(itemID: itemID, change: .set(categoryID, enabled: enabled))
    }

    func updateCategories(itemID: UUID, change: ClipCategoryChange) async throws {
        await mutationGate.acquire()
        defer { mutationGate.release() }
        guard let index = history.firstIndex(where: { $0.id == itemID }) else { throw MCPFailure.invalidInput }
        var candidate = history
        switch change {
        case let .set(id, enabled):
            if enabled, !(await areCustomCategoriesDefined([id])) { throw MCPFailure.invalidInput }
            candidate[index].setCategory(id, enabled: enabled)
        case .clear: candidate[index].clearCategories()
        }
        try await saveHistory(candidate)
        history = candidate
        markHistoryChanged()
        notifyHistoryObservers()
    }

    func removeCategoryDefinition(_ id: UUID) async throws {
        guard BuiltInCategory.isCustom(id) else {
            throw MCPFailure.invalidInput
        }
        await mutationGate.acquire()
        defer { mutationGate.release() }
        var candidate = history
        for index in candidate.indices { candidate[index].removeCategoryDefinition(id) }
        try await saveHistory(candidate)
        history = candidate
        definedCustomCategoryIDs?.remove(id)
        markHistoryChanged()
        await categoryStore?.remove(id: id)
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
        let mutation = try MCPHistoryMutation(
            items: items, history: history, capacity: maxHistoryItems, isProtected: isProtectedFromHistoryRemoval
        )
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
