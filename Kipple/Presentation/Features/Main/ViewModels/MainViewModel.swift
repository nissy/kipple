//
//  MainViewModel.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import Foundation
import SwiftUI
import CoreGraphics
import Combine
import AppKit

// swiftlint:disable type_body_length file_length
@MainActor
final class MainViewModel: ObservableObject, MainViewModelProtocol {
    enum PasteMode {
        case clipboard
        case queueOnce
        case queueToggle
    }

    private struct PaginationFilterState: Equatable {
        let searchText: String
        let showOnlyURLs: Bool
        let showOnlyPinned: Bool
        let selectedCategory: ClipItemCategory?
        let selectedUserCategoryId: UUID?
        let isPinnedFilterActive: Bool
    }

    @Published var editorText: String {
        didSet {
            guard !isApplyingClipboardContentToEditor else { return }
            scheduleLiveEditorClipboardWrite(editorText)
        }
    }
    
    let clipboardService: any ClipboardServiceProtocol
    private let pasteMonitor: any PasteCommandMonitoring
    private let screenCapturePermissionCheck: () -> Bool
    private var cancellables = Set<AnyCancellable>()
    private var serviceCancellables = Set<AnyCancellable>()
    
    @Published var history: [ClipItem] = []
    var pinnedItems: [ClipItem] = []
    var filteredHistory: [ClipItem] = []
    var pinnedHistory: [ClipItem] = []
    @Published var searchText: String = "" {
        didSet {
            // resetFiltersAfterCopy 等のフィルタ一括変更中は coalesce を schedule しない
            // （schedule すると close 後に遅延発火して focus 復帰と競合する）
            guard !isFilterMutating else { return }
            scheduleSearchFilterCoalesce()
        }
    }
    private var searchCoalesceTask: Task<Void, Never>?
    @Published var showOnlyURLs: Bool = false
    @Published var showOnlyPinned: Bool = false {
        didSet {
            applyFilters()
        }
    }
    @Published var selectedCategory: ClipItemCategory?
    @Published var selectedUserCategoryId: UUID?
    @Published var isPinnedFilterActive: Bool = false
    @Published private(set) var pasteMode: PasteMode = .clipboard
    @Published private(set) var pasteQueue: [UUID] = []
    @Published private(set) var queueSelectionPreview: Set<UUID> = []
    
    // 現在のクリップボードコンテンツを公開
    @Published var currentClipboardContent: String? {
        didSet {
            updateCurrentClipboardItemID()
        }
    }
    @Published private(set) var currentClipboardItemID: UUID?

    // 自動消去タイマーの残り時間
    @Published var autoClearRemainingTime: TimeInterval?

    // ページネーション関連
    @Published private(set) var hasMoreHistory: Bool = false
    @Published private(set) var isLoadingMoreHistory: Bool = false
    private let pageSize: Int
    private var currentHistoryLimit: Int = 0
    private var lastQueueAnchorID: UUID?
    private var shouldResetAnchorOnNextShiftSelection = false
    private var filteredOrderingSnapshot: [ClipItem] = []
    private var lastPaginationFilterState: PaginationFilterState?
    private var isFilterMutating = false
    private var isPasteMonitorActive = false
    private var isShiftSelecting = false
    private var pendingShiftSelection: [ClipItem] = []
    private var shiftSelectionInitialQueue: [UUID] = []
    private var expectedQueueHeadID: UUID?
    private var latestHistorySnapshot: [ClipItem] = []
    private var liveEditorWriteTask: Task<Void, Never>?
    private var isApplyingClipboardContentToEditor = false
    private static let newlineSet = CharacterSet.newlines

