//
//  CoreDataClipboardRepository.swift
//  Kipple
//
//  Created by Kipple on 2025/07/11.
//

import Foundation
import CoreData

class CoreDataClipboardRepository: ClipboardRepositoryProtocol {
    private let coreDataStack = CoreDataStack.shared
    
    func save(_ items: [ClipItem]) async throws {
        try await coreDataStack.performBackgroundTask { [weak self] context in
            try autoreleasepool {
                guard let self = self else { return }

                let ids = items.map { $0.id }
                try self.batchDeleteNotIn(ids: ids, context: context)

                let existing = try self.fetchExistingDict(for: ids, context: context)
                let (updated, created) = self.upsert(items, using: existing, in: context)

                Logger.shared.debug(
                    "CoreDataClipboardRepository.save: Updated \(updated), Created \(created) entities"
                )

                try context.save()
                Logger.shared.debug(
                    "CoreDataClipboardRepository.save: Successfully saved \(items.count) items to Core Data"
                )
            }
        }
        
        // バックグラウンドタスクの外でメインコンテキストを保存
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            if let viewContext = self.coreDataStack.viewContext, viewContext.hasChanges {
                do {
                    try viewContext.save()
                    Logger.shared.debug("CoreDataClipboardRepository.save: Also saved view context")
                } catch {
                    Logger.shared.error("Failed to save view context: \(error)")
                }
            }
        }
    }

    // MARK: - Private helpers
    private func batchDeleteNotIn(ids: [UUID], context: NSManagedObjectContext) throws {
        let deleteFetch: NSFetchRequest<NSFetchRequestResult> = ClipItemEntity.fetchRequest()
        if ids.isEmpty {
            // 全削除
        } else {
            deleteFetch.predicate = NSPredicate(format: "NOT (id IN %@)", ids as [UUID])
        }
        let batchDelete = NSBatchDeleteRequest(fetchRequest: deleteFetch)
        batchDelete.resultType = .resultTypeObjectIDs
        if let result = try context.execute(batchDelete) as? NSBatchDeleteResult,
           let objectIDs = result.result as? [NSManagedObjectID], !objectIDs.isEmpty {
            let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: objectIDs]
            var targetContexts: [NSManagedObjectContext] = [context]
            if let viewContext = coreDataStack.viewContext { targetContexts.append(viewContext) }
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: targetContexts)
        }
    }

    private func fetchExistingDict(for ids: [UUID], context: NSManagedObjectContext) throws -> [UUID: ClipItemEntity] {
        guard !ids.isEmpty else { return [:] }
        let fetch: NSFetchRequest<ClipItemEntity> = ClipItemEntity.fetchRequest()
        fetch.predicate = NSPredicate(format: "id IN %@", ids as [UUID])
        fetch.returnsObjectsAsFaults = true
        fetch.includesPropertyValues = true
        let existing = try context.fetch(fetch)
        return Dictionary(uniqueKeysWithValues: existing.compactMap { entity in
            guard let id = entity.id else { return nil }
            return (id, entity)
        })
    }

    private func upsert(_ items: [ClipItem], using existing: [UUID: ClipItemEntity], in context: NSManagedObjectContext) -> (Int, Int) {
        var updated = 0
        var created = 0
        for item in items {
            if let entity = existing[item.id] {
                entity.update(from: item)
                updated += 1
            } else {
                _ = ClipItemEntity.create(from: item, in: context)
                created += 1
            }
        }
        return (updated, created)
    }
    
    func load(limit: Int = 100) async throws -> [ClipItem] {
        return try await coreDataStack.performBackgroundTask { context in
            let request: NSFetchRequest<ClipItemEntity> = ClipItemEntity.fetchRequest()
            request.fetchLimit = limit
            request.sortDescriptors = [
                NSSortDescriptor(key: "isPinned", ascending: false),
                NSSortDescriptor(key: "timestamp", ascending: false)
            ]
            // パフォーマンス最適化: バッチサイズを設定
            request.fetchBatchSize = 20
            
            let entities = try context.fetch(request)
            return entities.map { $0.toClipItem() }
        }
    }
    
    func loadAll() async throws -> [ClipItem] {
        return try await coreDataStack.performBackgroundTask { context in
            let request: NSFetchRequest<ClipItemEntity> = ClipItemEntity.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(key: "isPinned", ascending: false),
                NSSortDescriptor(key: "timestamp", ascending: false)
            ]
            // パフォーマンス最適化: バッチサイズを設定
            request.fetchBatchSize = 50
            
            let entities = try context.fetch(request)
            return entities.map { $0.toClipItem() }
        }
    }
    
    func delete(_ item: ClipItem) async throws {
        try await coreDataStack.performBackgroundTask { context in
            let request: NSFetchRequest<ClipItemEntity> = ClipItemEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", item.id as CVarArg)
            
            if let entity = try context.fetch(request).first {
                context.delete(entity)
                try context.save()
                Logger.shared.debug("Deleted item with id: \(item.id)")
            }
        }
    }
    
    func clear(keepPinned: Bool = true) async throws {
        try await coreDataStack.performBackgroundTask { [weak self] context in
            guard let self = self else { return }
            let request: NSFetchRequest<ClipItemEntity> = ClipItemEntity.fetchRequest()
            
            if keepPinned {
                request.predicate = NSPredicate(format: "isPinned == NO")
            }
            
            // インメモリストアでは個別削除を使用
            let entities = try context.fetch(request)
            var deletedCount = 0
            
            for entity in entities {
                context.delete(entity)
                deletedCount += 1
            }
            
            try context.save()
            
            Logger.shared.log("Cleared \(deletedCount) items from Core Data (keepPinned: \(keepPinned))")
        }
    }
}
