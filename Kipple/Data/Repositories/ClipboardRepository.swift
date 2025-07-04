//
//  ClipboardRepository.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import Foundation

class ClipboardRepository {
    private let userDefaults = UserDefaults.standard
    private let clipboardHistoryKey = "com.Kipple.clipboardHistory"
    private let maxStoredItems = 100
    
    @discardableResult
    func save(_ items: [ClipItem]) -> Bool {
        // Limit stored items to prevent excessive storage
        let itemsToSave = Array(items.prefix(maxStoredItems))
        
        do {
            let encoded = try JSONEncoder().encode(itemsToSave)
            userDefaults.set(encoded, forKey: clipboardHistoryKey)
            return true
        } catch {
            Logger.shared.error("Failed to save clipboard history: \(error.localizedDescription)")
            // エラーが発生してもデータは削除しない
            return false
        }
    }
    
    func load() -> [ClipItem] {
        guard let data = userDefaults.data(forKey: clipboardHistoryKey) else {
            return []
        }
        
        do {
            let items = try JSONDecoder().decode([ClipItem].self, from: data)
            // Filter out items older than 7 days
            let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            return items.filter { $0.timestamp > sevenDaysAgo }
        } catch {
            Logger.shared.error("Error loading clipboard history: \(error.localizedDescription)")
            Logger.shared.warning("Clearing corrupted data")
            // 破損したデータをクリア
            clear()
            return []
        }
    }
    
    func clear() {
        userDefaults.removeObject(forKey: clipboardHistoryKey)
    }
}