    init(
        clipboardService: (any ClipboardServiceProtocol)? = nil,
        pageSize: Int = 50,
        pasteMonitor: any PasteCommandMonitoring = PasteCommandMonitor(),
        screenCapturePermissionCheck: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }
    ) {
        self.pageSize = max(1, pageSize)
        let resolvedService = clipboardService ?? ClipboardServiceProvider.resolve()
        self.clipboardService = resolvedService
        self.editorText = resolvedService.currentClipboardContent ?? ""
        self.pasteMonitor = pasteMonitor
        self.screenCapturePermissionCheck = screenCapturePermissionCheck
        
        subscribeToClipboardService()

        // 特定の設定値の変更のみを監視（パフォーマンス最適化）
        // 注: UserDefaultsの変更通知は特定のキーを識別できないため、
        // debounceのみで処理頻度を制限
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // 設定値が変更されたら再フィルタリング
                self.updateFilteredItems(self.clipboardService.history)
            }
            .store(in: &cancellables)

        // 初回読み込み
        updateFilteredItems(self.clipboardService.history)
        currentClipboardContent = resolvedService.currentClipboardContent
    }

    private func subscribeToClipboardService() {
        if let modernService = clipboardService as? ModernClipboardServiceAdapter {
            bindModernService(modernService)
        }

        clipboardService.onHistoryChanged = { [weak self] item in
            guard let self else { return }
            self.handleExternalHistoryUpdate(newTopID: item.id)
            if !(self.clipboardService is ModernClipboardServiceAdapter) {
                self.updateFilteredItems(self.clipboardService.history)
            }
        }
    }

        private func bindModernService(_ service: ModernClipboardServiceAdapter) {
        serviceCancellables.removeAll()

        service.$history
            .sink { [weak self] items in
                guard let self = self else { return }
                self.handleExternalHistoryUpdate(newTopID: items.first?.id)
                self.updateFilteredItems(items)
            }
            .store(in: &serviceCancellables)

        service.$currentClipboardContent
            .sink { [weak self] content in
                self?.applyClipboardContentToEditor(content)
            }
            .store(in: &serviceCancellables)

        service.$autoClearRemainingTime
            .sink { [weak self] remainingTime in
                self?.autoClearRemainingTime = remainingTime
            }
            .store(in: &serviceCancellables)
    }
    
    func loadHistory() {
        let items = clipboardService.history
        updateFilteredItems(items)
    }

    func copyToClipboard(_ item: ClipItem) {
        clipboardService.copyToClipboard(item.content, fromEditor: false)
        applyClipboardContentToEditor(item.content)
        resetFiltersAfterCopy()
        clearQueueAfterManualCopyIfNeeded()
    }

    func clearHistory(keepPinned: Bool) async {
        if keepPinned {
            await clipboardService.clearHistory(keepPinned: true)
        } else {
            await clipboardService.clearAllHistory()
        }
        loadHistory()
    }

    func deleteItem(_ item: ClipItem) async {
        await clipboardService.deleteItem(item)
        loadHistory()
    }

    func togglePin(for item: ClipItem) async {
        _ = clipboardService.togglePin(for: item)
        loadHistory()
    }

    private func applyFilters(animated: Bool = true) {
        guard !isFilterMutating else { return }
        updateFilteredItems(clipboardService.history, animated: animated)
    }

    /// コピー開始時に呼ぶ。pending な検索 coalesce を確実に潰す
    /// （onClose 後に await が yield する間、満了済み task が走るのを防ぐ）
    func cancelPendingSearchFilter() {
        searchCoalesceTask?.cancel()
        searchCoalesceTask = nil
    }

    /// 検索入力の連続変化を 50ms で coalescing。コピー後の reset で cancel される必要があるため
    /// Task-based debounce で実装（Combine だと cancel しにくく、window close 後に発火して focus 競合を起こす）
    private func scheduleSearchFilterCoalesce() {
        searchCoalesceTask?.cancel()
        searchCoalesceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            guard let self, !self.isFilterMutating else { return }
            self.applyFilters(animated: false)
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func updateFilteredItems(_ items: [ClipItem], animated: Bool = false) {
        let tracedContent = items.first?.content
        PerformanceTrace.event("viewmodel_update_started", content: tracedContent, count: items.count)
        rebuildHistoryLookups(using: items)
        updateCurrentClipboardItemID()

        let searchQuery = searchText
        let hasSearchQuery = !searchQuery.isEmpty
        let selectedUserCategory = selectedUserCategoryId
        let activeCategory = selectedCategory
        let requireURLsOnly = showOnlyURLs
        let requirePinnedOnly = showOnlyPinned || isPinnedFilterActive

        let categoryStore = UserCategoryStore.shared
        let noneCategoryId = categoryStore.noneCategoryId()
        let urlCategoryId = categoryStore.urlCategoryId()
        let filterByURLCategory = (selectedUserCategory == nil) && (activeCategory == .url)

        // Fast-path: no filters and no queue ordering → avoid O(n) filter
        let noFiltersActive = !hasSearchQuery &&
                              selectedUserCategory == nil &&
                              activeCategory == nil &&
                              !requireURLsOnly &&
                              !requirePinnedOnly

        let filtered: [ClipItem]
        if noFiltersActive {
            filtered = items
        } else {
            // 安価な判定（Bool/UUID 比較）で早期 return し、最後に expensive な
            // localizedCaseInsensitiveContains を評価して総コストを下げる
            filtered = items.filter { item in
                if requirePinnedOnly && !item.isPinned {
                    return false
                }
                if let userCatId = selectedUserCategory {
                    if userCatId == noneCategoryId {
                        if let assignedId = item.userCategoryId, assignedId != userCatId {
                            return false
                        }
                    } else if item.userCategoryId != userCatId {
                        return false
                    }
                }
                if filterByURLCategory || requireURLsOnly {
                    if !itemBelongsToURLCategory(item, urlCategoryId: urlCategoryId) {
                        return false
                    }
                }
                if hasSearchQuery {
                    let matchesContent = item.content.localizedCaseInsensitiveContains(searchQuery)
                    let matchesSourceApp = item.sourceApp?.localizedCaseInsensitiveContains(searchQuery) ?? false
                    if !matchesContent && !matchesSourceApp {
                        return false
                    }
                }
                return true
            }
        }

        let queueOrdered = applyQueueOrdering(to: filtered)
        let shouldPaginate = searchText.isEmpty && !isPinnedFilterActive && !showOnlyPinned
        let paginationFilterState = PaginationFilterState(
            searchText: searchText,
            showOnlyURLs: showOnlyURLs,
            showOnlyPinned: showOnlyPinned,
            selectedCategory: selectedCategory,
            selectedUserCategoryId: selectedUserCategoryId,
            isPinnedFilterActive: isPinnedFilterActive
        )
        let shouldResetPagination = lastPaginationFilterState != paginationFilterState || currentHistoryLimit == 0
        let visibleLimit = shouldResetPagination ? pageSize : max(pageSize, currentHistoryLimit)
        let newCurrentHistoryLimit = shouldPaginate ? min(visibleLimit, queueOrdered.count) : queueOrdered.count
        let newHistory = Array(queueOrdered.prefix(newCurrentHistoryLimit))
        let newHasMoreHistory = newHistory.count < queueOrdered.count
        let newPinnedItems = isPinnedFilterActive ? queueOrdered : []
        let newPinnedHistory = items.filter { $0.isPinned }

        let applyState = { [self] in
            pinnedHistory = newPinnedHistory
            filteredOrderingSnapshot = queueOrdered
            filteredHistory = queueOrdered
            currentHistoryLimit = newCurrentHistoryLimit
            lastPaginationFilterState = paginationFilterState
            history = newHistory
            hasMoreHistory = newHasMoreHistory
            pinnedItems = newPinnedItems
            PerformanceTrace.event(
                "viewmodel_history_published",
                content: newHistory.first?.content,
                count: newHistory.count,
                details: ["filtered": "\(queueOrdered.count)"]
            )
        }

        let shouldAnimate = animated && newHistory.count <= filterAnimationThreshold

        if shouldAnimate {
            withAnimation(.easeInOut(duration: 0.2)) { applyState() }
        } else {
            applyState()
        }
    }

    private func rebuildHistoryLookups(using items: [ClipItem]) {
        latestHistorySnapshot = items
    }

    private func updateCurrentClipboardItemID() {
        guard let currentContent = currentClipboardContent,
              !currentContent.isEmpty else {
            if currentClipboardItemID != nil {
                currentClipboardItemID = nil
            }
            return
        }
        let matchedID = latestHistorySnapshot.first { $0.content == currentContent }?.id
        if currentClipboardItemID != matchedID {
            currentClipboardItemID = matchedID
        }
    }

    func loadMoreHistoryIfNeeded(currentItem: ClipItem) {
        guard history.count < filteredHistory.count else { return }
        guard !isLoadingMoreHistory else { return }
        guard let lastItem = history.last, lastItem.id == currentItem.id else { return }

        isLoadingMoreHistory = true
        defer { isLoadingMoreHistory = false }
        let newLimit = min(history.count + pageSize, filteredHistory.count)
        currentHistoryLimit = newLimit
        history = Array(filteredHistory.prefix(currentHistoryLimit))
        hasMoreHistory = history.count < filteredHistory.count
    }

    func copyEditor() {
        liveEditorWriteTask?.cancel()
        writeEditorTextToClipboardOnly(editorText)
    }

    @discardableResult
    func trimEditor() -> Bool {
        let trimmedLines = editorText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let leadingTrimmed = trimmedLines.drop { $0.isEmpty }
        let trailingTrimmed = leadingTrimmed
            .reversed()
            .drop { $0.isEmpty }
            .reversed()

        let normalizedText = trailingTrimmed.joined(separator: "\n")
        guard normalizedText != editorText else { return false }

        editorText = normalizedText
        return true
    }
    
    func clearEditor() {
        liveEditorWriteTask?.cancel()
        LiveEditorTextView.clearLocalClipboard()
        isApplyingClipboardContentToEditor = true
        editorText = ""
        isApplyingClipboardContentToEditor = false
        writeEditorTextToClipboardOnly("")
    }

    private func scheduleLiveEditorClipboardWrite(_ text: String) {
        liveEditorWriteTask?.cancel()
        let scheduledPasteboardChangeCount = NSPasteboard.general.changeCount
        liveEditorWriteTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            guard NSPasteboard.general.changeCount == scheduledPasteboardChangeCount else { return }
            self?.writeEditorTextToClipboardOnly(text)
        }
    }

    private func writeEditorTextToClipboardOnly(_ text: String) {
        clipboardService.writeToClipboardOnly(text)
        currentClipboardContent = text.isEmpty ? nil : text
    }

    private func applyClipboardContentToEditor(_ content: String?) {
        liveEditorWriteTask?.cancel()
        currentClipboardContent = content
        let text = content ?? ""
        guard editorText != text else { return }

        LiveEditorTextView.clearLocalClipboard()
        isApplyingClipboardContentToEditor = true
        editorText = text
        isApplyingClipboardContentToEditor = false
    }

    @discardableResult
    func saveEditorToHistory() async -> Int {
        let items = await clipboardService.addEditorItems([editorText])
        return items.count
    }

    @discardableResult
    func splitHistoryItemIntoHistory(_ item: ClipItem) async -> Int {
        await splitLinesIntoHistory(item.content)
    }
    
    // These are now async methods above, keeping for backward compatibility
    func togglePinSync(for item: ClipItem) -> Bool {
        return clipboardService.togglePin(for: item)
    }

    func deleteItemSync(_ item: ClipItem) {
        clipboardService.deleteItem(item)
    }

    func insertToEditor(content: String) {
        applyClipboardContentToEditor(content)
        writeEditorTextToClipboardOnly(content)
    }

    // MARK: - Private helpers

    private func splitLinesIntoHistory(_ text: String) async -> Int {
        let components = text
            .components(separatedBy: Self.newlineSet)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !components.isEmpty else { return 0 }

        let addedItems = await clipboardService.addEditorItems(components)

        if let first = addedItems.first {
            clipboardService.recopyFromHistory(first)
        }

        return addedItems.count
    }
    
    /// 設定された修飾キーを取得
    func getEditorInsertModifiers() -> NSEvent.ModifierFlags {
        []
    }
    
    /// 現在の修飾キーがエディタ挿入用かチェック
    func shouldInsertToEditor() -> Bool {
        false
    }
    
    /// 履歴アイテム選択（修飾キー検出対応）
    func selectHistoryItem(_ item: ClipItem, forceInsert _: Bool = false) {
        clipboardService.recopyFromHistory(item)
        applyClipboardContentToEditor(item.content)
        finalizeHistorySelection()
    }

    func selectHistoryItemAndWait(_ item: ClipItem, forceInsert _: Bool = false) async {
        if let asyncService = clipboardService as? ClipboardServiceAsyncRecopying {
            await asyncService.recopyFromHistoryAndWait(item)
        } else {
            clipboardService.recopyFromHistory(item)
        }
        applyClipboardContentToEditor(item.content)
        finalizeHistorySelection()
    }

    /// pasteboard 書き込み完了までだけ待機。history 再同期は finalizeRecopyRefresh() を別途呼ぶ
    func selectHistoryItemAwaitingPasteboard(_ item: ClipItem, forceInsert _: Bool = false) async {
        if let adapter = clipboardService as? ModernClipboardServiceAdapter {
            await adapter.recopyFromHistoryAwaitingPasteboard(item)
        } else if let asyncService = clipboardService as? ClipboardServiceAsyncRecopying {
            await asyncService.recopyFromHistoryAndWait(item)
        } else {
            clipboardService.recopyFromHistory(item)
        }
        applyClipboardContentToEditor(item.content)
        finalizeHistorySelection()
    }

    /// selectHistoryItemAwaitingPasteboard 後の history 再同期。window close 後の別 Task で呼ぶ
    func finalizeRecopyRefresh() async {
        if let adapter = clipboardService as? ModernClipboardServiceAdapter {
            await adapter.finalizeRecopyRefresh()
        }
    }
    
    /// カテゴリフィルタの切り替え
    func toggleCategoryFilter(_ category: ClipItemCategory) {
        if category == .all {
            // "All" カテゴリはフィルタをクリア
            selectedCategory = nil
            selectedUserCategoryId = nil
        } else if selectedCategory == category {
            selectedCategory = nil
        } else {
            selectedCategory = category
            // ユーザカテゴリフィルタは排他
            selectedUserCategoryId = nil
        }
        updateFilteredItems(clipboardService.history, animated: true)
    }
    
    /// ピンフィルタの切り替え
    func togglePinnedFilter() {
        isPinnedFilterActive.toggle()
        updateFilteredItems(clipboardService.history, animated: true)
    }

    /// ユーザカテゴリフィルタの切り替え（内製カテゴリとは排他）
    func toggleUserCategoryFilter(_ id: UUID) {
        if selectedUserCategoryId == id {
            selectedUserCategoryId = nil
        } else {
            selectedUserCategoryId = id
            selectedCategory = nil
        }
        updateFilteredItems(clipboardService.history, animated: true)
    }

    private func resetFiltersAfterCopy() {
        // window close 後に発火して focus 復帰と競合しないよう、検索 coalesce を必ず cancel
        searchCoalesceTask?.cancel()
        searchCoalesceTask = nil

        isFilterMutating = true
        var didMutate = false

        if !searchText.isEmpty {
            searchText = ""
            didMutate = true
        }
        if showOnlyURLs {
            showOnlyURLs = false
            didMutate = true
        }
        if showOnlyPinned {
            showOnlyPinned = false
            didMutate = true
        }
        if selectedCategory != nil {
            selectedCategory = nil
            didMutate = true
        }
        if selectedUserCategoryId != nil {
            selectedUserCategoryId = nil
            didMutate = true
        }
        if isPinnedFilterActive {
            isPinnedFilterActive = false
            didMutate = true
        }

        isFilterMutating = false
        guard didMutate else { return }
        updateFilteredItems(clipboardService.history, animated: false)
        // window close 後に発火して focus 復帰と競合しないよう、検索 coalesce を確実に cancel
        searchCoalesceTask?.cancel()
    }

    private func finalizeHistorySelection() {
        resetFiltersAfterCopy()
        clearQueueAfterManualCopyIfNeeded()
    }

    // MARK: - Paste Queue Management

    func queueSelection(items: [ClipItem], anchor: ClipItem?) {
        guard canUsePasteQueue else { return }
        guard isQueueModeActive else { return }
        guard !items.isEmpty else { return }

        let wasQueueEmpty = pasteQueue.isEmpty
        var updatedQueue = pasteQueue
        for item in items {
            if let existingIndex = updatedQueue.firstIndex(of: item.id) {
                updatedQueue.remove(at: existingIndex)
            }
            updatedQueue.append(item.id)
        }
        pasteQueue = updatedQueue

        if let anchor = anchor {
            lastQueueAnchorID = anchor.id
            shouldResetAnchorOnNextShiftSelection = false
        }

        updateFilteredItems(clipboardService.history)

        if !pasteQueue.isEmpty {
            if wasQueueEmpty {
                prepareNextQueueClipboard()
            }
            startPasteMonitoringIfNeeded()
        }
    }

    func handleQueueSelection(for item: ClipItem, modifiers: NSEvent.ModifierFlags) {
        guard canUsePasteQueue else { return }
        guard isQueueModeActive else { return }
        let normalized = modifiers.intersection(.deviceIndependentFlagsMask)
        isShiftSelecting = normalized.contains(.shift)

        let baselineItems = filteredOrderingSnapshot.isEmpty ? filteredHistory : filteredOrderingSnapshot

        guard let currentIndex = baselineItems.firstIndex(where: { $0.id == item.id }) else {
            queueSelection(items: [item], anchor: item)
            queueSelectionPreview = isShiftSelecting ? [item.id] : []
            pendingShiftSelection = isShiftSelecting ? [item] : []
            return
        }

        if isShiftSelecting {
            if pendingShiftSelection.isEmpty {
                shiftSelectionInitialQueue = pasteQueue
                if shouldResetAnchorOnNextShiftSelection ||
                    lastQueueAnchorID == nil ||
                    !baselineItems.contains(where: { $0.id == lastQueueAnchorID }) {
                    lastQueueAnchorID = item.id
                    shouldResetAnchorOnNextShiftSelection = false
                }
            }
            guard let anchorID = lastQueueAnchorID,
                  let anchorIndex = baselineItems.firstIndex(where: { $0.id == anchorID }) else {
                pendingShiftSelection = []
                queueSelectionPreview = []
                return
            }

            let selection = makeShiftSelectionRange(
                baselineItems: baselineItems,
                anchorIndex: anchorIndex,
                currentIndex: currentIndex
            )

            if selection.count == 1,
               let anchorID = lastQueueAnchorID,
               selection.first?.id == anchorID {
                queueSelectionPreview = Set([anchorID])
                pendingShiftSelection = []
                return
            }

            let selectionIDs = selection.map(\.id)

            pendingShiftSelection = selection
            queueSelectionPreview = Set(selectionIDs)
            return
        } else {
            pendingShiftSelection = []
            queueSelectionPreview = []
            toggleSingleItemSelection(item)
        }
    }

    func makeShiftSelectionRange(
        baselineItems: [ClipItem],
        anchorIndex: Int,
        currentIndex: Int
    ) -> [ClipItem] {
        guard !baselineItems.isEmpty else { return [] }
        guard baselineItems.indices.contains(anchorIndex),
              baselineItems.indices.contains(currentIndex) else {
            return []
        }

        if currentIndex >= anchorIndex {
            return Array(baselineItems[anchorIndex...currentIndex])
        } else {
            var ordered: [ClipItem] = []
            ordered.append(baselineItems[anchorIndex])
            if anchorIndex > currentIndex {
                for idx in stride(from: anchorIndex - 1, through: currentIndex, by: -1) {
                    ordered.append(baselineItems[idx])
                }
            }
            return ordered
        }
    }

    func queueBadge(for item: ClipItem) -> Int? {
        if let previewQueue = previewQueueOrder() {
            guard let index = previewQueue.firstIndex(of: item.id) else { return nil }
            return index + 1
        }
        guard let index = pasteQueue.firstIndex(of: item.id) else { return nil }
        return index + 1
    }

    func nextQueuedItem() -> ClipItem? {
        guard let firstID = pasteQueue.first else { return nil }
        return clipboardService.history.first { $0.id == firstID }
    }

    func toggleQueueMode() {
        guard canUsePasteQueue else {
            resetPasteQueue()
            return
        }
        if isQueueModeActive {
            resetPasteQueue()
        } else {
            pauseAutoClearIfNeeded()
            pasteMode = .queueOnce
            updateFilteredItems(clipboardService.history)
        }
    }

    func toggleQueueRepetition() {
        guard isQueueModeActive else { return }
        switch pasteMode {
        case .queueOnce:
            pasteMode = .queueToggle
        case .queueToggle:
            pasteMode = .queueOnce
        case .clipboard:
            return
        }
    }

    func resetPasteQueue() {
        guard !pasteQueue.isEmpty || pasteMode != .clipboard else { return }
        pasteQueue = []
        pasteMode = .clipboard
        lastQueueAnchorID = nil
        shouldResetAnchorOnNextShiftSelection = false
        expectedQueueHeadID = nil
        stopPasteMonitoring()
        pendingShiftSelection = []
        queueSelectionPreview = []
        resumeAutoClearIfNeeded()
        updateFilteredItems(clipboardService.history)
    }

    private let filterAnimationThreshold = 120

    private func itemBelongsToURLCategory(_ item: ClipItem, urlCategoryId: UUID) -> Bool {
        if let userCategoryId = item.userCategoryId {
            return userCategoryId == urlCategoryId
        }
        return item.category == .url
    }

    private func applyQueueOrdering(to items: [ClipItem]) -> [ClipItem] {
        guard !pasteQueue.isEmpty else { return items }

        var queueItems: [ClipItem] = []
        queueItems.reserveCapacity(pasteQueue.count)
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var seen = Set<UUID>()

        for id in pasteQueue {
            guard !seen.contains(id), let match = lookup[id] else { continue }
            queueItems.append(match)
            seen.insert(id)
        }

        guard !queueItems.isEmpty else { return items }

        let remaining = items.filter { !seen.contains($0.id) }
        return queueItems + remaining
    }

    private func startPasteMonitoringIfNeeded() {
        guard canUsePasteQueue else { return }
        guard !isPasteMonitorActive else { return }
        let started = pasteMonitor.start { [weak self] in
            Task { @MainActor in
                await self?.handlePasteCommandDetected()
            }
        }
        if started {
            isPasteMonitorActive = true
        }
    }

    private func stopPasteMonitoring() {
        guard isPasteMonitorActive else { return }
        pasteMonitor.stop()
        isPasteMonitorActive = false
    }

    private func handlePasteCommandDetected() async {
        guard !pasteQueue.isEmpty else {
            stopPasteMonitoring()
            return
        }

        let wasQueueToggle = pasteMode == .queueToggle
        let completedID = pasteQueue.removeFirst()

        if wasQueueToggle {
            pasteQueue.append(completedID)
        }

        if pasteQueue.isEmpty {
            if !wasQueueToggle {
                await clipboardService.clearSystemClipboard()
            }
            resetPasteQueue()
            return
        }

        updateFilteredItems(clipboardService.history)

        if pasteQueue.isEmpty {
            stopPasteMonitoring()
        } else {
            prepareNextQueueClipboard()
        }
    }

    private func prepareNextQueueClipboard() {
        guard canUsePasteQueue else {
            resetPasteQueue()
            return
        }
        guard let nextID = pasteQueue.first else {
            return
        }

        guard let nextItem = clipboardService.history.first(where: { $0.id == nextID }) else {
            pasteQueue.removeFirst()
            if pasteQueue.isEmpty {
                pasteMode = .clipboard
                stopPasteMonitoring()
                updateFilteredItems(clipboardService.history)
            } else {
                prepareNextQueueClipboard()
            }
            return
        }

        expectedQueueHeadID = nextItem.id
        clipboardService.recopyFromHistory(nextItem)
        applyClipboardContentToEditor(nextItem.content)
    }
}

