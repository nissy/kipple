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

// swiftlint:disable type_body_length file_length
@MainActor
class MainViewModel: ObservableObject, MainViewModelProtocol {
    enum PasteMode {
        case clipboard
        case queueOnce
        case queueToggle
    }

    @Published var editorText: String {
        didSet {
            // パフォーマンス最適化：デバウンスを使用して保存処理を遅延
            saveDebouncer.send(editorText)
        }
    }
    
    private let saveDebouncer = PassthroughSubject<String, Never>()
    
    let clipboardService: any ClipboardServiceProtocol
    private let pasteMonitor: any PasteCommandMonitoring
    private let screenCapturePermissionCheck: () -> Bool
    private var cancellables = Set<AnyCancellable>()
    private var serviceCancellables = Set<AnyCancellable>()
    
    @Published var history: [ClipItem] = []
    @Published var pinnedItems: [ClipItem] = []
    @Published var filteredHistory: [ClipItem] = []
    @Published var pinnedHistory: [ClipItem] = []
    @Published var searchText: String = "" {
        didSet {
            applyFilters()
        }
    }
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
    @Published var currentClipboardContent: String?

    // 自動消去タイマーの残り時間
    @Published var autoClearRemainingTime: TimeInterval?

    // ページネーション関連
    @Published private(set) var hasMoreHistory: Bool = false
    private let pageSize: Int
    private var currentHistoryLimit: Int = 0
    private var isLoadingMore = false
    private var lastQueueAnchorID: UUID?
    private var shouldResetAnchorOnNextShiftSelection = false
    private var filteredOrderingSnapshot: [ClipItem] = []
    private var isFilterMutating = false
    private var isPasteMonitorActive = false
    private var isShiftSelecting = false
    private var pendingShiftSelection: [ClipItem] = []
    private var shiftSelectionInitialQueue: [UUID] = []
    private var expectedQueueHeadID: UUID?
    private let appSettings = AppSettings.shared

