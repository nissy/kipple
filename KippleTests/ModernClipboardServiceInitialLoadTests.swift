import XCTest
@testable import Kipple

@MainActor
final class ModernClipboardServiceInitialLoadTests: XCTestCase {
    private var service: ModernClipboardService!
    private var repository: MockClipboardRepository!

    override func setUp() async throws {
        try await super.setUp()

        service = ModernClipboardService.shared
        await service.useCategoryStoreFixture()
        repository = MockClipboardRepository()

        await MainActor.run {
            RepositoryProvider.useTestingRepository(repository)
        }
        await service.setRepository(repository)

        // Reset service state
        await service.stopMonitoring()
        await service.clearHistory(keepingCategories: false)

        AppSettings.shared.maxHistoryItems = 300
        await service.setMaxHistoryItems(300)
    }

    override func tearDown() async throws {
        await service.stopMonitoring()
        await service.clearHistory(keepingCategories: false)

        await MainActor.run {
            RepositoryProvider.useTestingRepository(nil)
        }

        AppSettings.shared.maxHistoryItems = 300

        repository = nil
        service = nil

        try await super.tearDown()
    }

    func testInitialLoadUsesDynamicLimit() async throws {
        // Given
        AppSettings.shared.maxHistoryItems = 200
        await service.setMaxHistoryItems(200)

        var seededItems: [ClipItem] = []
        for index in 1...70 {
            var item = ClipItem(content: "Categorized \(index)")
            item.setCategory(savedHistoryCategoryID, enabled: true)
            seededItems.append(item)
        }
        for index in 1...120 {
            seededItems.append(ClipItem(content: "Uncategorized \(index)"))
        }
        await repository.configure(items: seededItems, loadDelay: 0)

        // When
        await service.loadHistoryFromRepository()

        // Then
        let requestedLimits = await repository.getRequestedLimits()
        let expectedLimit = 200 + 70 + 10
        XCTAssertEqual(requestedLimits.last, expectedLimit,
                       "Initial load should request dynamic limit with headroom")
    }