extension MainViewModel {
    var canUsePasteQueue: Bool {
        pasteMonitor.hasAccessibilityPermission
    }

    var canUseScreenTextCapture: Bool {
        screenCapturePermissionCheck()
    }

    var isQueueModeActive: Bool {
        pasteMode != .clipboard
    }

    func handleModifierFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        let normalized = flags.intersection(.deviceIndependentFlagsMask)
        let shiftDown = normalized.contains(.shift)
        isShiftSelecting = shiftDown
        if shiftDown {
            if canUsePasteQueue,
               isQueueModeActive {
                shouldResetAnchorOnNextShiftSelection = true
            }
        } else {
            if canUsePasteQueue,
               isQueueModeActive,
               !pendingShiftSelection.isEmpty {
                commitPendingShiftSelection()
            }
            pendingShiftSelection = []
            queueSelectionPreview = []
            lastQueueAnchorID = nil
            shouldResetAnchorOnNextShiftSelection = false
        }
    }

    private func commitPendingShiftSelection() {
        let selection = pendingShiftSelection
        guard !selection.isEmpty else { return }
        guard isQueueModeActive else {
            pendingShiftSelection = []
            queueSelectionPreview = []
            return
        }

        let initialQueue = shiftSelectionInitialQueue
        let initialSet = Set(initialQueue)
        let orderedIDs = selection.map(\.id)

        let selectedSet = Set(orderedIDs)
        var updatedQueue = initialQueue.filter { !selectedSet.contains($0) }
        let newIDs = orderedIDs.filter { !initialSet.contains($0) }
        updatedQueue.append(contentsOf: newIDs)

        pasteQueue = updatedQueue
        shiftSelectionInitialQueue = updatedQueue

        if pasteQueue.isEmpty {
            resetPasteQueue()
        } else {
            updateFilteredItems(clipboardService.history)
            prepareNextQueueClipboard()
            startPasteMonitoringIfNeeded()
            if let last = selection.last, pasteQueue.contains(last.id) {
                lastQueueAnchorID = last.id
                shouldResetAnchorOnNextShiftSelection = false
            }
        }
    }

    private func toggleSingleItemSelection(_ item: ClipItem) {
        var updatedQueue = pasteQueue
        if let index = updatedQueue.firstIndex(of: item.id) {
            updatedQueue.remove(at: index)
        } else {
            updatedQueue.removeAll { $0 == item.id }
            updatedQueue.append(item.id)
        }
        pasteQueue = updatedQueue

        if pasteQueue.isEmpty {
            resetPasteQueue()
        } else {
            updateFilteredItems(clipboardService.history)
            prepareNextQueueClipboard()
            startPasteMonitoringIfNeeded()
            if pasteQueue.contains(item.id) {
                lastQueueAnchorID = item.id
            }
        }
    }

    private func previewQueueOrder() -> [UUID]? {
        guard isShiftSelecting,
              !pendingShiftSelection.isEmpty else {
            return nil
        }

        let orderedIDs = pendingShiftSelection.map(\.id)
        let initialQueue = shiftSelectionInitialQueue
        let initialSet = Set(initialQueue)
        let selectedSet = Set(orderedIDs)
        var previewQueue = initialQueue.filter { !selectedSet.contains($0) }
        let newIDs = orderedIDs.filter { !initialSet.contains($0) }
        previewQueue.append(contentsOf: newIDs)
        return previewQueue
    }

    private func pauseAutoClearIfNeeded() {
        (clipboardService as? QueueAutoClearControlling)?.pauseAutoClearForQueue()
    }

    private func resumeAutoClearIfNeeded() {
        (clipboardService as? QueueAutoClearControlling)?.resumeAutoClearAfterQueue()
    }

    private func clearQueueAfterManualCopyIfNeeded() {
        guard isQueueModeActive else { return }
        resetPasteQueue()
    }

    private func handleExternalHistoryUpdate(newTopID: UUID?) {
        guard isQueueModeActive else {
            expectedQueueHeadID = nil
            return
        }

        guard !pasteQueue.isEmpty else {
            expectedQueueHeadID = nil
            return
        }

        if let expected = expectedQueueHeadID {
            if expected == newTopID {
                expectedQueueHeadID = nil
                return
            }
        }

        if let newTopID, pasteQueue.contains(newTopID) {
            expectedQueueHeadID = nil
            return
        }

        expectedQueueHeadID = nil
        resetPasteQueue()
    }
}
// swiftlint:enable type_body_length file_length
