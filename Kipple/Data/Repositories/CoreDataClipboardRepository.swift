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
            let existingRequest: NSFetchRequest<ClipItemEntity> = ClipItemEntity.fetchRequest()
            let existingEntities = try context.fetch(existingRequest)
            
            Logger.shared.debug("CoreDataClipboardRepository.save: Saving \(items.count) items, existing entities: \(existingEntities.count)")
            
            // パフォーマンス最適化: O(1)ルックアップのための辞書を作成
            let existingEntitiesDict: [UUID: ClipItemEntity] = Dictionary(
                uniqueKeysWithValues: existingEntities.compactMap { entity in
                    guard let id = entity.id else { return nil }
                    return (id, entity)
                }
            )
            
            let itemIds = Set(items.map { $0.id })
            
            // 削除処理
            var deletedCount = 0
            for entity in existingEntities where !itemIds.contains(entity.id ?? UUID()) {
                context.delete(entity)
                deletedCount += 1
            }
            if deletedCount > 0 {
                Logger.shared.debug("CoreDataClipboardRepository.save: Deleted \(deletedCount) entities not in the new list")
            }
            
            // 更新・作成処理
            var updatedCount = 0
            var createdCount = 0
            for item in items {
                if let existingEntity = existingEntitiesDict[item.id] {
                    existingEntity.update(from: item)
                    updatedCount += 1
                } else {
                    _ = ClipItemEntity.create(from: item, in: context)
                    createdCount += 1
                }
            }
            
            Logger.shared.debug("CoreDataClipboardRepository.save: Updated \(updatedCount), Created \(createdCount) entities")
            
            try context.save()
            Logger.shared.debug("CoreDataClipboardRepository.save: Successfully saved \(items.count) items to Core Data")
            
            // メインコンテキストも保存して確実に永続化する処理は
            // performBackgroundTaskの外で実行する必要がある
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
            let request: NSFetchRequest<NSFetchRequestResult> = ClipItemEntity.fetchRequest()
            
            if keepPinned {
                request.predicate = NSPredicate(format: "isPinned == NO")
            }
            
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            deleteRequest.resultType = .resultTypeObjectIDs
            
            let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
            let deletedObjectIDs = result?.result as? [NSManagedObjectID] ?? []
            let deletedCount = deletedObjectIDs.count
            
            // 削除されたオブジェクトをコンテキストから削除
            let changes = [NSDeletedObjectsKey: deletedObjectIDs]
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: changes,
                into: [context]
            )
            
            // view contextにも変更を伝播
            if let viewContext = self.coreDataStack.viewContext {
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: changes,
                    into: [viewContext]
                )
            }
            
            Logger.shared.log("Cleared \(deletedCount) items from Core Data (keepPinned: \(keepPinned))")
        }
    }
}