    func testCategorizedItemsSurfaceBeforeFullLoad() async throws {
        // Given
        AppSettings.shared.maxHistoryItems = 50
        await service.setMaxHistoryItems(50)

        var seededItems: [ClipItem] = []
        for index in 1...6 {
            var item = ClipItem(content: "Categorized \(index)")
            item.setCategory(savedHistoryCategoryID, enabled: true)
            seededItems.append(item)
        }
        for index in 1...80 {
            seededItems.append(ClipItem(content: "History \(index)"))
        }
        await repository.configure(items: seededItems, loadDelay: 200_000_000)

        // When
        let loadTask = Task {
            await self.service.loadHistoryFromRepository()
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        let interimHistory = await service.getHistory()

        // Then
        XCTAssertEqual(interimHistory.count, 6,
                       "Categorized items should be available before full history loads")
        XCTAssertTrue(interimHistory.allSatisfy { $0.hasCustomCategory },
                      "Interim history should only contain categorized items")

        await loadTask.value
        let finalHistory = await service.getHistory()

        let categorizedInFinal = finalHistory.filter { $0.hasCustomCategory }
        XCTAssertEqual(finalHistory.count - categorizedInFinal.count, 50)
        XCTAssertEqual(categorizedInFinal.count, 6,
                       "Categorized items must be preserved after trimming")
    }

    func testInitialLoadKeepsTimestampOrderWithCategorizedItems() async throws {
        // Given
        AppSettings.shared.maxHistoryItems = 10
        await service.setMaxHistoryItems(10)

        let now = Date()
        var newest = ClipItem(content: "Newest uncategorized")
        newest.timestamp = now

        var categorizedMiddle = ClipItem(content: "Categorized middle")
        categorizedMiddle.timestamp = now.addingTimeInterval(-10)
        categorizedMiddle.setCategory(savedHistoryCategoryID, enabled: true)

        var recent = ClipItem(content: "Recent uncategorized")
        recent.timestamp = now.addingTimeInterval(-20)

        var categorizedOld = ClipItem(content: "Categorized old")
        categorizedOld.timestamp = now.addingTimeInterval(-30)
        categorizedOld.setCategory(savedHistoryCategoryID, enabled: true)

        await repository.configure(
            items: [categorizedOld, newest, categorizedMiddle, recent],
            loadDelay: 0
        )

        // When
        await service.loadHistoryFromRepository()

        // Then
        let history = await service.getHistory()
        XCTAssertEqual(
            history.map(\.content),
            ["Newest uncategorized", "Categorized middle", "Recent uncategorized", "Categorized old"],
            "Initial load should not move categorized items above newer uncategorized items"
        )
    }
}

actor MockClipboardRepository: ClipboardRepositoryProtocol {
    private var storage: [ClipItem] = []
    private var startupPreviews: [HistoryRowPreview] = []
    private var requestedLimitHistory: [Int] = []
    private var loadDelayNanoseconds: UInt64 = 0
    private var remainingLoadFailures = 0
    private var remainingWriteFailures = 0
    private var onLoad: (@Sendable () -> Void)?
    private var shouldSuspendLoad = false
    private var loadContinuation: CheckedContinuation<Void, Never>?

    func configureStartupPreviews(_ rows: [HistoryRowPreview]) {
        startupPreviews = rows
    }

    func loadStartupPreviews(limit: Int) async throws -> [HistoryRowPreview] {
        Array(startupPreviews.prefix(limit))
    }

    func failNextLoads(_ count: Int) {
        remainingLoadFailures = count
    }

    func failNextWrites(_ count: Int) {
        remainingWriteFailures = count
    }

    func suspendLoad(onLoad: @escaping @Sendable () -> Void) {
        shouldSuspendLoad = true
        self.onLoad = onLoad
    }

    func resumeLoad() {
        shouldSuspendLoad = false
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func configure(items: [ClipItem], loadDelay: UInt64) {
        storage = items.sorted { $0.timestamp > $1.timestamp }
        requestedLimitHistory = []
        loadDelayNanoseconds = loadDelay
    }

    func save(_ items: [ClipItem]) async throws {
        storage.append(contentsOf: items)
        storage.sort { $0.timestamp > $1.timestamp }
    }

    func replaceAll(with items: [ClipItem]) async throws {
        storage = items.sorted { $0.timestamp > $1.timestamp }
    }

    func load(limit: Int) async throws -> [ClipItem] {
        requestedLimitHistory.append(limit)
        if shouldSuspendLoad {
            await withCheckedContinuation { continuation in
                loadContinuation = continuation
                onLoad?()
            }
        }
        if remainingLoadFailures > 0 {
            remainingLoadFailures -= 1
            throw CocoaError(.fileReadCorruptFile)
        }
        if loadDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: loadDelayNanoseconds)
        }
        return Array(storage.prefix(limit))
    }

    func loadAll() async throws -> [ClipItem] {
        storage
    }

    func delete(_ item: ClipItem) async throws {
        storage.removeAll { $0.id == item.id }
    }

    func clear() async throws {
        storage.removeAll()
    }

    func applyChanges(inserted: [ClipItem], updated: [ClipItem], removed: [UUID]) async throws {
        if remainingWriteFailures > 0 {
            remainingWriteFailures -= 1
            throw CocoaError(.fileWriteOutOfSpace)
        }
        if !removed.isEmpty {
            storage.removeAll { removed.contains($0.id) }
        }

        for item in updated {
            if let index = storage.firstIndex(where: { $0.id == item.id }) {
                storage[index] = item
            } else {
                storage.append(item)
            }
        }

        if !inserted.isEmpty {
            storage.append(contentsOf: inserted)
        }

        storage.sort { $0.timestamp > $1.timestamp }
    }

    func getRequestedLimits() -> [Int] {
        requestedLimitHistory
    }
}
