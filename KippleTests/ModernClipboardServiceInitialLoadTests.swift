import XCTest
@testable import Kipple

@MainActor
final class ModernClipboardServiceInitialLoadTests: XCTestCase {
    private var service: ModernClipboardService!
    private var repository: MockClipboardRepository!

    override func setUp() async throws {
        try await super.setUp()

        service = ModernClipboardService.shared
        repository = MockClipboardRepository()

        await MainActor.run {
            RepositoryProvider.useTestingRepository(repository)
        }
        await service.setRepository(repository)

        // Reset service state
        await service.stopMonitoring()
        await service.clearHistory(keepPinned: false)
        await service.clearAllHistory()

        AppSettings.shared.maxHistoryItems = 300
        AppSettings.shared.maxPinnedItems = 50
        await service.setMaxHistoryItems(300)
    }

    override func tearDown() async throws {
        await service.stopMonitoring()
        await service.clearHistory(keepPinned: false)
        await service.clearAllHistory()

        await MainActor.run {
            RepositoryProvider.useTestingRepository(nil)
        }

        AppSettings.shared.maxHistoryItems = 300
        AppSettings.shared.maxPinnedItems = 50

        repository = nil
        service = nil

        try await super.tearDown()
    }

    func testInitialLoadUsesDynamicLimit() async throws {
        // Given
        AppSettings.shared.maxHistoryItems = 200
        AppSettings.shared.maxPinnedItems = 30
        await service.setMaxHistoryItems(200)

        var seededItems: [ClipItem] = []
        for index in 1...70 {
            var item = ClipItem(content: "Pinned \(index)")
            item.isPinned = true
            seededItems.append(item)
        }
        for index in 1...120 {
            seededItems.append(ClipItem(content: "Unpinned \(index)"))
        }
        await repository.configure(items: seededItems, loadDelay: 0)

        // When
        await service.loadHistoryFromRepository()

        // Then
        let requestedLimits = await repository.getRequestedLimits()
        let expectedLimit = 200 + max(30, 70) + 10
        XCTAssertEqual(requestedLimits.last, expectedLimit,
                       "Initial load should request dynamic limit with headroom")
    }

    func testPinnedItemsSurfaceBeforeFullLoad() async throws {
        // Given
        AppSettings.shared.maxHistoryItems = 50
        AppSettings.shared.maxPinnedItems = 10
        await service.setMaxHistoryItems(50)

        var seededItems: [ClipItem] = []
        for index in 1...6 {
            var item = ClipItem(content: "Pinned \(index)")
            item.isPinned = true
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
                       "Pinned items should be available before full history loads")
        XCTAssertTrue(interimHistory.allSatisfy { $0.isPinned },
                      "Interim history should only contain pinned items")

        await loadTask.value
        let finalHistory = await service.getHistory()

        XCTAssertLessThanOrEqual(finalHistory.count, 50,
                                 "Final history should respect max history limit")
        let pinnedInFinal = finalHistory.filter { $0.isPinned }
        XCTAssertEqual(pinnedInFinal.count, 6,
                       "Pinned items must be preserved after trimming")
    }
}

actor MockClipboardRepository: ClipboardRepositoryProtocol {
    private var storage: [ClipItem] = []
    private var requestedLimitHistory: [Int] = []
    private var loadDelayNanoseconds: UInt64 = 0

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
        if loadDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: loadDelayNanoseconds)
        }
        return Array(storage.prefix(limit))
    }

    func loadAll() async throws -> [ClipItem] {
        storage
    }

    func loadPinned() async throws -> [ClipItem] {
        storage.filter { $0.isPinned }.sorted { $0.timestamp > $1.timestamp }
    }

    func delete(_ item: ClipItem) async throws {
        storage.removeAll { $0.id == item.id }
    }

    func clear() async throws {
        storage.removeAll()
    }

    func clear(keepPinned: Bool) async throws {
        if keepPinned {
            storage.removeAll { !$0.isPinned }
        } else {
            storage.removeAll()
        }
    }

    func applyChanges(inserted: [ClipItem], updated: [ClipItem], removed: [UUID]) async throws {
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
