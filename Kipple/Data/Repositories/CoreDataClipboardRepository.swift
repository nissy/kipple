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
            guard let self = self else { return }

            // 1) 先に不要なレコードをバッチ削除（大量フェッチを避ける）
            let ids = items.map { $0.id }
            if !ids.isEmpty {
                let deleteFetch: NSFetchRequest<NSFetchRequestResult> = ClipItemEntity.fetchRequest()
                deleteFetch.predicate = NSPredicate(format: "NOT (id IN %@)", ids as [UUID])
                let batchDelete = NSBatchDeleteRequest(fetchRequest: deleteFetch)
                batchDelete.resultType = .resultTypeObjectIDs
                if let result = try context.execute(batchDelete) as? NSBatchDeleteResult,
                   let objectIDs = result.result as? [NSManagedObjectID],
                   !objectIDs.isEmpty {
                    let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: objectIDs]
                    var targetContexts: [NSManagedObjectContext] = [context]
                    if let viewContext = self.coreDataStack.viewContext {
                        targetContexts.append(viewContext)
                    }
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: targetContexts)
                }
            } else {
                // 空の場合は全削除
                let deleteFetch: NSFetchRequest<NSFetchRequestResult> = ClipItemEntity.fetchRequest()
                let batchDelete = NSBatchDeleteRequest(fetchRequest: deleteFetch)
                batchDelete.resultType = .resultTypeObjectIDs
                if let result = try context.execute(batchDelete) as? NSBatchDeleteResult,
                   let objectIDs = result.result as? [NSManagedObjectID],
                   !objectIDs.isEmpty {
                    let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: objectIDs]
                    var targetContexts: [NSManagedObjectContext] = [context]
                    if let viewContext = self.coreDataStack.viewContext {
                        targetContexts.append(viewContext)
                    }
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: targetContexts)
                }
            }

            // 2) 既存の対象のみフェッチして辞書化（全件ロードを避ける）
            var existingEntitiesDict: [UUID: ClipItemEntity] = [:]
            if !ids.isEmpty {
                let fetchExisting: NSFetchRequest<ClipItemEntity> = ClipItemEntity.fetchRequest()
                fetchExisting.predicate = NSPredicate(format: "id IN %@", ids as [UUID])
                fetchExisting.returnsObjectsAsFaults = true
                fetchExisting.includesPropertyValues = true
                let existing = try context.fetch(fetchExisting)
                existingEntitiesDict = Dictionary(uniqueKeysWithValues: existing.compactMap { entity in
                    guard let id = entity.id else { return nil }
                    return (id, entity)
                })
            }

            // 3) 更新・作成
            var updatedCount = 0
            var createdCount = 0
            for item in items {
                if let entity = existingEntitiesDict[item.id] {
                    entity.update(from: item)
                    updatedCount += 1
                } else {
                    _ = ClipItemEntity.create(from: item, in: context)
                    createdCount += 1
                }
            }

            Logger.shared.debug(
                "CoreDataClipboardRepository.save: Updated \(updatedCount), Created \(createdCount) entities"
            )

            try context.save()
            Logger.shared.debug(
                "CoreDataClipboardRepository.save: Successfully saved \(items.count) items to Core Data"
            )
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
