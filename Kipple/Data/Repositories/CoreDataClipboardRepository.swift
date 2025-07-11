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
        try await coreDataStack.performBackgroundTask { context in
            let existingRequest: NSFetchRequest<ClipItemEntity> = ClipItemEntity.fetchRequest()
            let existingEntities = try context.fetch(existingRequest)
            
            // パフォーマンス最適化: O(1)ルックアップのための辞書を作成
            let existingEntitiesDict: [UUID: ClipItemEntity] = Dictionary(
                uniqueKeysWithValues: existingEntities.compactMap { entity in
                    guard let id = entity.id else { return nil }
                    return (id, entity)
                }
            )
            
            let itemIds = Set(items.map { $0.id })
            
            // 削除処理
            for entity in existingEntities where !itemIds.contains(entity.id ?? UUID()) {
                context.delete(entity)
            }
            
            // 更新・作成処理
            for item in items {
                if let existingEntity = existingEntitiesDict[item.id] {
                    existingEntity.update(from: item)
                } else {
                    _ = ClipItemEntity.create(from: item, in: context)
                }
            }
            
            try context.save()
            Logger.shared.debug("Saved \(items.count) items to Core Data")
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
