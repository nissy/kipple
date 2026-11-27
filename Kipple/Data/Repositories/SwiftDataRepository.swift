import Foundation
import SwiftData

actor SwiftDataRepository: ClipboardRepositoryProtocol {
    private let container: ModelContainer
    private static let mostRecentFirst: [SortDescriptor<ClipItemModel>] = [
        SortDescriptor(\.timestamp, order: .reverse), SortDescriptor(\.id)
    ]

    // MARK: - Factory

    nonisolated static func make(container: ModelContainer? = nil, inMemory: Bool = false) throws -> SwiftDataRepository {
        if let container {
            return SwiftDataRepository(container: container)
        }

        let schema = Schema([ClipItemModel.self, MCPReceiptModel.self])
        let config = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema)
        let container = try ModelContainer(for: schema, configurations: [config])
        return SwiftDataRepository(container: container)
    }

    private init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Helpers

    private func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func saveIfNeeded(_ context: ModelContext) throws {
        if context.hasChanges {
            try context.save()
        }
    }

    private func fetchIDs(_ context: ModelContext) throws -> Set<UUID> {
        var descriptor = FetchDescriptor<ClipItemModel>()
        descriptor.propertiesToFetch = [\.id]
        return Set(try context.fetch(descriptor).map(\.id))
    }

    // MARK: - ClipboardRepositoryProtocol

    func save(_ items: [ClipItem]) async throws {
        guard !items.isEmpty else { return }
        try await applyChanges(inserted: items, updated: [], removed: [])
    }

    func replaceAll(with items: [ClipItem]) async throws {
        let context = makeContext()
        let existingIDs = try fetchIDs(context)
        let newMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        let inserted = newMap.values.filter { !existingIDs.contains($0.id) }
        let common = newMap.values.filter { existingIDs.contains($0.id) }
        let removed = existingIDs.subtracting(newMap.keys)

        try insertItems(Array(inserted), context: context)
        try updateItems(Array(common), context: context)
        try removeItems(Array(removed), context: context)
        try saveIfNeeded(context)
    }

    func load(limit: Int) async throws -> [ClipItem] {
        let context = makeContext()
        var descriptor = FetchDescriptor<ClipItemModel>(
            sortBy: Self.mostRecentFirst
        )
        descriptor.fetchLimit = limit
        let models = try context.fetch(descriptor)
        return models.map { $0.toClipItem() }
    }

    func loadAll() async throws -> [ClipItem] {
        let context = makeContext()
        let descriptor = FetchDescriptor<ClipItemModel>(
            sortBy: Self.mostRecentFirst
        )
        let models = try context.fetch(descriptor)
        return models.map { $0.toClipItem() }
    }

    func load(ids: Set<UUID>) async throws -> [ClipItem] {
        guard !ids.isEmpty else { return [] }
        let itemIDs = Array(ids)
        let descriptor = FetchDescriptor<ClipItemModel>(predicate: #Predicate { itemIDs.contains($0.id) })
        return try makeContext().fetch(descriptor).map { $0.toClipItem() }
    }

    func loadStartupPreviews(limit: Int) async throws -> [HistoryRowPreview] {
        guard limit > 0 else { return [] }
        let context = makeContext()
        guard try hasCompletePreviewIndex(in: context) else { return [] }
        var descriptor = FetchDescriptor<StoredHistoryRowPreview>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse), SortDescriptor(\.id)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map(\.header)
    }

    func backfillHistoryPreviews() async throws {
        let context = makeContext()
        guard try !hasCompletePreviewIndex(in: context) else { return }
        let missing = FetchDescriptor<ClipItemModel>(predicate: #Predicate { $0.listPreview == nil })
        for model in try context.fetch(missing) {
            model.backfillListPreview()
        }
        try saveIfNeeded(context)
    }

    private func hasCompletePreviewIndex(in context: ModelContext) throws -> Bool {
        try context.fetchCount(FetchDescriptor<StoredHistoryRowPreview>()) == context.fetchCount(FetchDescriptor<ClipItemModel>())
    }

    nonisolated func loadFullStartupItem(id: UUID) async throws -> ClipItem? {
        // Use a separate read context so a row action can fetch its item during the bulk startup fetch.
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<ClipItemModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.toClipItem()
    }

    func loadItemIDs() async throws -> Set<UUID> {
        try fetchIDs(makeContext())
    }

    func delete(_ item: ClipItem) async throws {
        try await applyChanges(inserted: [], updated: [], removed: [item.id])
    }

    func clear() async throws {
        let context = makeContext()
        let descriptor = FetchDescriptor<ClipItemModel>()
        let models = try context.fetch(descriptor)
        for model in models {
            context.delete(model)
        }
        try saveIfNeeded(context)
    }

    func countItems() async throws -> Int {
        let context = makeContext()
        return try context.fetchCount(FetchDescriptor<ClipItemModel>())
    }

    func update(_ item: ClipItem) async throws {
        try await applyChanges(inserted: [], updated: [item], removed: [])
    }

    func loadCategorized() async throws -> [ClipItem] {
        let context = makeContext()
        if try hasCompletePreviewIndex(in: context) {
            let previews = FetchDescriptor<StoredHistoryRowPreview>(predicate: #Predicate { $0.hasCustomCategory })
            let ids = try context.fetch(previews).map(\.id)
            guard !ids.isEmpty else { return [] }
            let categorized = FetchDescriptor<ClipItemModel>(
                predicate: #Predicate { ids.contains($0.id) },
                sortBy: Self.mostRecentFirst
            )
            return try context.fetch(categorized).compactMap { $0.toCustomCategorizedClipItem() }
        }
        let descriptor = FetchDescriptor<ClipItemModel>(
            predicate: #Predicate { $0.userCategoryId != nil || $0.metadataData != nil },
            sortBy: Self.mostRecentFirst
        )
        let models = try context.fetch(descriptor)
        return models.compactMap { $0.toCustomCategorizedClipItem() }
    }

    func deleteItemsOlderThan(_ date: Date) async throws {
        let context = makeContext()
        let descriptor = FetchDescriptor<ClipItemModel>(
            predicate: #Predicate { entity in entity.timestamp < date }
        )
        let models = try context.fetch(descriptor)
        for model in models where !model.hasCustomCategory {
            context.delete(model)
        }
        try saveIfNeeded(context)
    }

    func applyChanges(inserted: [ClipItem], updated: [ClipItem], removed: [UUID]) async throws {
        let context = makeContext()
        try removeItems(removed, context: context)
        try updateItems(updated, context: context)
        try insertItems(inserted, context: context)
        try saveIfNeeded(context)
    }

    func receipt(for key: String) throws -> MCPStoredReceipt? {
        let context = makeContext()
        let descriptor = FetchDescriptor<MCPReceiptModel>(predicate: #Predicate { $0.key == key })
        guard let model = try context.fetch(descriptor).first,
              model.receivedAt > Date().addingTimeInterval(-86_400) else { return nil }
        return try JSONDecoder().decode(MCPStoredReceipt.self, from: model.data)
    }

    func commitMCP(
        inserted: [ClipItem],
        updated: [ClipItem],
        removed: [UUID],
        record: MCPStoredReceipt
    ) throws {
        let context = makeContext()
        try removeItems(removed, context: context)
        try updateItems(updated, context: context)
        try insertItems(inserted, context: context)
        try storeReceipt(record, context: context)
        try saveIfNeeded(context)
    }

    func updateReceipt(_ record: MCPStoredReceipt) throws {
        let context = makeContext()
        try storeReceipt(record, context: context)
        try saveIfNeeded(context)
    }

    private func storeReceipt(_ record: MCPStoredReceipt, context: ModelContext) throws {
        let cutoff = Date().addingTimeInterval(-86_400)
        let key = record.key
        let descriptor = FetchDescriptor<MCPReceiptModel>(
            predicate: #Predicate { $0.receivedAt < cutoff || $0.key == key }
        )
        for old in try context.fetch(descriptor) { context.delete(old) }
        context.insert(try MCPReceiptModel(record: record))
    }

    // MARK: - Internal helpers

    private func insertItems(_ items: [ClipItem], context: ModelContext) throws {
        guard !items.isEmpty else { return }
        for (offset, item) in items.enumerated() {
            let adjustedTimestamp = item.timestamp.addingTimeInterval(TimeInterval(offset) * 1e-6)
            let model = ClipItemModel(
                id: item.id,
                content: item.content,
                timestamp: adjustedTimestamp,
                kind: item.kind,
                appName: item.sourceApp,
                windowTitle: item.windowTitle,
                bundleId: item.bundleIdentifier,
                processId: item.processID,
                isFromEditor: item.isFromEditor ?? false,
                userCategoryId: item.userCategoryId,
                metadata: item.metadata,
                richText: item.richText
            )
            model.refreshListPreview(from: item)
            context.insert(model)
        }
    }

    private func updateItems(_ items: [ClipItem], context: ModelContext) throws {
        guard !items.isEmpty else { return }
        let ids = items.map { $0.id }
        let descriptor = FetchDescriptor<ClipItemModel>(
            predicate: #Predicate { entity in ids.contains(entity.id) }
        )
        let models = try context.fetch(descriptor)
        var map = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for model in models {
            if let item = map.removeValue(forKey: model.id) {
                model.update(with: item)
            }
        }
        for (offset, item) in map.values.enumerated() {
            let adjustedTimestamp = item.timestamp.addingTimeInterval(TimeInterval(offset) * 1e-6)
            let model = ClipItemModel(
                id: item.id,
                content: item.content,
                timestamp: adjustedTimestamp,
                kind: item.kind,
                appName: item.sourceApp,
                windowTitle: item.windowTitle,
                bundleId: item.bundleIdentifier,
                processId: item.processID,
                isFromEditor: item.isFromEditor ?? false,
                userCategoryId: item.userCategoryId,
                metadata: item.metadata,
                richText: item.richText
            )
            model.refreshListPreview(from: item)
            context.insert(model)
        }
    }

    private func removeItems(_ ids: [UUID], context: ModelContext) throws {
        guard !ids.isEmpty else { return }
        let descriptor = FetchDescriptor<ClipItemModel>(
            predicate: #Predicate { entity in ids.contains(entity.id) }
        )
        let models = try context.fetch(descriptor)
        for model in models {
            context.delete(model)
        }
    }
}

private extension ClipItemModel {
    func update(with item: ClipItem) {
        content = item.content
        timestamp = item.timestamp
        kindRawValue = item.kind.rawValue
        appName = item.sourceApp
        windowTitle = item.windowTitle
        bundleId = item.bundleIdentifier
        processId = item.processID
        isFromEditor = item.isFromEditor ?? false
        userCategoryId = item.userCategoryId
        metadataData = item.metadata.flatMap { try? JSONEncoder().encode($0) }
        richTextData = item.richText.flatMap { try? JSONEncoder().encode($0) }
        refreshListPreview(from: item)
    }
}
