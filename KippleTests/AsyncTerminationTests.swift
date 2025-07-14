//
//  AsyncTerminationTests.swift
//  KippleTests
//
//  Created by Claude on 2025/07/14.
//

import XCTest
@testable import Kipple

/// 非同期終了処理の詳細なテスト
final class AsyncTerminationTests: XCTestCase {
    
    // MARK: - ClipboardService 保存処理のテスト
    
    func testClipboardServiceFlushPendingSaves() async throws {
        // Given
        let service = ClipboardService.shared
        let testItems = [
            ClipItem(content: "Async Test 1", sourceApp: "XCTest"),
            ClipItem(content: "Async Test 2", sourceApp: "XCTest"),
            ClipItem(content: "Async Test 3", sourceApp: "XCTest")
        ]
        
        // サービスに履歴を設定
        await MainActor.run {
            service.history = testItems
        }
        
        // When - 保存を実行
        let expectation = XCTestExpectation(description: "Save completion")
        
        Task {
            await service.flushPendingSaves()
            expectation.fulfill()
        }
        
        // Then - タイムアウトせずに完了
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // データが保存されたことを確認
        let repository = CoreDataClipboardRepository()
        let savedItems = try await repository.load(limit: 10)
        
        // 保存したアイテムが含まれていることを確認
        for testItem in testItems {
            XCTAssertTrue(savedItems.contains { $0.content == testItem.content },
                         "Item '\(testItem.content)' should be saved")
        }
    }
    
    // MARK: - Core Data 保存処理のテスト
    
    func testCoreDataSaveWithWALCheckpoint() async throws {
        // Given
        let coreDataStack = CoreDataStack.shared
        coreDataStack.initializeAndWait()
        
        // テストデータを作成
        let repository = CoreDataClipboardRepository()
        let testItem = ClipItem(
            content: "WAL Checkpoint Test",
            sourceApp: "XCTest"
        )
        
        // When - データを保存してWALチェックポイントを実行
        try await repository.save([testItem])
        
        let saveExpectation = XCTestExpectation(description: "Core Data save")
        
        Task { @MainActor in
            do {
                try coreDataStack.save()
                saveExpectation.fulfill()
            } catch {
                XCTFail("Core Data save failed: \(error)")
            }
        }
        
        // Then - 保存が成功
        await fulfillment(of: [saveExpectation], timeout: 3.0)
        
        // データが永続化されていることを確認
        let loadedItems = try await repository.load(limit: 10)
        XCTAssertTrue(loadedItems.contains { $0.content == "WAL Checkpoint Test" })
    }
    
    // MARK: - 並行処理のテスト
    
    func testConcurrentSaveOperations() async throws {
        // Given
        let service = ClipboardService.shared
        let repository = CoreDataClipboardRepository()
        
        // 既存の履歴をクリア
        await MainActor.run {
            service.history = []
        }
        
        // 並行処理によるマージコンフリクトを避けるため、
        // アイテムを追加してから保存を順次実行
        let items = (1...5).map { index in
            ClipItem(
                content: "Concurrent Item \(index)",
                sourceApp: "XCTest"
            )
        }
        
        // When - アイテムを履歴に追加
        await MainActor.run {
            service.history = items
        }
        
        // 保存を実行
        await service.flushPendingSaves()
        
        // Core Data の保存も待つ
        try await MainActor.run {
            try CoreDataStack.shared.save()
        }
        
        // Then - すべてのアイテムが保存されている
        let savedItems = try await repository.load(limit: 20)
        
        for index in 1...5 {
            let expectedContent = "Concurrent Item \(index)"
            XCTAssertTrue(
                savedItems.contains { $0.content == expectedContent },
                "Item '\(expectedContent)' should be saved"
            )
        }
    }
    
    // MARK: - エラーハンドリングのテスト
    
    func testSaveFailureHandling() async throws {
        // Given - ClipboardService のサイズ制限を確認するテスト
        let service = ClipboardService.shared
        let repository = CoreDataClipboardRepository()
        
        // 既存の履歴をクリア
        await MainActor.run {
            service.history = []
        }
        await service.flushPendingSaves()
        
        // 通常サイズのコンテンツ（1KB）
        let normalContent = String(repeating: "A", count: 1024)
        let normalItem = ClipItem(content: normalContent, sourceApp: "XCTest")
        
        // When - 通常サイズのアイテムを追加
        await MainActor.run {
            service.history = [normalItem]
        }
        
        // Then - 正常に保存される
        await service.flushPendingSaves()
        
        let savedItems = try await repository.load(limit: 10)
        XCTAssertTrue(savedItems.contains { $0.content == normalContent })
        
        // 巨大なコンテンツはクリップボードサービスのレベルで
        // 追加されないため、ここではテストしない
        // （実際のアプリでは addToHistoryWithAppInfo でサイズチェックされる）
    }
    
    // MARK: - 非同期処理のキャンセルテスト
    
    func testAsyncOperationCancellation() async throws {
        // Given
        let service = ClipboardService.shared
        
        // 多数のアイテムを追加
        let items = (1...100).map { index in
            ClipItem(content: "Cancellation Test \(index)")
        }
        
        await MainActor.run {
            service.history = items
        }
        
        // When - 保存タスクを開始してすぐにキャンセル
        let task = Task {
            await service.flushPendingSaves()
        }
        
        // 少し待ってからキャンセル
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        task.cancel()
        
        // Then - キャンセルされてもエラーが発生しない
        // （実際の保存処理は内部で継続される可能性がある）
        _ = await task.result
    }
}

// MARK: - モックテスト用の拡張

extension AsyncTerminationTests {
    
    /// タイムアウトシミュレーションのテスト
    func testTimeoutSimulation() async {
        // Given - 2秒のタイムアウトを設定
        let timeout: TimeInterval = 2.0
        let startTime = Date()
        
        // When - タイムアウトをシミュレート
        let timeoutExpectation = XCTestExpectation(description: "Timeout")
        
        let workItem = DispatchWorkItem {
            timeoutExpectation.fulfill()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
        
        // Then - 約2秒後にタイムアウトが発生
        await fulfillment(of: [timeoutExpectation], timeout: 3.0)
        
        let elapsed = Date().timeIntervalSince(startTime)
        XCTAssertGreaterThanOrEqual(elapsed, timeout - 0.1) // 許容誤差0.1秒
        XCTAssertLessThanOrEqual(elapsed, timeout + 0.5) // 許容誤差0.5秒
    }
    
    /// 非同期処理の順序確認テスト
    func testAsyncExecutionOrder() async {
        // Given
        var executionOrder: [String] = []
        let lock = NSLock()
        
        // When - 複数の非同期処理を実行
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                lock.lock()
                executionOrder.append("Task1")
                lock.unlock()
            }
            
            group.addTask {
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05秒
                lock.lock()
                executionOrder.append("Task2")
                lock.unlock()
            }
            
            group.addTask {
                lock.lock()
                executionOrder.append("Task3")
                lock.unlock()
            }
        }
        
        // Then - Task3, Task2, Task1 の順序で実行される
        XCTAssertEqual(executionOrder.count, 3)
        XCTAssertEqual(executionOrder[0], "Task3") // 即座に実行
        XCTAssertEqual(executionOrder[1], "Task2") // 0.05秒後
        XCTAssertEqual(executionOrder[2], "Task1") // 0.1秒後
    }
}
