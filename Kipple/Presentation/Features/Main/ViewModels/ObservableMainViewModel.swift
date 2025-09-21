import SwiftUI
import Combine

@available(macOS 14.0, iOS 17.0, *)
@Observable
@MainActor
final class ObservableMainViewModel: MainViewModelProtocol {
    // MARK: - Published Properties
    var filteredHistory: [ClipItem] = []
    var pinnedHistory: [ClipItem] = []
    var filteredItems: [ClipItem] = [] // Keep for backward compatibility
    var searchText = "" {
        didSet {
            applyFilters()
        }
    }
    var editorText = ""
    var selectedCategory: ClipItemCategory? {
        didSet {
            applyFilters()
        }
    }
    var isPinnedFilterActive = false {
        didSet {
            applyFilters()
        }
    }
    var showOnlyPinned = false {
        didSet {
            applyFilters()
        }
    }
    var showOnlyURLs = false {
        didSet {
            applyFilters()
        }
    }
    var showingCopiedNotification = false
    var currentClipboardContent: String?
    var autoClearRemainingTime: TimeInterval?

    // MARK: - Private Properties
    private let clipboardService: any ClipboardServiceProtocol
    private var allItems: [ClipItem] = []
    private var serviceCancellables = Set<AnyCancellable>()
    private var notificationTimer: Timer?

    // MARK: - Initialization
    init(clipboardService: (any ClipboardServiceProtocol)? = nil) {
        // Use provided service or default to provider resolution
        if let service = clipboardService {
            self.clipboardService = service
        } else {
            self.clipboardService = ClipboardServiceProvider.resolve()
        }

        setupBindings()
        Task {
            await loadInitialData()
        }
    }

    // MARK: - Public Methods
    func loadHistory() {
        Task {
            await refreshItems()
        }
    }

    func refreshItems() async {
        allItems = clipboardService.history
        applyFilters()
    }

    func copyToClipboard(_ item: ClipItem) {
        clipboardService.copyToClipboard(item.content, fromEditor: false)
        showCopiedNotification()
    }

    func copyItem(_ item: ClipItem) {
        copyToClipboard(item) // Keep for backward compatibility
    }

    func deleteItem(_ item: ClipItem) async {
        await clipboardService.deleteItem(item)
        await refreshItems()
    }

    func togglePin(for item: ClipItem) async {
        _ = clipboardService.togglePin(for: item)
        await refreshItems()
    }

    func clearHistory(keepPinned: Bool) async {
        await clipboardService.clearHistory(keepPinned: keepPinned)
        if !keepPinned {
            editorText = ""
        }
        await refreshItems()
    }

    func clearAllItems(keepPinned: Bool) {
        Task {
            await clearHistory(keepPinned: keepPinned)
        }
    }

    func updateSearchText(_ text: String) {
        searchText = text
    }

    func selectCategory(_ category: ClipItemCategory?) {
        selectedCategory = category
        applyFilters()
    }

    func toggleShowOnlyPinned() {
        showOnlyPinned.toggle()
        applyFilters()
    }

    func copyEditor() {
        guard !editorText.isEmpty else { return }
        clipboardService.copyToClipboard(editorText, fromEditor: true)
        showCopiedNotification()
    }

    func copyEditorContent() {
        copyEditor() // Keep for backward compatibility
    }

    func clearEditor() {
        editorText = ""
    }

    func toggleCategoryFilter(_ category: ClipItemCategory) {
        if selectedCategory == category {
            selectedCategory = nil
        } else {
            selectedCategory = category
            // Clear pinned filter when category is selected
            isPinnedFilterActive = false
        }
        applyFilters()
    }

    func togglePinnedFilter() {
        isPinnedFilterActive.toggle()
        // Clear category filter when pinned filter is activated
        if isPinnedFilterActive {
            selectedCategory = nil
        }
        applyFilters()
    }

    func insertToEditor(content: String) {
        editorText = content
    }

    func selectHistoryItem(_ item: ClipItem, forceInsert: Bool = false) {
        if forceInsert || shouldInsertToEditor() {
            insertToEditor(content: item.content)
        } else {
            clipboardService.copyToClipboard(item.content, fromEditor: false)
        }
    }