    init(
        clipboardService: (any ClipboardServiceProtocol)? = nil,
        pageSize: Int = 50,
        pasteMonitor: any PasteCommandMonitoring = PasteCommandMonitor(),
        screenCapturePermissionCheck: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }
    ) {
        self.pageSize = max(1, pageSize)
        // 保存されたエディタテキストを読み込む（なければ空文字）
        self.editorText = UserDefaults.standard.string(forKey: "lastEditorText") ?? ""
        // Use provided service or get default service
        if let service = clipboardService {
            self.clipboardService = service
        } else {
            // Fallback to default service
            self.clipboardService = ClipboardServiceProvider.resolve()
        }
        self.pasteMonitor = pasteMonitor
        self.screenCapturePermissionCheck = screenCapturePermissionCheck

        // デバウンスされた保存処理を設定
        saveDebouncer
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] text in
                if !text.isEmpty {
                    UserDefaults.standard.set(text, forKey: "lastEditorText")
                } else {
                    UserDefaults.standard.removeObject(forKey: "lastEditorText")
                }
            }
            .store(in: &cancellables)
        
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
        currentClipboardContent = self.clipboardService.currentClipboardContent
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
                self?.currentClipboardContent = content
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

    private func applyFilters() {
        guard !isFilterMutating else { return }
        updateFilteredItems(clipboardService.history, animated: true)
    }

    func updateFilteredItems(_ items: [ClipItem], animated: Bool = false) {
        var filtered = items

        if !searchText.isEmpty {
            filtered = filtered.filter { item in
                item.content.localizedCaseInsensitiveContains(searchText) ||
                (item.sourceApp?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        if let userCatId = selectedUserCategoryId {
            let noneId = UserCategoryStore.shared.noneCategoryId()
            if userCatId == noneId {
                filtered = filtered.filter { $0.userCategoryId == nil || $0.userCategoryId == userCatId }
            } else {
                filtered = filtered.filter { $0.userCategoryId == userCatId }
            }
        } else if let category = selectedCategory, category != .all {
            filtered = filtered.filter { $0.category == category }
        }

        if showOnlyURLs {
            filtered = filtered.filter { $0.category == .url }
        }

        if showOnlyPinned || isPinnedFilterActive {
            filtered = filtered.filter { $0.isPinned }
        }

        let queueOrdered = applyQueueOrdering(to: filtered)
        let shouldPaginate = searchText.isEmpty && !isPinnedFilterActive && !showOnlyPinned
        let newCurrentHistoryLimit = shouldPaginate ? min(pageSize, queueOrdered.count) : queueOrdered.count
        let newHistory = Array(queueOrdered.prefix(newCurrentHistoryLimit))
        let newHasMoreHistory = newHistory.count < queueOrdered.count
        let newPinnedItems = isPinnedFilterActive ? queueOrdered : []
        let newPinnedHistory = items.filter { $0.isPinned }

        let applyState = { [self] in
            pinnedHistory = newPinnedHistory
            filteredOrderingSnapshot = queueOrdered
            filteredHistory = queueOrdered
            currentHistoryLimit = newCurrentHistoryLimit
            history = newHistory
            hasMoreHistory = newHasMoreHistory
            pinnedItems = newPinnedItems
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                applyState()
            }
        } else {
            applyState()
        }
    }

    func loadMoreHistoryIfNeeded(currentItem: ClipItem) {
        guard history.count < filteredHistory.count else { return }
        guard !isLoadingMore else { return }
        guard let lastItem = history.last, lastItem.id == currentItem.id else { return }

        isLoadingMore = true
        let newLimit = min(history.count + pageSize, filteredHistory.count)
        currentHistoryLimit = newLimit
        history = Array(filteredHistory.prefix(currentHistoryLimit))
        hasMoreHistory = history.count < filteredHistory.count
        isLoadingMore = false
    }

    func copyEditor() {
        if !editorText.isEmpty {
            clipboardService.copyToClipboard(editorText, fromEditor: true)
            // コピー後にテキストをクリア
            editorText = ""
            UserDefaults.standard.removeObject(forKey: "lastEditorText")
        }
    }
    
    func clearEditor() {
        editorText = ""
        UserDefaults.standard.removeObject(forKey: "lastEditorText")
    }
    
    // These are now async methods above, keeping for backward compatibility
    func togglePinSync(for item: ClipItem) -> Bool {
        return clipboardService.togglePin(for: item)
    }

    func deleteItemSync(_ item: ClipItem) {
        clipboardService.deleteItem(item)
    }
    
    // MARK: - Editor Insert Functions
    
    /// エディタに内容を挿入（既存内容をクリア）
    func insertToEditor(content: String) {
        // 同期的に処理（非同期は不要）
        editorText = content
    }
    
    /// 設定された修飾キーを取得
    func getEditorInsertModifiers() -> NSEvent.ModifierFlags {
        let rawValue = UserDefaults.standard.integer(forKey: "editorInsertModifiers")
        return NSEvent.ModifierFlags(rawValue: UInt(rawValue))
    }
    
    /// 現在の修飾キーがエディタ挿入用かチェック
    func shouldInsertToEditor() -> Bool {
        guard appSettings.editorPosition != "disabled" else { return false }
        let currentModifiers = NSEvent.modifierFlags
        let requiredModifiers = getEditorInsertModifiers()
        // None(=0) のときは無効
        if requiredModifiers.isEmpty { return false }
        // 必要な修飾キーがすべて押されているかチェック
        return currentModifiers.intersection(requiredModifiers) == requiredModifiers
    }
    
    /// 履歴アイテム選択（修飾キー検出対応）
    func selectHistoryItem(_ item: ClipItem, forceInsert: Bool = false) {
        if forceInsert || shouldInsertToEditor() {
            insertToEditor(content: item.content)
        } else {
            clipboardService.recopyFromHistory(item)
            resetFiltersAfterCopy()
            clearQueueAfterManualCopyIfNeeded()
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
        updateFilteredItems(clipboardService.history, animated: didMutate)
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
