//
//  CoreDataStack.swift
//  Kipple
//
//  Created by Kipple on 2025/07/11.
//

import Foundation
import CoreData

class CoreDataStack {
    static let shared = CoreDataStack()
    
    private var _persistentContainer: NSPersistentContainer?
    private let containerLock = NSLock()
    private var isInitializing = false
    private(set) var isLoaded = false
    private(set) var loadError: Error?
    
    var persistentContainer: NSPersistentContainer? {
        containerLock.lock()
        defer { containerLock.unlock() }
        
        if let container = _persistentContainer {
            return container
        }
        
        // 初期化フラグをチェック（デッドロック防止）
        if isInitializing {
            return nil
        }
        
        isInitializing = true
        defer { isInitializing = false }
        
        let container = NSPersistentContainer(name: "Kipple")
        
        // マイグレーションオプションを設定
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        
        // 非同期で初期化を実行
        Task {
            let loadedContainer = await loadPersistentContainerAsync()
            if loadedContainer != nil {
                Logger.shared.log("Core Data container loaded successfully")
            }
        }
        
        return nil
    }
    
    var viewContext: NSManagedObjectContext? {
        persistentContainer?.viewContext
    }
    
    func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        guard let container = persistentContainer else {
            throw CoreDataError.notLoaded
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                do {
                    let result = try block(context)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    @MainActor
    func save() throws {
        guard let context = viewContext else {
            throw CoreDataError.notLoaded
        }
        
        if context.hasChanges {
            try context.save()
        }
    }
    
    func saveContext(_ context: NSManagedObjectContext) throws {
        if context.hasChanges {
            try context.save()
        }
    }
    
    private init() {
        // 遅延初期化のため、ここでは何もしない
        // persistentContainerプロパティへの最初のアクセス時に初期化される
    }
    
    // 非同期でコンテナを初期化する新しいメソッド
    private func loadPersistentContainerAsync() async -> NSPersistentContainer? {
        return await withCheckedContinuation { continuation in
            containerLock.lock()
            
            if let container = _persistentContainer {
                containerLock.unlock()
                continuation.resume(returning: container)
                return
            }
            
            if isInitializing {
                containerLock.unlock()
                continuation.resume(returning: nil)
                return
            }
            
            isInitializing = true
            containerLock.unlock()
            
            let container = NSPersistentContainer(name: "Kipple")
            
            // マイグレーションオプションを設定
            let description = container.persistentStoreDescriptions.first
            description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
            
            container.loadPersistentStores { [weak self] storeDescription, error in
                self?.containerLock.lock()
                defer { self?.containerLock.unlock() }
                
                // isInitializingフラグを必ずリセット
                self?.isInitializing = false
                
                if let error = error as NSError? {
                    Logger.shared.error("Core Data failed to load: \(error), \(error.userInfo)")
                    self?.loadError = error
                    continuation.resume(returning: nil)
                } else {
                    let storeURL = storeDescription.url?.absoluteString ?? "unknown"
                    Logger.shared.log("Core Data loaded successfully at: \(storeURL)")
                    self?.isLoaded = true
                    container.viewContext.automaticallyMergesChangesFromParent = true
                    self?._persistentContainer = container
                    continuation.resume(returning: container)
                }
            }
        }
    }
}

enum CoreDataError: LocalizedError {
    case notLoaded
    
    var errorDescription: String? {
        switch self {
        case .notLoaded:
            return "Core Data is not loaded. Data will be stored in memory only."
        }
    }
}

