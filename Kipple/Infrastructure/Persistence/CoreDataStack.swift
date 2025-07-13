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
    private let initializationSemaphore = DispatchSemaphore(value: 0)
    
    var persistentContainer: NSPersistentContainer? {
        containerLock.lock()
        defer { containerLock.unlock() }
        
        if let container = _persistentContainer {
            return container
        }
        
        // 初期化がまだの場合は、初期化完了を待つ
        if !isLoaded && !isInitializing {
            containerLock.unlock()
            initializeAndWait()
            containerLock.lock()
        }
        
        return _persistentContainer
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
        
        // WALチェックポイントを強制的に実行
        checkpointWAL()
    }
    
    // WALをメインデータベースにマージする
    func checkpointWAL() {
        guard let container = _persistentContainer else {
            return
        }
        
        // すべてのコンテキストの変更を保存
        do {
            // viewContextの変更を保存
            if let viewContext = viewContext, viewContext.hasChanges {
                try viewContext.save()
            }
            
            // NSSQLiteManualVacuumOption を使用してWALをチェックポイント
            if let store = container.persistentStoreCoordinator.persistentStores.first,
               let storeURL = store.url {
                
                // 現在のストアのオプションを取得
                var options = store.options ?? [:]
                
                // 手動バキュームオプションを設定（これによりWALがチェックポイントされる）
                options[NSSQLiteManualVacuumOption] = true
                
                // ストアを削除して再追加
                try container.persistentStoreCoordinator.remove(store)
                
                _ = try container.persistentStoreCoordinator.addPersistentStore(
                    ofType: store.type,
                    configurationName: store.configurationName,
                    at: storeURL,
                    options: options
                )
                
                Logger.shared.log("WAL checkpoint completed with manual vacuum")
            }
        } catch {
            Logger.shared.error("Failed to checkpoint WAL: \(error)")
        }
    }
    
    func saveContext(_ context: NSManagedObjectContext) throws {
        if context.hasChanges {
            try context.save()
        }
    }
    
    private init() {
        // アプリ起動時に非同期で初期化を開始
        Task {
            await loadPersistentContainerAsync()
        }
    }
    
    // 同期的に初期化を待つメソッド
    func initializeAndWait() {
        if isLoaded || loadError != nil {
            return
        }
        
        // 最大5秒待つ
        let result = initializationSemaphore.wait(timeout: .now() + 5)
        if result == .timedOut {
            Logger.shared.error("Core Data initialization timed out")
        }
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
                    self?.initializationSemaphore.signal()
                    continuation.resume(returning: nil)
                } else {
                    let storeURL = storeDescription.url?.absoluteString ?? "unknown"
                    Logger.shared.log("Core Data loaded successfully at: \(storeURL)")
                    
                    // SQLiteファイルの実際のパスをログに出力
                    if let url = storeDescription.url {
                        Logger.shared.log("SQLite file path: \(url.path)")
                        
                        // ファイルの存在とサイズを確認
                        let fileManager = FileManager.default
                        if fileManager.fileExists(atPath: url.path) {
                            do {
                                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                                if let fileSize = attributes[.size] as? NSNumber {
                                    Logger.shared.log("SQLite file size: \(fileSize.intValue) bytes")
                                }
                            } catch {
                                Logger.shared.error("Failed to get file attributes: \(error)")
                            }
                        }
                    }
                    
                    self?.isLoaded = true
                    container.viewContext.automaticallyMergesChangesFromParent = true
                    self?._persistentContainer = container
                    self?.initializationSemaphore.signal()
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
