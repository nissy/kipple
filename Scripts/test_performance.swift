#!/usr/bin/env swift

//
//  test_performance.swift
//  Kipple Performance Test
//
//  Core Dataでの大量データパフォーマンステスト
//

import Foundation
import CoreData

// ClipItemの簡易版
struct TestClipItem: Codable {
    let id = UUID()
    let content: String
    let timestamp = Date()
    let isPinned = false
    let kind = "text"
}

// パフォーマンステスト
func testPerformance() {
    print("Kipple Core Data Performance Test")
    print("=================================")
    
    // データベースパス
    let dbPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Kipple/Kipple.sqlite")
    
    print("Database path: \(dbPath.path)")
    
    // データベースのサイズを確認
    if let attributes = try? FileManager.default.attributesOfItem(atPath: dbPath.path) {
        let fileSize = attributes[.size] as? Int64 ?? 0
        let sizeMB = Double(fileSize) / 1024.0 / 1024.0
        print("Current database size: \(String(format: "%.2f", sizeMB)) MB")
    }
    
    // SQLiteコマンドでアイテム数を確認
    let countCommand = "sqlite3 '\(dbPath.path)' 'SELECT COUNT(*) FROM ZCLIPITEMENTITY;'"
    let countProcess = Process()
    countProcess.launchPath = "/bin/bash"
    countProcess.arguments = ["-c", countCommand]
    
    let countPipe = Pipe()
    countProcess.standardOutput = countPipe
    
    countProcess.launch()
    countProcess.waitUntilExit()
    
    let countData = countPipe.fileHandleForReading.readDataToEndOfFile()
    if let countString = String(data: countData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
        print("Current item count: \(countString)")
    }
    
    // 1000件のテストデータを生成
    print("\nGenerating 1000 test items…")
    let testItems = (1...1000).map { i in
        TestClipItem(content: "Performance test item \(i) - " + String(repeating: "Lorem ipsum ", count: 10))
    }
    
    // メモリ使用量を計算
    let encoder = JSONEncoder()
    if let data = try? encoder.encode(testItems) {
        let sizeMB = Double(data.count) / 1024.0 / 1024.0
        print("Test data size in memory: \(String(format: "%.2f", sizeMB)) MB")
    }
    
    print("\nPerformance test completed!")
    print("\nNote: To test actual performance:")
    print("1. Run Kipple app")
    print("2. Copy many items to clipboard")
    print("3. Check app responsiveness")
    print("4. Monitor Activity Monitor for memory usage")
}

// メイン実行
testPerformance()