    private func shouldInsertToEditor() -> Bool {
        // Check if editor insert is enabled and modifier keys are pressed
        guard UserDefaults.standard.bool(forKey: "enableEditorInsert") else { return false }

        let currentModifiers = NSEvent.modifierFlags
        let requiredModifiers = NSEvent.ModifierFlags(
            rawValue: UInt(UserDefaults.standard.integer(forKey: "editorInsertModifiers"))
        )

        return currentModifiers.intersection(requiredModifiers) == requiredModifiers
    }

    // MARK: - Private Methods
    private func setupBindings() {
        serviceCancellables.removeAll()

        if let modernService = clipboardService as? ModernClipboardServiceAdapter {
            bindModernService(modernService)
        }
    }

    private func bindModernService(_ service: ModernClipboardServiceAdapter) {
        service.$history
            .sink { [weak self] items in
                Task { @MainActor in
                    self?.allItems = items
                    self?.applyFilters()
                }
            }
            .store(in: &serviceCancellables)

        service.$currentClipboardContent
            .sink { [weak self] content in
                Task { @MainActor in
                    self?.currentClipboardContent = content
                }
            }
            .store(in: &serviceCancellables)

        service.$autoClearRemainingTime
            .sink { [weak self] time in
                Task { @MainActor in
                    self?.autoClearRemainingTime = time
                }
            }
            .store(in: &serviceCancellables)
    }

    private func loadInitialData() async {
        await refreshItems()
    }

    private func applyFilters() {
        // Separate pinned items
        pinnedHistory = allItems.filter { $0.isPinned }

        // Start with all items
        var items = allItems

        // Apply search filter
        if !searchText.isEmpty {
            items = items.filter { item in
                item.content.localizedCaseInsensitiveContains(searchText) ||
                (item.sourceApp?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // Apply category filter
        if let category = selectedCategory {
            items = items.filter { item in
                // Handle category aliases
                switch (category, item.category) {
                case (.url, .url), (.url, .urls), (.urls, .url), (.urls, .urls):
                    return true
                case (.email, .email), (.email, .emails), (.emails, .email), (.emails, .emails):
                    return true
                case (.filePath, .filePath), (.filePath, .files), (.files, .filePath), (.files, .files):
                    return true
                default:
                    return item.category == category
                }
            }
        }

        // URL filter
        if showOnlyURLs {
            items = items.filter { $0.kind == .url }
        }

        // Apply pinned filter
        if showOnlyPinned || isPinnedFilterActive {
            items = items.filter { $0.isPinned }
        }

        // Update filtered results
        // filteredHistory should always be non-pinned items with current filters (except pinned filter)
        var nonPinnedItems = allItems.filter { !$0.isPinned }

        // Apply same filters to non-pinned items
        if !searchText.isEmpty {
            nonPinnedItems = nonPinnedItems.filter { item in
                item.content.localizedCaseInsensitiveContains(searchText) ||
                (item.sourceApp?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        if let category = selectedCategory {
            nonPinnedItems = nonPinnedItems.filter { item in
                // Handle category aliases
                switch (category, item.category) {
                case (.url, .url), (.url, .urls), (.urls, .url), (.urls, .urls):
                    return true
                case (.email, .email), (.email, .emails), (.emails, .email), (.emails, .emails):
                    return true
                case (.filePath, .filePath), (.filePath, .files), (.files, .filePath), (.files, .files):
                    return true
                default:
                    return item.category == category
                }
            }
        }

        if showOnlyURLs {
            nonPinnedItems = nonPinnedItems.filter { $0.kind == .url }
        }

        filteredHistory = nonPinnedItems

        // Update filteredItems
        filteredItems = items
    }

    private func showCopiedNotification() {
        showingCopiedNotification = true

        // Cancel existing timer
        notificationTimer?.invalidate()

        // Hide after 2 seconds
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.showingCopiedNotification = false
            }
        }
    }

    deinit {
        // Timer cleanup is not needed here since the timer will be automatically
        // invalidated when the object is deallocated
    }
}
