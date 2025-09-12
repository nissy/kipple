//
//  CoreDataStack.swift
//  Kipple
//
//  Created by Kipple on 2025/07/11.
//

import Foundation
import CoreData
import SQLite3

class CoreDataStack {
    static let shared = CoreDataStack()
    
    private var _persistentContainer: NSPersistentContainer?
    private let containerLock = NSLock()
    private var isInitializing = false
    private(set) var isLoaded = false
    private(set) var loadError: Error?
    private let initializationSemaphore = DispatchSemaphore(value: 0)
    private let isTestEnvironment: Bool
    // WAL checkpoint scheduling/guard
    private var checkpointTimer: Timer? // deprecated path (kept for compatibility)
    private var checkpointTimerSource: DispatchSourceTimer?
    private let checkpointQueue = DispatchQueue(label: "com.nissy.kipple.coredata.checkpoint", qos: .utility)
    private let checkpointStateLock = NSLock()
    private var isCheckpointing = false
    
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
        
        // WALチェックポイントはUIをブロックしないよう非同期で実行
        checkpointQueue.async { [weak self] in
            self?.checkpointWAL()
        }
    }
    
    // WALをメインデータベースにマージする
    func checkpointWAL() {
        // 競合防止（多重実行を避ける）
        checkpointStateLock.lock()
        if isCheckpointing { checkpointStateLock.unlock(); return }
        isCheckpointing = true
        checkpointStateLock.unlock()
        defer {
            checkpointStateLock.lock(); isCheckpointing = false; checkpointStateLock.unlock()
        }
        guard let path = databasePath() else { return }
        autoreleasepool {
            saveMainViewContextIfNeeded()
            guard let db = openDatabase(atPath: path) else { return }
            defer { sqlite3_close(db) }
            executeCheckpoint(on: db)
        }
    }

    private func databasePath() -> String? {
        guard let coordinator = _persistentContainer?.persistentStoreCoordinator,
              let store = coordinator.persistentStores.first,
              let url = store.url else { return nil }
        return url.path
    }

    private func saveMainViewContextIfNeeded() {
        do {
            if let ctx = viewContext, ctx.hasChanges {
                try ctx.save()
            }
        } catch {
            Logger.shared.error("Failed to save viewContext before WAL checkpoint: \(error)")
        }
    }

    private func openDatabase(atPath path: String) -> OpaquePointer? {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(path, &db, flags, nil)
        guard openResult == SQLITE_OK, let opened = db else {
            Logger.shared.error("sqlite3_open_v2 failed for WAL checkpoint: code=\(openResult)")
            return nil
        }
        sqlite3_busy_timeout(opened, 1000)
        return opened
    }

    private func executeCheckpoint(on db: OpaquePointer) {
        if sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil) == SQLITE_OK {
            _ = sqlite3_exec(db, "PRAGMA optimize;", nil, nil, nil)
            Logger.shared.log("WAL checkpoint (TRUNCATE) executed successfully")
        } else if let err = sqlite3_errmsg(db) {
            Logger.shared.error("WAL checkpoint failed: \(String(cString: err))")
        } else {
            Logger.shared.error("WAL checkpoint failed with unknown error")
        }
    }
    
    func saveContext(_ context: NSManagedObjectContext) throws {
        if context.hasChanges {
            try context.save()
        }
    }
    
    private init() {
        isTestEnvironment = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        
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
            if isTestEnvironment {
                // テスト用の一時ファイルを使用（メモリ内ストアの代わり）
                let tempDir = FileManager.default.temporaryDirectory
                let testDBURL = tempDir.appendingPathComponent("KippleTest.sqlite")
                description?.url = testDBURL
                description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
                description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
                
                // 既存のテストDBファイルを削除
                try? FileManager.default.removeItem(at: testDBURL)
                let walURL = testDBURL.appendingPathExtension("wal")
                let shmURL = testDBURL.appendingPathExtension("shm")
                try? FileManager.default.removeItem(at: walURL)
                try? FileManager.default.removeItem(at: shmURL)
            } else {
                description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
                description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
            }
            // SQLite PRAGMA 最適化（WAL + 同期軽減）
            let pragmas: [String: Any] = [
                "journal_mode": "WAL",
                "synchronous": "NORMAL"
            ]
            description?.setOption(pragmas as NSDictionary, forKey: NSSQLitePragmasOption)
            
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
                    
                    // SQLiteファイルの実際のパスをログに出力（テスト時は除外）
                    if let url = storeDescription.url, !(self?.isTestEnvironment ?? false) {
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
                    container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                    container.viewContext.shouldDeleteInaccessibleFaults = true
                    self?._persistentContainer = container
                    self?.startCheckpointTimerIfNeeded()
                    self?.initializationSemaphore.signal()
                    continuation.resume(returning: container)
                }
            }
        }
    }
    
    // テスト用のデータベースクリーンアップ
    func resetForTesting() {
        guard isTestEnvironment else { return }
        
        // タイマー解除
        checkpointTimer?.invalidate(); checkpointTimer = nil
        checkpointTimerSource?.cancel(); checkpointTimerSource = nil

        containerLock.lock()
        defer { containerLock.unlock() }
        
        // 現在のコンテナをクリア
        _persistentContainer = nil
        isLoaded = false
        loadError = nil
        
        // 一時ファイルを削除
        let tempDir = FileManager.default.temporaryDirectory
        let testDBURL = tempDir.appendingPathComponent("KippleTest.sqlite")
        try? FileManager.default.removeItem(at: testDBURL)
        let walURL = testDBURL.appendingPathExtension("wal")
        let shmURL = testDBURL.appendingPathExtension("shm")
        try? FileManager.default.removeItem(at: walURL)
        try? FileManager.default.removeItem(at: shmURL)
    }

    // MARK: - Periodic WAL checkpoint
    private func startCheckpointTimerIfNeeded() {
        guard !isTestEnvironment, checkpointTimerSource == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: checkpointQueue)
        timer.schedule(deadline: .now() + .seconds(1800), repeating: .seconds(1800), leeway: .seconds(60))
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isLoaded else { return }
            self.checkpointWAL()
        }
        checkpointTimerSource = timer
        timer.resume()
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
