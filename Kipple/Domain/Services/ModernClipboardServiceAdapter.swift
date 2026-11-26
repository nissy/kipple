import Foundation
import AppKit
import Combine

// MARK: - Modern Clipboard Service Adapter

/// Adapter to bridge ModernClipboardService (Actor) with existing ClipboardServiceProtocol
@MainActor
final class ModernClipboardServiceAdapter: ObservableObject, ClipboardServiceProtocol {
    // MARK: - Published Properties

    @Published var history: [ClipItem] = []
    @Published var currentClipboardContent: String?

    // MARK: - Properties

    private let modernService: ModernClipboardService
    private let refreshGate = AsyncMutationGate()
    private var refreshTask: Task<Void, Never>?
    private var operationGeneration: UInt64 = 0
    var copyEpoch: UInt64 { operationGeneration }
    private var pendingOperationTask: Task<Void, Never>?
    private var pendingClipboardContent: String?
    private var lastKnownHistoryRevision: UInt64?
    private var lastKnownQueueHeadRevision: UInt64?
    private(set) var publishedQueueHeadChange: ModernClipboardService.QueueHeadChange?
    private(set) var isHistoryLoaded = false

    // ClipboardServiceProtocol requirement
    var onHistoryChanged: ((ClipItem) -> Void)?

    // MARK: - Singleton

    static let shared = ModernClipboardServiceAdapter()

    // MARK: - Initialization

