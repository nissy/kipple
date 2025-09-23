import Foundation
import SwiftData

@available(macOS 14.0, *)
actor SwiftDataRepository: ClipboardRepositoryProtocol, Sendable {
    private let container: ModelContainer

    // MARK: - Factory

    nonisolated static func make(container: ModelContainer? = nil, inMemory: Bool = false) throws -> SwiftDataRepository {
        if let container {
            return SwiftDataRepository(container: container)
        }

        let schema = Schema([ClipItemModel.self])
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

    private func fetchIDs(_ context: ModelContext) -> [UUID] {
        let descriptor = FetchDescriptor<ClipItemModel>()
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map { $0.id }
    }

    // MARK: - ClipboardRepositoryProtocol

    func save(_ items: [ClipItem]) async throws {
        guard !items.isEmpty else { return }
        try await applyChanges(inserted: items, updated: [], removed: [])
    }

    func replaceAll(with items: [ClipItem]) async throws {
        let context = makeContext()
        let existingIDs = Set(fetchIDs(context))
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
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let models = try context.fetch(descriptor)
        return models.map { $0.toClipItem() }
    }

    func loadAll() async throws -> [ClipItem] {
        let context = makeContext()
        let descriptor = FetchDescriptor<ClipItemModel>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let models = try context.fetch(descriptor)
        return models.map { $0.toClipItem() }
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

    func clear(keepPinned: Bool) async throws {
        let context = makeContext()
        let descriptor: FetchDescriptor<ClipItemModel>
        if keepPinned {
            descriptor = FetchDescriptor<ClipItemModel>(
                predicate: #Predicate { entity in !entity.isPinned }
            )
        } else {
            descriptor = FetchDescriptor<ClipItemModel>()
        }
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

    func loadPinned() async throws -> [ClipItem] {
        let context = makeContext()
        let descriptor = FetchDescriptor<ClipItemModel>(
            predicate: #Predicate { entity in entity.isPinned },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let models = try context.fetch(descriptor)
        return models.map { $0.toClipItem() }
    }

    func deleteItemsOlderThan(_ date: Date) async throws {
        let context = makeContext()
        let descriptor = FetchDescriptor<ClipItemModel>(
            predicate: #Predicate { entity in entity.timestamp < date && !entity.isPinned }
        )
        let models = try context.fetch(descriptor)
        for model in models {
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

    // MARK: - Internal helpers

    private func insertItems(_ items: [ClipItem], context: ModelContext) throws {
        guard !items.isEmpty else { return }
        for (offset, item) in items.enumerated() {
            let adjustedTimestamp = item.timestamp.addingTimeInterval(TimeInterval(offset) * 1e-6)
            let model = ClipItemModel(
                id: item.id,
                content: item.content,
                timestamp: adjustedTimestamp,
                isPinned: item.isPinned,
                kind: item.kind,
                appName: item.sourceApp,
                windowTitle: item.windowTitle,
                bundleId: item.bundleIdentifier,
                processId: item.processID,
                isFromEditor: item.isFromEditor ?? false
            )
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
            context.insert(ClipItemModel(
                id: item.id,
                content: item.content,
                timestamp: adjustedTimestamp,
                isPinned: item.isPinned,
                kind: item.kind,
                appName: item.sourceApp,
                windowTitle: item.windowTitle,
                bundleId: item.bundleIdentifier,
                processId: item.processID,
                isFromEditor: item.isFromEditor ?? false
            ))
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

@available(macOS 14.0, *)
private extension ClipItemModel {
    func update(with item: ClipItem) {
        content = item.content
        timestamp = item.timestamp
        isPinned = item.isPinned
        kindRawValue = item.kind.rawValue
        appName = item.sourceApp
        windowTitle = item.windowTitle
        bundleId = item.bundleIdentifier
        processId = item.processID
        isFromEditor = item.isFromEditor ?? false
    }
}
