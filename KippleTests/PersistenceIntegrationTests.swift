//
//  PersistenceIntegrationTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/13.
//

import XCTest
import CoreData
@testable import Kipple

final class PersistenceIntegrationTests: XCTestCase {
    
    func testRealWorldPersistenceScenario() async throws {
        // アプリの実際の使用シナリオをシミュレート
        let repository = CoreDataClipboardRepository()
        
        // 1. 初期状態: 空のデータベース
        try await repository.clear(keepPinned: false)
        var loadedItems = try await repository.load(limit: 100)
        XCTAssertEqual(loadedItems.count, 0, "Should start with empty database")
        
        // 2. ユーザーがクリップボードにコピー（履歴に追加）
        var history: [ClipItem] = []
        let item1 = ClipItem(content: "First Copy", sourceApp: "TextEdit")
        history.insert(item1, at: 0)
        
        // デバウンスをシミュレート（実際はClipboardServiceで1秒後に保存）
        try await repository.save(history)
        
        // 3. 読み込んで確認
        loadedItems = try await repository.load(limit: 100)
        XCTAssertEqual(loadedItems.count, 1)
        XCTAssertEqual(loadedItems.first?.content, "First Copy")
        
        // 4. 新しいアイテムを追加（既存の履歴を保持しながら）
        let item2 = ClipItem(content: "Second Copy", sourceApp: "Safari")
        history.insert(item2, at: 0)
        try await repository.save(history)
        
        // 5. 読み込んで確認
        loadedItems = try await repository.load(limit: 100)
        XCTAssertEqual(loadedItems.count, 2)
        XCTAssertEqual(loadedItems[0].content, "Second Copy")
        XCTAssertEqual(loadedItems[1].content, "First Copy")
        
        // 6. アプリを終了して再起動をシミュレート
        // WALチェックポイントを実行
        await MainActor.run {
            CoreDataStack.shared.checkpointWAL()
        }
        
        // 新しいリポジトリインスタンスで読み込み（アプリ再起動をシミュレート）
        let newRepository = CoreDataClipboardRepository()
        let reloadedItems = try await newRepository.load(limit: 100)
        
        // データが永続化されていることを確認
        XCTAssertEqual(reloadedItems.count, 2, "Data should persist after simulated restart")
        XCTAssertEqual(reloadedItems[0].content, "Second Copy")
        XCTAssertEqual(reloadedItems[1].content, "First Copy")
    }
    
    func testConcurrentSaveOperations() async throws {
        // 並行保存操作のテスト
        let repository = CoreDataClipboardRepository()
        try await repository.clear(keepPinned: false)
        
        // 複数の保存操作を並行して実行
        await withTaskGroup(of: Void.self) { group in
            for i in 1...5 {
                group.addTask {
                    let item = ClipItem(content: "Concurrent Item \(i)", sourceApp: "App \(i)")
                    // 注意: 実際のアプリでは全履歴を保存するが、テストでは単一アイテムを保存
                    // これにより最後の1つだけが残る
                    try? await repository.save([item])
                }
            }
        }
        
        // 少し待つ
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        
        // 最後の保存操作の結果を確認
        let items = try await repository.load(limit: 100)
        XCTAssertGreaterThan(items.count, 0, "At least one item should be saved")
        XCTAssertTrue(items.first?.content.contains("Concurrent Item") ?? false)
    }
    
    func testWALCheckpoint() async throws {
        // WALチェックポイントの動作確認
        let repository = CoreDataClipboardRepository()
        let coreDataStack = CoreDataStack.shared
        
        // データを保存
        let testItem = ClipItem(content: "WAL Test Item", sourceApp: "Test")
        try await repository.save([testItem])
        
        // WALファイルの存在を確認（間接的に）
        // チェックポイント前に読み込み
        var items = try await repository.load(limit: 100)
        XCTAssertEqual(items.count, 1)
        
        // WALチェックポイントを実行
        await MainActor.run {
            coreDataStack.checkpointWAL()
        }
        
        // チェックポイント後も読み込めることを確認
        items = try await repository.load(limit: 100)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.content, "WAL Test Item")
    }
}