    init(modernService: ModernClipboardService = .shared, refreshPeriodically: Bool = true) {
        self.modernService = modernService
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(historyDidChange(_:)),
            name: .modernClipboardHistoryDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(mcpWillCopy(_:)), name: .mcpWillCopy, object: nil
        )
        if refreshPeriodically { startPeriodicRefresh() }
    }

    @objc private func mcpWillCopy(_ notification: Notification) {
        operationGeneration &+= 1
        pendingOperationTask?.cancel()
        pendingClipboardContent = nil
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
        enqueueClipboardOperation { [self] generation in
            await modernService.copyToClipboard(content, fromEditor: fromEditor) {
                await self.isCurrentOperation(generation)
            }
            await refreshHistory()
        }
    }

    func writeToClipboardOnly(_ content: String) {
        pendingClipboardContent = content
        currentClipboardContent = content.isEmpty ? nil : content
        enqueueClipboardOperation { [self] generation in
            await modernService.writeToClipboardOnly(content) {
                await self.isCurrentOperation(generation)
            }
        }
    }

    func copyRecognizedText(_ content: String) async -> UUID? {
        guard !Task.isCancelled else { return nil }
        var itemID: UUID?
        let task = enqueueClipboardOperation { [self] generation in
            itemID = await modernService.copyRecognizedText(content) {
                await self.isCurrentOperation(generation) && !Task.isCancelled
            }
            await refreshHistory()
        }
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        return Task.isCancelled ? nil : itemID
    }

    func performClipboardPaste(
        of queuedItem: ClipItem? = nil,
        _ operation: @escaping @MainActor @Sendable (ClipItem, Int) -> Int?
    ) async -> Bool {
        var backupAvailable = true
        await enqueueClipboardOperation { [self] generation in
            guard isCurrentOperation(generation) else { return }
            backupAvailable = await modernService.performClipboardPaste(of: queuedItem) { item, changeCount in
                guard self.isCurrentOperation(generation), !Task.isCancelled else { return nil }
                return operation(item, changeCount)
            }
            await refreshHistory()
        }.value
        return backupAvailable
    }

    func createHistoryItem(title: String?, content: String, categoryChanges: [UUID: Bool]) async throws {
        try await modernService.createHistoryItem(title: title, content: content, categoryChanges: categoryChanges)
        await refreshHistory()
    }

    func updateDetails(
        itemID: UUID, title: String?, content: String?, categoryChanges: [UUID: Bool], allowsRemovingRichText: Bool = true
    ) async throws {
        try await modernService.updateDetails(
            id: itemID, title: title, content: content, categoryChanges: categoryChanges,
            allowsRemovingRichText: allowsRemovingRichText
        )
        await refreshHistory()
    }

    func updateCategories(itemID: UUID, change: ClipCategoryChange) async throws {
        try await modernService.updateCategories(itemID: itemID, change: change)
        await refreshHistory()
    }

    func removeCategoryDefinition(_ id: UUID) async throws {
        try await modernService.removeCategoryDefinition(id)
        await refreshHistory()
    }

    @discardableResult
    func addEditorItems(_ contents: [String]) async -> [ClipItem] {
        let items = await modernService.addEditorItems(contents)
        await refreshHistory()
        return items
    }

    func recopyFromHistory(_ item: ClipItem) {
        enqueueRecopy(item)
    }

    func recopyFromHistory(_ item: ClipItem, onSuccess: @escaping () -> Void) {
        enqueueRecopy(item, onSuccess: onSuccess)
    }

    func clearSystemClipboard() async {
        await enqueueClipboardOperation { [self] generation in
            await modernService.clearSystemClipboard { await self.isCurrentOperation(generation) }
            guard generation == operationGeneration else { return }
            pendingClipboardContent = nil
            currentClipboardContent = nil
            await refreshHistory()
        }.value
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

    func protectHistoryForDesktopNote(_ itemID: UUID) async -> ClipItem? {
        await modernService.protectHistoryForDesktopNote(itemID)
    }

    var repeatedCopyDesktopNoteRequests: AnyPublisher<UUID, Never> {
        NotificationCenter.default.publisher(for: .desktopNoteRequestedByRepeatedCopy, object: modernService)
            .compactMap { $0.userInfo?["itemID"] as? UUID }
            .eraseToAnyPublisher()
    }

    func desktopNoteItemsToRestore(_ ids: Set<UUID>) async -> [ClipItem]? {
        await modernService.desktopNoteItemsToRestore(ids)
    }

    func removeDesktopNoteProtection(_ itemID: UUID) async {
        await modernService.removeDesktopNoteProtection(itemID)
    }

    @discardableResult
    func clearHistory(keepingCategories: Bool) async -> Result<Int, Error> {
        let result = await modernService.clearHistory(keepingCategories: keepingCategories)
        await refreshHistory()
        return result
    }

    func updateItem(_ item: ClipItem) async {
        await modernService.updateItem(item)
        await refreshHistory()
    }

    func flushPendingSaves() async {
        await pendingOperationTask?.value
        await modernService.flushPendingSaves()
    }

    func saveBeforeTermination() async throws {
        let wasMonitoring = await modernService.isMonitoring()
        await modernService.stopMonitoring()
        do {
            await pendingOperationTask?.value
            try await modernService.saveBeforeTermination()
        } catch {
            if wasMonitoring { await modernService.startMonitoring() }
            throw error
        }
    }

    func searchHistory(_ query: String) -> [ClipItem] {
        // Synchronous search on current cached history
        history.filter { item in
            item.matchesSearch(query)
        }
    }

    func searchHistoryAsync(_ query: String) async -> [ClipItem] {
        await modernService.searchHistory(query: query)
    }

    // MARK: - Private Methods

    @discardableResult
    private func enqueueClipboardOperation(
        _ operation: @escaping @MainActor (UInt64) async -> Void
    ) -> Task<Void, Never> {
        let generation = operationGeneration
        let previous = pendingOperationTask
        let task = Task {
            await previous?.value
            guard generation == operationGeneration, !Task.isCancelled else { return }
            await operation(generation)
        }
        pendingOperationTask = task
        return task
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
        await refreshGate.acquire()
        defer { refreshGate.release() }
        let previousClipboardContent = currentClipboardContent
        let newCurrentContent = await modernService.getCurrentClipboardContent()
        let snapshot = await modernService.getHistorySnapshot()

        if lastKnownHistoryRevision != snapshot.revision || isHistoryLoaded != snapshot.isLoaded {
            let newRevision = snapshot.revision
            let newHistory = snapshot.items
            PerformanceTrace.event("adapter_refresh_started", revision: newRevision)
            PerformanceTrace.event(
                "adapter_history_will_publish",
                content: newHistory.first?.content,
                revision: newRevision,
                count: newHistory.count
            )
            isHistoryLoaded = snapshot.isLoaded
            // A refresh can include both a clipboard copy and a manual history addition.
            let queueHeadChange = snapshot.lastQueueHeadChange
            publishedQueueHeadChange = queueHeadChange?.revision == lastKnownQueueHeadRevision ? nil : queueHeadChange
            lastKnownQueueHeadRevision = queueHeadChange?.revision
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
        pendingOperationTask?.cancel()
        pendingOperationTask = nil
        isHistoryLoaded = false
        publishedQueueHeadChange = nil
        lastKnownQueueHeadRevision = nil
        history = []
        currentClipboardContent = nil
        pendingClipboardContent = nil
        lastKnownHistoryRevision = nil

        // Ensure we are in sync with the service after it resets.
        await refreshHistory()
        startPeriodicRefresh()
    }

    func flushPendingAdapterOperationForTesting() async {
        await pendingOperationTask?.value
    }

    func refreshHistoryForTesting() async {
        await refreshHistory()
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
        await enqueueRecopy(item).value
    }

    @discardableResult
    private func enqueueRecopy(_ item: ClipItem, onSuccess: (() -> Void)? = nil) -> Task<Void, Never> {
        prepareForRecopy(of: item)
        return enqueueClipboardOperation { [self] generation in
            let copied = await modernService.recopyFromHistory(item) { await self.isCurrentOperation(generation) }
            if copied, isCurrentOperation(generation), !Task.isCancelled { onSuccess?() }
            await refreshHistory()
        }
    }

    /// pasteboard 書き込みのみ待機する軽量版。history 再同期は後段で finalizeRecopyRefresh() を呼ぶこと
    func recopyFromHistoryAwaitingPasteboard(_ item: ClipItem) async {
        prepareForRecopy(of: item)
        await enqueueClipboardOperation { [self] generation in
            await modernService.recopyFromHistory(item) { await self.isCurrentOperation(generation) }
        }.value
    }

    /// recopyFromHistoryAwaitingPasteboard 後の history 再同期
    func finalizeRecopyRefresh() async {
        await refreshHistory()
    }

    private func isCurrentOperation(_ generation: UInt64) -> Bool { operationGeneration == generation }

    private func prepareForRecopy(of item: ClipItem) {
        pendingClipboardContent = item.content
        currentClipboardContent = pendingClipboardContent
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
