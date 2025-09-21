import Foundation
import SwiftData

@available(macOS 14.0, *)
@MainActor
final class SwiftDataRepository: ClipboardRepositoryProtocol {
    private let container: ModelContainer
    private let context: ModelContext

    init(container: ModelContainer? = nil, inMemory: Bool = false) throws {
        if let container {
            self.container = container
        } else {
            let schema = Schema([ClipItemModel.self])
            let config: ModelConfiguration
            if inMemory {
                config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            } else {
                config = ModelConfiguration(schema: schema)
            }
            self.container = try ModelContainer(for: schema, configurations: [config])
        }
        self.context = self.container.mainContext
    }

    func save(_ items: [ClipItem]) async throws {
        // For migration, just add items without clearing existing ones
        // Check for duplicates by ID
        let descriptor = FetchDescriptor<ClipItemModel>()
        let existingModels = try context.fetch(descriptor)
        let existingIds = Set(existingModels.map { $0.id })

        // Add only new items (not already present)
        for item in items {
            if !existingIds.contains(item.id) {
                let model = ClipItemModel(from: item)
                context.insert(model)
            }
        }

        try context.save()
    }

    func load(limit: Int) async throws -> [ClipItem] {
        var descriptor = FetchDescriptor<ClipItemModel>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let models = try context.fetch(descriptor)
        return models.map { $0.toClipItem() }
    }

    func loadAll() async throws -> [ClipItem] {
        let descriptor = FetchDescriptor<ClipItemModel>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        let models = try context.fetch(descriptor)
        return models.map { $0.toClipItem() }
    }

    func delete(_ item: ClipItem) async throws {
        let descriptor = FetchDescriptor<ClipItemModel>(
            predicate: #Predicate { model in
                model.id == item.id
            }
        )

        let models = try context.fetch(descriptor)
        for model in models {
            context.delete(model)
        }

        try context.save()
    }

    func clear() async throws {
        let descriptor = FetchDescriptor<ClipItemModel>()
        let models = try context.fetch(descriptor)
        for model in models {
            context.delete(model)
        }
        try context.save()
    }

    func clear(keepPinned: Bool) async throws {
        let descriptor: FetchDescriptor<ClipItemModel>

        if keepPinned {
            descriptor = FetchDescriptor<ClipItemModel>(
                predicate: #Predicate { model in
                    !model.isPinned
                }
            )
        } else {
            descriptor = FetchDescriptor<ClipItemModel>()
        }

        let models = try context.fetch(descriptor)
        for model in models {
            context.delete(model)
        }

        try context.save()
    }

    // MARK: - Additional Operations

    func countItems() async throws -> Int {
        let descriptor = FetchDescriptor<ClipItemModel>()
        return try context.fetchCount(descriptor)
    }

    func update(_ item: ClipItem) async throws {
        // Find existing model by ID
        let descriptor = FetchDescriptor<ClipItemModel>(
            predicate: #Predicate { model in
                model.id == item.id
            }
        )

        let models = try context.fetch(descriptor)
        if let existingModel = models.first {
            // Update properties
            existingModel.content = item.content
            existingModel.isPinned = item.isPinned
            existingModel.timestamp = item.timestamp
            existingModel.appName = item.sourceApp
            existingModel.windowTitle = item.windowTitle
            existingModel.bundleId = item.bundleIdentifier
            existingModel.processId = item.processID
            existingModel.isFromEditor = item.isFromEditor ?? false
            existingModel.kindRawValue = item.kind.rawValue
        } else {
            // If not found, create new
            let model = ClipItemModel(from: item)
            context.insert(model)
        }

        try context.save()
    }

    func loadPinned() async throws -> [ClipItem] {
        let descriptor = FetchDescriptor<ClipItemModel>(
            predicate: #Predicate { model in
                model.isPinned
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        let models = try context.fetch(descriptor)
        return models.map { $0.toClipItem() }
    }

    func deleteItemsOlderThan(_ date: Date) async throws {
        let descriptor = FetchDescriptor<ClipItemModel>(
            predicate: #Predicate { model in
                model.timestamp < date && !model.isPinned
            }
        )

        let models = try context.fetch(descriptor)
        for model in models {
            context.delete(model)
        }

        try context.save()
    }
}
