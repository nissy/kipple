//
//  ClipboardServiceProtocol.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import Foundation

protocol ClipboardServiceProtocol: AnyObject {
    var history: [ClipItem] { get }
    var pinnedItems: [ClipItem] { get }
    var currentClipboardContent: String? { get }
    var onHistoryChanged: ((ClipItem) -> Void)? { get set }
    
    func startMonitoring()
    func stopMonitoring()
    func copyToClipboard(_ content: String, fromEditor: Bool)
    func clearAllHistory()
    func togglePin(for item: ClipItem) -> Bool
    func deleteItem(_ item: ClipItem)
}
